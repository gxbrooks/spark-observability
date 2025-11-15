package com.elastic.spark.otel

import org.apache.spark.scheduler._
import io.opentelemetry.api.GlobalOpenTelemetry
import io.opentelemetry.api.trace.{Span, SpanKind, StatusCode, Tracer}
import io.opentelemetry.context.Context
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter
import io.opentelemetry.semconv.ResourceAttributes
import org.slf4j.LoggerFactory

import java.time.{Duration, Instant}
import scala.collection.concurrent.TrieMap
import scala.util.Try

/**
 * Custom SparkListener that exports telemetry to OpenTelemetry Collector via OTLP.
 *
 * This listener captures Spark application lifecycle events (Job, Stage, Task) and
 * converts them into OpenTelemetry spans with proper parent-child relationships.
 *
 * Configuration via environment variables:
 *  - OTEL_EXPORTER_OTLP_ENDPOINT: Collector endpoint (default: http://otel-collector:4317)
 *  - OTEL_SERVICE_NAME: Service name (default: spark-application)
 *  - OTEL_SERVICE_NAMESPACE: Service namespace (default: spark)
 *  - SPARK_APP_NAME: Spark application name (from SparkConf)
 *
 * Usage:
 *  spark.extraListeners=com.elastic.spark.otel.OTelSparkListener
 *  spark.jars=/path/to/spark-otel-listener-1.0.0.jar
 */
class OTelSparkListener extends SparkListener {

  private val logger = LoggerFactory.getLogger(classOf[OTelSparkListener])

  // Configuration from environment
  private val otlpEndpoint = sys.env.getOrElse(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://otel-collector.observability.svc.cluster.local:4317"
  )
  
  private val serviceName = sys.env.getOrElse("OTEL_SERVICE_NAME", "spark-application")
  private val serviceNamespace = sys.env.getOrElse("OTEL_SERVICE_NAMESPACE", "spark")
  private val deploymentEnvironment = sys.env.getOrElse("OTEL_DEPLOYMENT_ENVIRONMENT", "production")

  // Initialize OpenTelemetry
  private val spanExporter: OtlpGrpcSpanExporter = Try {
    OtlpGrpcSpanExporter.builder()
      .setEndpoint(otlpEndpoint)
      .build()
  }.recover {
    case e: Exception =>
      logger.error(s"Failed to create OTLP exporter for endpoint $otlpEndpoint", e)
      throw e
  }.get

  private val resource: Resource = Resource.getDefault.toBuilder
    .put(ResourceAttributes.SERVICE_NAME, serviceName) 
    .put(ResourceAttributes.SERVICE_NAMESPACE, serviceNamespace)
    .put(ResourceAttributes.DEPLOYMENT_ENVIRONMENT, deploymentEnvironment)
    .build()

  private val tracerProvider: SdkTracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(
      BatchSpanProcessor.builder(spanExporter)
        .setMaxQueueSize(2048)
        .setMaxExportBatchSize(512)
        .setScheduleDelay(Duration.ofMillis(1000))
        .build()
    )
    .setResource(resource)
    .build()

  // Register as global to make it accessible
  private val openTelemetry: OpenTelemetrySdk = OpenTelemetrySdk.builder()
    .setTracerProvider(tracerProvider)
    .buildAndRegisterGlobal()

  private val tracer: Tracer = openTelemetry.getTracer("spark-listener", "1.0.0")

  // Track active spans for proper parent-child relationships
  private val applicationSpan: TrieMap[String, Span] = TrieMap.empty
  private val jobSpans: TrieMap[Int, Span] = TrieMap.empty
  private val stageSpans: TrieMap[Int, Span] = TrieMap.empty
  private val taskSpans: TrieMap[Long, Span] = TrieMap.empty
  // private val sqlExecutionSpans: TrieMap[Long, Span] = TrieMap.empty  // Disabled until SQL listener interface is available

  logger.info(s"OTelSparkListener initialized - OTLP endpoint: $otlpEndpoint, service: $serviceName")

  override def onApplicationStart(applicationStart: SparkListenerApplicationStart): Unit = {
    try {
      val appName = applicationStart.appName
      val appId = applicationStart.appId.getOrElse("unknown")
      val user = applicationStart.sparkUser
      val startTime = applicationStart.time

      logger.info(s"Application started: $appName (ID: $appId, User: $user)")

      val span = tracer.spanBuilder(s"spark.application.$appName")
        .setSpanKind(SpanKind.SERVER)
        .setStartTimestamp(Instant.ofEpochMilli(startTime))
        .setAttribute("spark.app.name", appName)
        .setAttribute("spark.app.id", appId)
        .setAttribute("spark.user", user)
        .setAttribute("service.name", serviceName)
        .setAttribute("span.kind", "Spark.app")
        .startSpan()

      applicationSpan.put(appId, span)
    } catch {
      case e: Exception =>
        logger.error("Error in onApplicationStart", e)
    }
  }

  override def onApplicationEnd(applicationEnd: SparkListenerApplicationEnd): Unit = {
    try {
      val endTime = applicationEnd.time

      logger.info(s"Application ended at $endTime")

      applicationSpan.values.foreach { span =>
        span.setStatus(StatusCode.OK)
        span.end(Instant.ofEpochMilli(endTime))
      }
      applicationSpan.clear()

      // Shutdown OpenTelemetry to flush remaining spans
      tracerProvider.close()
      logger.info("OTelSparkListener shutdown complete")
    } catch {
      case e: Exception =>
        logger.error("Error in onApplicationEnd", e)
    }
  }

  override def onJobStart(jobStart: SparkListenerJobStart): Unit = {
    try {
      val jobId = jobStart.jobId
      val stageIds = jobStart.stageIds
      val stageInfos = jobStart.stageInfos
      val time = jobStart.time

      logger.debug(s"Job $jobId started with ${stageIds.length} stages")

      // Get parent context from application span
      val parentSpan = applicationSpan.values.headOption

      val spanBuilder = tracer.spanBuilder(s"spark.job.$jobId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(time))
        .setAttribute("spark.job.id", jobId.toLong)
        .setAttribute("spark.job.stage.count", stageIds.length.toLong)
        .setAttribute("span.kind", "Spark.job")

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      // Add stage information
      if (stageInfos.nonEmpty) {
        val stageNames = stageInfos.map(_.name).mkString(", ")
        spanBuilder.setAttribute("spark.job.stages", stageNames)
      }

      // Check if this job was spawned by a SQL execution
      val sqlExecutionId = jobStart.properties.getProperty("spark.sql.execution.id")
      if (sqlExecutionId != null && sqlExecutionId.nonEmpty) {
        spanBuilder.setAttribute("spark.job.sql.execution.id", sqlExecutionId.toLong)
        // Note: SQL execution span linking disabled until SQL listener interface is available
        // sqlExecutionSpans.get(sqlExecutionId.toLong).foreach { sqlSpan =>
        //   spanBuilder.setParent(Context.current().`with`(sqlSpan))
        // }
      }

      val span = spanBuilder.startSpan()
      jobSpans.put(jobId, span)
    } catch {
      case e: Exception =>
        logger.error(s"Error in onJobStart for job ${jobStart.jobId}", e)
    }
  }

  override def onJobEnd(jobEnd: SparkListenerJobEnd): Unit = {
    try {
      val jobId = jobEnd.jobId
      val time = jobEnd.time

      logger.debug(s"Job $jobId ended: ${jobEnd.jobResult}")

      jobSpans.remove(jobId).foreach { span =>
        // Set status based on job result
        jobEnd.jobResult match {
          case JobSucceeded =>
            span.setStatus(StatusCode.OK)
            span.setAttribute("spark.job.result", "SUCCESS")
          case JobFailed(exception) =>
            span.setStatus(StatusCode.ERROR, exception.getMessage)
            span.setAttribute("spark.job.result", "FAILED")
            span.setAttribute("spark.job.error", exception.getMessage)
            span.recordException(exception)
        }
        span.end(Instant.ofEpochMilli(time))
      }
    } catch {
      case e: Exception =>
        logger.error(s"Error in onJobEnd for job ${jobEnd.jobId}", e)
    }
  }

  override def onStageSubmitted(stageSubmitted: SparkListenerStageSubmitted): Unit = {
    try {
      val stageInfo = stageSubmitted.stageInfo
      val stageId = stageInfo.stageId
      val stageName = stageInfo.name
      val numTasks = stageInfo.numTasks
      val attemptNumber = stageInfo.attemptNumber()
      val submissionTime = stageInfo.submissionTime.getOrElse(System.currentTimeMillis())

      logger.debug(s"Stage $stageId submitted: $stageName ($numTasks tasks)")

      // Try to get parent job span - in Spark 4.0, we need to find it from active jobs
      // For simplicity, we'll use the first available job span
      val parentSpan = jobSpans.values.headOption

      val spanBuilder = tracer.spanBuilder(s"spark.stage.$stageId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(submissionTime))
        .setAttribute("spark.stage.id", stageId.toLong)
        .setAttribute("spark.stage.name", stageName)
        .setAttribute("spark.stage.num.tasks", numTasks.toLong)
        .setAttribute("spark.stage.attempt", attemptNumber.toLong)
        .setAttribute("span.kind", "Spark.stage")

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      // Add parent stage information if this is a retry
      if (attemptNumber > 0) {
        spanBuilder.setAttribute("spark.stage.is.retry", true)
      }

      val span = spanBuilder.startSpan()
      stageSpans.put(stageId, span)
    } catch {
      case e: Exception =>
        logger.error(s"Error in onStageSubmitted for stage ${stageSubmitted.stageInfo.stageId}", e)
    }
  }

  override def onStageCompleted(stageCompleted: SparkListenerStageCompleted): Unit = {
    try {
      val stageInfo = stageCompleted.stageInfo
      val stageId = stageInfo.stageId
      val completionTime = stageInfo.completionTime.getOrElse(System.currentTimeMillis())

      logger.debug(s"Stage $stageId completed")

      stageSpans.remove(stageId).foreach { span =>
        // Add metrics
        val taskMetrics = stageInfo.taskMetrics
        span.setAttribute("spark.stage.tasks.completed", stageInfo.numTasks.toLong)
        
        if (taskMetrics != null) {
          span.setAttribute("spark.stage.shuffle.read.bytes", taskMetrics.shuffleReadMetrics.totalBytesRead)
          span.setAttribute("spark.stage.shuffle.write.bytes", taskMetrics.shuffleWriteMetrics.bytesWritten)
          span.setAttribute("spark.stage.input.bytes", taskMetrics.inputMetrics.bytesRead)
          span.setAttribute("spark.stage.output.bytes", taskMetrics.outputMetrics.bytesWritten)
          span.setAttribute("spark.stage.memory.spilled.bytes", taskMetrics.memoryBytesSpilled)
          span.setAttribute("spark.stage.disk.spilled.bytes", taskMetrics.diskBytesSpilled)
        }

        // Set status based on failure
        if (stageInfo.failureReason.isDefined) {
          span.setStatus(StatusCode.ERROR, stageInfo.failureReason.get)
          span.setAttribute("spark.stage.result", "FAILED")
          span.setAttribute("spark.stage.error", stageInfo.failureReason.get)
        } else {
          span.setStatus(StatusCode.OK)
          span.setAttribute("spark.stage.result", "SUCCESS")
        }

        span.end(Instant.ofEpochMilli(completionTime))
      }
    } catch {
      case e: Exception =>
        logger.error(s"Error in onStageCompleted for stage ${stageCompleted.stageInfo.stageId}", e)
    }
  }

  override def onTaskStart(taskStart: SparkListenerTaskStart): Unit = {
    // Task-level spans can be high volume - only emit for failed tasks or sample
    // For now, we'll create spans for all tasks, but this can be made configurable
    try {
      val stageId = taskStart.stageId
      val taskInfo = taskStart.taskInfo

      logger.debug(s"Task ${taskInfo.taskId} started in stage $stageId")

      // Get parent stage span
      val parentSpan = stageSpans.get(stageId)

      val spanBuilder = tracer.spanBuilder(s"spark.task.${taskInfo.taskId}")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(taskInfo.launchTime))
        .setAttribute("spark.task.id", taskInfo.taskId)
        .setAttribute("spark.task.index", taskInfo.index.toLong)
        .setAttribute("spark.task.attempt", taskInfo.attemptNumber.toLong)
        .setAttribute("spark.task.stage.id", stageId.toLong)
        .setAttribute("spark.task.executor.id", taskInfo.executorId)
        .setAttribute("span.kind", "Spark.task")

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      val span = spanBuilder.startSpan()
      taskSpans.put(taskInfo.taskId, span)
    } catch {
      case e: Exception =>
        logger.error(s"Error in onTaskStart for task in stage ${taskStart.stageId}", e)
    }
  }

  override def onTaskEnd(taskEnd: SparkListenerTaskEnd): Unit = {
    try {
      val taskInfo = taskEnd.taskInfo
      val taskMetrics = taskEnd.taskMetrics

      // Get the span we created in onTaskStart
      taskSpans.remove(taskInfo.taskId).foreach { span =>
        logger.debug(s"Task ${taskInfo.taskId} ended in stage ${taskEnd.stageId}: ${taskEnd.reason}")

        // Add task metrics
        if (taskMetrics != null) {
          span.setAttribute("spark.task.executor.run.time.ms", taskMetrics.executorRunTime)
          span.setAttribute("spark.task.executor.cpu.time.ms", taskMetrics.executorCpuTime / 1000000)
          span.setAttribute("spark.task.result.size.bytes", taskMetrics.resultSize)
        }

        // Set status based on task result
        taskEnd.reason match {
          case _: org.apache.spark.Success.type =>
            span.setStatus(StatusCode.OK)
          case other =>
            span.setStatus(StatusCode.ERROR, other.toString)
            span.setAttribute("spark.task.failure.reason", other.toString)
        }

        span.end(Instant.ofEpochMilli(taskInfo.finishTime))
      }
    } catch {
      case e: Exception =>
        logger.error(s"Error in onTaskEnd for task in stage ${taskEnd.stageId}", e)
    }
  }

  // Note: SQL execution events (SparkListenerSQLExecutionStart/End) are not part of the
  // standard SparkListener interface in Spark 4.0. They require a separate listener interface
  // (SparkListenerInterface) or spark-sql dependency. These methods are commented out until
  // we can verify the correct interface/package for Spark 4.0.
  //
  // override def onSQLExecutionStart(sqlExecutionStart: SparkListenerSQLExecutionStart): Unit = {
  //   ...
  // }
  //
  // override def onSQLExecutionEnd(sqlExecutionEnd: SparkListenerSQLExecutionEnd): Unit = {
  //   ...
  // }

  override def onExecutorAdded(executorAdded: SparkListenerExecutorAdded): Unit = {
    try {
      val executorId = executorAdded.executorId
      val executorInfo = executorAdded.executorInfo
      val time = executorAdded.time

      logger.info(s"Executor $executorId added: ${executorInfo.executorHost}")

      // Get parent application span
      val parentSpan = applicationSpan.values.headOption

      val spanBuilder = tracer.spanBuilder(s"spark.executor.$executorId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(time))
        .setAttribute("spark.executor.id", executorId)
        .setAttribute("spark.executor.host", executorInfo.executorHost)
        .setAttribute("spark.executor.total.cores", executorInfo.totalCores.toLong)
        .setAttribute("span.kind", "Spark.executor")

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      val span = spanBuilder.startSpan()
      span.setStatus(StatusCode.OK)
      // Executor added is a point-in-time event, so we end it immediately
      span.end(Instant.ofEpochMilli(time))
    } catch {
      case e: Exception =>
        logger.error(s"Error in onExecutorAdded for executor ${executorAdded.executorId}", e)
    }
  }

  override def onExecutorRemoved(executorRemoved: SparkListenerExecutorRemoved): Unit = {
    try {
      val executorId = executorRemoved.executorId
      val reason = executorRemoved.reason
      val time = executorRemoved.time

      logger.info(s"Executor $executorId removed: $reason")

      // Get parent application span
      val parentSpan = applicationSpan.values.headOption

      val spanBuilder = tracer.spanBuilder(s"spark.executor.$executorId.removed")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(time))
        .setAttribute("spark.executor.id", executorId)
        .setAttribute("spark.executor.removal.reason", reason)
        .setAttribute("span.kind", "Spark.executor.removed")

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      val span = spanBuilder.startSpan()
      span.setStatus(StatusCode.OK)
      // Executor removed is a point-in-time event, so we end it immediately
      span.end(Instant.ofEpochMilli(time))
    } catch {
      case e: Exception =>
        logger.error(s"Error in onExecutorRemoved for executor ${executorRemoved.executorId}", e)
    }
  }
}

