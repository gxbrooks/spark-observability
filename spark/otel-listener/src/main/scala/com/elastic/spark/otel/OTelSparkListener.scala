package com.elastic.spark.otel

import org.apache.spark.scheduler._
import org.apache.spark.sql.execution.ui.{SparkListenerSQLExecutionStart, SparkListenerSQLExecutionEnd}
import io.opentelemetry.api.GlobalOpenTelemetry
import io.opentelemetry.api.trace.{Span, SpanKind, StatusCode, Tracer}
import io.opentelemetry.context.Context
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.{BatchSpanProcessor, SimpleSpanProcessor}
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter
import io.opentelemetry.exporter.logging.LoggingSpanExporter
import io.opentelemetry.semconv.ResourceAttributes
import org.slf4j.LoggerFactory

import java.time.{Duration, Instant}
import java.time.format.DateTimeFormatter
import java.util.UUID
import scala.collection.concurrent.TrieMap
import scala.util.{Try, Success, Failure}

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
  private val enableLoggingExporter = sys.env.getOrElse("OTEL_ENABLE_LOGGING", "false").toLowerCase == "true"
  private val emitTaskEvents = sys.env.getOrElse("OTEL_EMIT_TASK_EVENTS", "true").toLowerCase == "true"

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

  private val tracerProviderBuilder = SdkTracerProvider.builder()
    .addSpanProcessor(
      BatchSpanProcessor.builder(spanExporter)
        .setMaxQueueSize(2048)
        .setMaxExportBatchSize(512)
        .setScheduleDelay(Duration.ofMillis(1000))
        .build()
    )
    .setResource(resource)
  
  // Add logging exporter if enabled (for testing without OTEL Collector)
  private val tracerProvider: SdkTracerProvider = if (enableLoggingExporter) {
    logger.info("Logging span exporter ENABLED - spans will be output to console")
    tracerProviderBuilder
      .addSpanProcessor(SimpleSpanProcessor.create(LoggingSpanExporter.create()))
      .build()
  } else {
    tracerProviderBuilder.build()
  }

  // Register as global to make it accessible
  private val openTelemetry: OpenTelemetrySdk = OpenTelemetrySdk.builder()
    .setTracerProvider(tracerProvider)
    .buildAndRegisterGlobal()

  private val tracer: Tracer = openTelemetry.getTracer("spark-listener", "1.0.0")

  // Initialize Event Emitter
  // ES_URL or ES_HOST must be defined - es01 is a Docker service name not resolvable from Kubernetes
  private val elasticsearchUrl = sys.env.get("ES_URL").getOrElse {
    val esHost = sys.env.get("ES_HOST").getOrElse {
      val errorMsg = "ES_URL or ES_HOST environment variable must be defined. " +
        "ES_URL should be the full Elasticsearch URL (e.g., https://GaryPC.lan:9200). " +
        "ES_HOST should be the Elasticsearch hostname (e.g., GaryPC.lan)."
      logger.error(errorMsg)
      throw new IllegalStateException(errorMsg)
    }
    val esPort = sys.env.getOrElse("ES_PORT", "9200")
    s"https://$esHost:$esPort"
  }
  private val esUsername = sys.env.getOrElse("ES_USER", "elastic")
  private val esPassword = sys.env.getOrElse("ES_PASSWORD", "changeme")
  
  private val eventEmitter = new EventEmitter(elasticsearchUrl, esUsername, esPassword)
  
  // Track active spans for proper parent-child relationships
  private val applicationSpan: TrieMap[String, Span] = TrieMap.empty
  private val jobSpans: TrieMap[Int, Span] = TrieMap.empty
  private val stageSpans: TrieMap[Int, Span] = TrieMap.empty
  private val taskSpans: TrieMap[Long, Span] = TrieMap.empty
  private val sqlExecutionSpans: TrieMap[Long, Span] = TrieMap.empty

  // Unified event metadata maps (replaces separate eventIds and startTimes maps)
  private val appEventMetadata: TrieMap[String, EventStartMetadata] = TrieMap.empty  // key: appId
  private val jobEventMetadata: TrieMap[String, EventStartMetadata] = TrieMap.empty  // key: composite job key
  private val stageEventMetadata: TrieMap[String, EventStartMetadata] = TrieMap.empty  // key: composite stage key
  private val taskEventMetadata: TrieMap[String, EventStartMetadata] = TrieMap.empty  // key: composite task key
  private val sqlEventMetadata: TrieMap[String, EventStartMetadata] = TrieMap.empty  // key: composite sql key
  
  // Store semantic operation and confidence for refinement in onStageCompleted
  private val stageSemanticData: TrieMap[Int, (String, Double)] = TrieMap.empty
  
  // Track application names for correlation
  private val appNames: TrieMap[String, String] = TrieMap.empty
  
  // Composite key helper functions for unique event identification
  // Format: App:{AppID}|Job:{JobId}|Stage:{StageID}|Task:{TaskID}
  // Uses | as level separator and : to separate level name from level ID
  private def appKey(appId: String): String = s"App:$appId"
  private def jobKey(appId: String, jobId: Int): String = s"App:$appId|Job:$jobId"
  private def stageKey(appId: String, jobId: Int, stageId: Int): String = s"App:$appId|Job:$jobId|Stage:$stageId"
  private def taskKey(stageCorrelationKey: String, taskId: Long): String = {
    // Task correlation key extends stage correlation key: App|Job|Stage|Task
    s"$stageCorrelationKey|Task:$taskId"
  }
  private def sqlKey(appId: String, executionId: Long): String = s"App:$appId|SQL:$executionId"
  
  /**
   * Close residual child tasks of a stage.
   * Only closes events that are still in the taskEventMetadata map (have START but no END).
   * Uses correlation key prefix matching with | separator.
   * 
   * @param stageCorrelationKey The stage's correlation key (e.g., "App:appId|Job:jobId|Stage:stageId")
   */
  private def stageCloseResidualChildren(stageCorrelationKey: String): Unit = {
    // Task correlation key format: App:appId|Job:jobId|Stage:stageId|Task:taskId
    // Find tasks that start with the stage's correlation key (since we're iterating over taskEventMetadata, all keys are task keys)
    // Use TrieMap iterator directly
    val residualTasks = taskEventMetadata.iterator.filter { case (key, _) =>
      key.startsWith(stageCorrelationKey) && key.length > stageCorrelationKey.length
    }.toSeq
    
    if (residualTasks.nonEmpty) {
      logger.debug(s"Closing ${residualTasks.size} residual Task events for stage (key: $stageCorrelationKey)")
      residualTasks.foreach { case (key, metadata) =>
        eventEmitter.closeStartEvent(metadata.eventId, closedBy = "parent", correlationKey = Some(key), eventType = Some("task"))
        taskEventMetadata.remove(key)
      }
    }
  }
  
  /**
   * Close residual child stages and tasks of a job.
   * Only closes events that are still in the metadata maps (have START but no END).
   * Recursively processes child stages before closing them.
   * 
   * @param jobCorrelationKey The job's correlation key (e.g., "App:appId|Job:jobId")
   */
  private def jobCloseResidualChildren(jobCorrelationKey: String): Unit = {
    // Stage correlation key format: App:appId|Job:jobId|Stage:stageId
    // Find stages that start with the job's correlation key (since we're iterating over stageEventMetadata, all keys are stage keys)
    // Use TrieMap iterator directly
    val residualStages = stageEventMetadata.iterator.filter { case (key, _) =>
      key.startsWith(jobCorrelationKey) && key.length > jobCorrelationKey.length
    }.toSeq
    
    if (residualStages.nonEmpty) {
      logger.debug(s"Closing ${residualStages.size} residual Stage events for job (key: $jobCorrelationKey)")
      residualStages.foreach { case (stageKey, stageMetadata) =>
        // Recursively close children of this stage (tasks)
        stageCloseResidualChildren(stageKey)
        // Close the stage itself
        eventEmitter.closeStartEvent(stageMetadata.eventId, closedBy = "parent", correlationKey = Some(stageKey), eventType = Some("stage"))
        stageEventMetadata.remove(stageKey)
      }
    }
  }
  
  /**
   * Close residual child jobs, stages, tasks, and SQL executions of an application.
   * Only closes events that are still in the metadata maps (have START but no END).
   * Recursively processes children before closing parents.
   * 
   * @param appCorrelationKey The application's correlation key (e.g., "App:appId")
   */
  private def appCloseResidualChildren(appCorrelationKey: String): Unit = {
    // SQL correlation key format: App:appId|SQL:executionId
    // Find SQL executions that start with the app's correlation key (since we're iterating over sqlEventMetadata, all keys are SQL keys)
    val residualSql = sqlEventMetadata.iterator.filter { case (key, _) =>
      key.startsWith(appCorrelationKey) && key.length > appCorrelationKey.length
    }.toSeq
    if (residualSql.nonEmpty) {
      logger.info(s"Closing ${residualSql.size} residual SQL events for application (key: $appCorrelationKey)")
      residualSql.foreach { case (key, metadata) =>
        eventEmitter.closeStartEvent(metadata.eventId, closedBy = "parent", correlationKey = Some(key), eventType = Some("sql"))
        sqlEventMetadata.remove(key)
      }
    }
    
    // Job correlation key format: App:appId|Job:jobId
    // Find jobs that start with the app's correlation key (since we're iterating over jobEventMetadata, all keys are job keys)
    val residualJobs = jobEventMetadata.iterator.filter { case (key, _) =>
      key.startsWith(appCorrelationKey) && key.length > appCorrelationKey.length
    }.toSeq
    if (residualJobs.nonEmpty) {
      logger.info(s"Closing ${residualJobs.size} residual Job events and their children for application (key: $appCorrelationKey)")
      residualJobs.foreach { case (jobKey, jobMetadata) =>
        // Recursively close children of this job (stages and tasks)
        jobCloseResidualChildren(jobKey)
        // Close the job itself
        eventEmitter.closeStartEvent(jobMetadata.eventId, closedBy = "parent", correlationKey = Some(jobKey), eventType = Some("job"))
        jobEventMetadata.remove(jobKey)
      }
    }
  }
  
  // ISO 8601 timestamp formatter
  private val isoFormatter = DateTimeFormatter.ISO_INSTANT

  logger.info(s"OTelSparkListener initialized - OTLP endpoint: $otlpEndpoint, service: $serviceName")
  logger.info(s"EventEmitter initialized - Elasticsearch URL: $elasticsearchUrl")

  // Generate unique app ID when Spark doesn't provide one
  private def generateAppId(): String = {
    val timestamp = java.time.LocalDateTime.now().format(
      java.time.format.DateTimeFormatter.ofPattern("yyyyMMddHHmmss")
    )
    val random = java.util.concurrent.ThreadLocalRandom.current().nextInt(10000)
    s"app-$timestamp-$random"
  }

  override def onApplicationStart(applicationStart: SparkListenerApplicationStart): Unit = {
    val startNanos = System.nanoTime()
    try {
      val appName = applicationStart.appName
      val appId = applicationStart.appId.getOrElse {
        val generatedId = generateAppId()
        logger.error(s"CRITICAL: Application ID not provided by Spark for app '$appName', generated unique ID: $generatedId")
        generatedId
      }
      val user = applicationStart.sparkUser
      val startTime = applicationStart.time
      val timestamp = Instant.ofEpochMilli(startTime)

      logger.info(s"Application started: $appName (ID: $appId, User: $user)")

      // Generate event ID and correlation key - emit as early as possible
      val eventId = UUID.randomUUID().toString
      val correlationKey = appKey(appId)
      appNames.put(appId, appName)
      
      // Emit START event immediately (before span creation to ensure event is emitted early)
      val startEvent = ApplicationEvent(
        `@timestamp` = isoFormatter.format(timestamp),
        event = EventMetadata(
          id = eventId,
          `type` = "start",
          state = "open"
        ),
        application = "spark",
        operation = Operation(
          `type` = "app",
          id = appId,
          name = appName,
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = None, // Will be updated later if needed
          `trace.id` = None, // Will be updated later if needed
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `app.name` = Some(appName),
          user = Some(user)
        ))
      )
      eventEmitter.emitStartEvent(startEvent, correlationKey)
      
      // Store unified metadata AFTER emitting (prevents race condition)
      val metadata = EventStartMetadata(eventId, startTime, correlationKey)
      appEventMetadata.put(correlationKey, metadata)  // Use correlationKey (App:appId) as map key
      
      // Create span after event emission
      val span = tracer.spanBuilder(s"spark.application.$appName")
        .setSpanKind(SpanKind.SERVER)
        .setStartTimestamp(timestamp)
        .setAttribute("spark.app.name", appName)
        .setAttribute("spark.app.id", appId)
        .setAttribute("spark.user", user)
        .setAttribute("service.name", serviceName)
        .setAttribute("span.kind", "Spark.app")
        .setAttribute("correlation.event.start.id", eventId)
        .startSpan()
      
      val spanId = span.getSpanContext.getSpanId
      val traceId = span.getSpanContext.getTraceId
      applicationSpan.put(appId, span)
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.debug(s"onApplicationStart completed in ${elapsedMs}ms")
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onApplicationStart (${elapsedMs}ms)", e)
    }
  }

  override def onApplicationEnd(applicationEnd: SparkListenerApplicationEnd): Unit = {
    val startNanos = System.nanoTime()
    try {
      val endTime = applicationEnd.time
      val timestamp = Instant.ofEpochMilli(endTime)

      logger.info(s"Application ended at $endTime")

      applicationSpan.foreach { case (appId, span) =>
        // Get unified metadata and app name (use correlationKey: App:appId)
        val correlationKey = appKey(appId)
        val metadata = appEventMetadata.get(correlationKey)
        val appName = appNames.get(appId).getOrElse("unknown")
        val spanId = span.getSpanContext.getSpanId
        val traceId = span.getSpanContext.getTraceId
        
        // Error if metadata is missing
        if (metadata.isEmpty) {
          logger.error(s"CRITICAL: START event metadata missing for app $appId in onApplicationEnd - START event will remain open!")
        }
        
        // Generate end event ID (standard UUID)
        val endEventId = UUID.randomUUID().toString
        // correlationKey already defined above (line 246)
        
        // Calculate duration: end time - start time
        val duration = metadata match {
          case Some(m) =>
            val durationMs = endTime - m.startTime
            Some(durationMs * 1000000)  // Convert to nanoseconds
          case None =>
            logger.error(s"CRITICAL: Start metadata missing for app $appId - cannot calculate duration")
            None
        }
        
        // Emit END event with correlation key and span ID
        val endEvent = ApplicationEvent(
          `@timestamp` = isoFormatter.format(timestamp),
          event = EventMetadata(
            id = endEventId,
            `type` = "end",
            state = "closed",
            duration = duration
          ),
          application = "spark",
          operation = Operation(
            `type` = "app",
            id = appId,
            name = appName,
            result = Some("SUCCESS"),
            `correlation.key` = Some(correlationKey)
          ),
          correlation = Correlation(
            `span.id` = Some(spanId),
            `trace.id` = Some(traceId),
            `start.event.id` = metadata.map(_.eventId),
            `correlation.key` = Some(correlationKey)
          ),
          spark = Some(SparkMetadata(
            `app.id` = Some(appId),
            `app.name` = Some(appName)
          ))
        )
        
        // Close residual child events FIRST (before emitting end event and closing the application itself)
        logger.info(s"Checking for residual child events for application $appId")
        appCloseResidualChildren(correlationKey)
        
        // Emit END event AFTER closing residual children
        eventEmitter.emitEndEvent(endEvent, correlationKey)
        
        // Close the corresponding START event with close_by="end" AFTER emitting end event
        metadata match {
          case Some(m) =>
            eventEmitter.closeStartEvent(m.eventId, closedBy = "end", correlationKey = Some(correlationKey), eventType = Some("app"))
            appEventMetadata.remove(correlationKey)  // Use correlationKey (App:appId) as map key
          case None =>
            logger.error(s"CRITICAL: Cannot close START event for app $appId - metadata is None")
        }
        
        // Complete span
        span.setAttribute("correlation.event.end.id", endEventId)
        span.setStatus(StatusCode.OK)
        span.end(timestamp)
      }
      // CRITICAL: Flush all pending events to Elasticsearch before clearing maps.
      eventEmitter.flushAll()

      // Cleanup application-level structures only
      applicationSpan.clear()
      appNames.clear()
      // NOTE: Job/stage/task/sql metadata maps are cleared when their END events are processed
      // DO NOT clear stageSemanticData - used by stages

      // Shutdown event emitter (events already flushed above, shutdown just stops the executor)
      // Use a shorter timeout to avoid blocking Spark shutdown
      eventEmitter.shutdown()
      
      // Shutdown OpenTelemetry to flush remaining spans
      tracerProvider.close()
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.info(s"OTelSparkListener shutdown complete (${elapsedMs}ms)")
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onApplicationEnd (${elapsedMs}ms)", e)
    }
  }

  override def onJobStart(jobStart: SparkListenerJobStart): Unit = {
    try {
      val jobId = jobStart.jobId
      val stageIds = jobStart.stageIds
      val stageInfos = jobStart.stageInfos
      val time = jobStart.time

      logger.debug(s"Job $jobId started with ${stageIds.length} stages")

      // Generate event ID and correlation key - emit as early as possible
      val eventId = UUID.randomUUID().toString
      val timestamp = Instant.ofEpochMilli(time)
      
      // Get application info
      val (appId, appName) = applicationSpan.keys.headOption.map { id =>
        (id, appNames.getOrElse(id, "unknown"))
      }.getOrElse(("unknown", "unknown"))
      
      // Generate composite correlation key
      val correlationKey = jobKey(appId, jobId)
      
      // Emit START event immediately (before span creation to ensure event is emitted early)
      val startEvent = ApplicationEvent(
        `@timestamp` = isoFormatter.format(timestamp),
        event = EventMetadata(
          id = eventId,
          `type` = "start",
          category = "application",
          state = "open"
        ),
        application = "spark",
        operation = Operation(
          `type` = "job",
          id = s"job-$jobId",
          name = s"Job $jobId",
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = None, // Will be updated later if needed
          `trace.id` = None, // Will be updated later if needed
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `app.name` = Some(appName),
          `job.id` = Some(jobId),
          `job.stage.count` = Some(stageIds.length.toLong)
        ))
      )
      eventEmitter.emitStartEvent(startEvent, correlationKey)
      
      // Store unified metadata AFTER emitting (prevents race condition)
      val metadata = EventStartMetadata(eventId, time, correlationKey)
      jobEventMetadata.put(correlationKey, metadata)
      
      // Get parent context from application span
      val parentSpan = applicationSpan.values.headOption

      val spanBuilder = tracer.spanBuilder(s"spark.job.$jobId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(timestamp)
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
      val spanId = span.getSpanContext.getSpanId
      val traceId = span.getSpanContext.getTraceId
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

      // Get application info
      val (appId, appName) = applicationSpan.keys.headOption.map { id =>
        (id, appNames.getOrElse(id, "unknown"))
      }.getOrElse(("unknown", "unknown"))
      
      // Generate end event ID and correlation key
      val endEventId = UUID.randomUUID().toString
      val timestamp = Instant.ofEpochMilli(time)
      val correlationKey = jobKey(appId, jobId)
      
      // Get unified metadata
      val metadata = jobEventMetadata.get(correlationKey)
      
      // Error if metadata is missing
      if (metadata.isEmpty) {
        logger.error(s"CRITICAL: START event metadata missing for job $jobId (key: $correlationKey) in onJobEnd - START event will remain open!")
      }
      
      // Calculate duration: end time - start time
      val duration = metadata match {
        case Some(m) =>
          val durationMs = time - m.startTime
          Some(durationMs * 1000000)  // Convert to nanoseconds
        case None =>
          logger.error(s"CRITICAL: Start metadata missing for job $jobId - cannot calculate duration")
          None
      }
      
      // Determine result
      val result = jobEnd.jobResult match {
        case JobSucceeded => "SUCCESS"
        case JobFailed(_) => "FAILED"
      }
      
      // Get span for span ID
      val spanOption = jobSpans.get(jobId)
      val spanId = spanOption.map(s => s.getSpanContext.getSpanId)
      val traceId = spanOption.map(s => s.getSpanContext.getTraceId)
      
      // Emit END event with correlation key and span ID
      val endEvent = ApplicationEvent(
        `@timestamp` = isoFormatter.format(timestamp),
        event = EventMetadata(
          id = endEventId,
          `type` = "end",
          category = "application",
          state = "closed",
          duration = duration
        ),
        application = "spark",
        operation = Operation(
          `type` = "job",
          id = s"job-$jobId",
          name = s"Job $jobId",
          result = Some(result),
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = spanId,
          `trace.id` = traceId,
          `start.event.id` = metadata.map(_.eventId),
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `app.name` = Some(appName),
          `job.id` = Some(jobId)
        ))
      )
      
      // Close residual child events FIRST (before emitting end event and closing the job itself)
      logger.debug(s"Checking for residual child events for job $jobId")
      jobCloseResidualChildren(correlationKey)
      
      // Emit END event AFTER closing residual children
      eventEmitter.emitEndEvent(endEvent, correlationKey)
      
      // Close the corresponding START event with close_by="end" AFTER emitting end event
      metadata match {
        case Some(m) =>
          eventEmitter.closeStartEvent(m.eventId, closedBy = "end", correlationKey = Some(correlationKey), eventType = Some("job"))
          jobEventMetadata.remove(correlationKey)
        case None =>
          logger.error(s"CRITICAL: Cannot close START event for job $jobId - metadata is None")
      }
      
      
      // Clean up job-level structures (but NOT lower-level events like tasks/stages)
      // Metadata is already removed in the closeStartEvent call above

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
        span.end(timestamp)
      }
    } catch {
      case e: Exception =>
        logger.error(s"Error in onJobEnd for job ${jobEnd.jobId}", e)
    }
  }

  override def onStageSubmitted(stageSubmitted: SparkListenerStageSubmitted): Unit = {
    val startNanos = System.nanoTime()
    try {
      val stageInfo = stageSubmitted.stageInfo
      val stageId = stageInfo.stageId
      val stageName = stageInfo.name
      val numTasks = stageInfo.numTasks
      val attemptNumber = stageInfo.attemptNumber()
      val submissionTime = stageInfo.submissionTime.getOrElse(System.currentTimeMillis())
      val timestamp = Instant.ofEpochMilli(submissionTime)

      logger.debug(s"Stage $stageId submitted: $stageName ($numTasks tasks)")

      // Generate event ID and correlation key - emit as early as possible
      val eventId = UUID.randomUUID().toString
      
      // Get parent job ID and app ID for composite key
      // Stages usually have jobs, but handle gracefully if job context is missing
      val parentJobId = jobSpans.keys.headOption.getOrElse {
        logger.warn(s"Stage $stageId submitted without parent job context - using job ID 0 as fallback")
        0
      }
      val appId = applicationSpan.keys.headOption.getOrElse("unknown")
      
      // Generate composite correlation key (stages always have jobs)
      val correlationKey = stageKey(appId, parentJobId, stageId)
      
      // Get parent job event ID for correlation
      val jobCorrelationKey = jobKey(appId, parentJobId)
      val parentJobEventId = jobEventMetadata.get(jobCorrelationKey).map(_.eventId)
      
      // Emit START event immediately (before span creation to ensure event is emitted early)
      val startEvent = ApplicationEvent(
        `@timestamp` = isoFormatter.format(timestamp),
        event = EventMetadata(
          id = eventId,
          `type` = "start",
          state = "open"
        ),
        application = "spark",
        operation = Operation(
          `type` = "stage",
          id = s"stage-$stageId",
          name = stageName,
          `parent.id` = Some(s"job-$parentJobId"),
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = None, // Will be updated later if needed
          `trace.id` = None, // Will be updated later if needed
          `parent.event.id` = parentJobEventId,
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `stage.id` = Some(stageId.toLong),
          `stage.name` = Some(stageName),
          `stage.attempt` = Some(attemptNumber.toLong),
          `stage.num.tasks` = Some(numTasks.toLong),
          `job.id` = Some(parentJobId.toLong)
        ))
      )
      eventEmitter.emitStartEvent(startEvent, correlationKey)
      
      // Store unified metadata AFTER emitting (prevents race condition)
      val metadata = EventStartMetadata(eventId, submissionTime, correlationKey)
      stageEventMetadata.put(correlationKey, metadata)
      
      // Try to get parent job span - in Spark 4.0, we need to find it from active jobs
      // For simplicity, we'll use the first available job span
      val parentSpan = jobSpans.values.headOption

      // Extract semantic information from stage name
      val operationPattern = """^(\w+)\s+at\s+([^:]+):(\d+)""".r
      val semanticOperationType = stageName match {
        case operationPattern(op, _, _) => Some(op)
        case _ =>
          // Fallback: try simpler pattern
          if (stageName.contains(" at ")) {
            val parts = stageName.split(" at ")
            if (parts.length > 0) Some(parts(0).trim) else None
          } else None
      }
      
      val semanticSourceFile = stageName match {
        case operationPattern(_, file, _) => Some(file)
        case _ => None
      }
      
      val semanticSourceLine = stageName match {
        case operationPattern(_, _, line) => Try(line.toInt).toOption
        case _ => None
      }
      
      // Extract RDD types from stage info
      val rddInfos = stageInfo.rddInfos
      val rddTypes = if (rddInfos.nonEmpty) {
        Some(rddInfos.map(_.name).distinct.mkString(","))
      } else None
      
      val spanBuilder = tracer.spanBuilder(s"spark.stage.$stageId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(timestamp)
        .setAttribute("spark.stage.id", stageId.toLong)
        .setAttribute("spark.stage.name", stageName)
        .setAttribute("spark.stage.num.tasks", numTasks.toLong)
        .setAttribute("spark.stage.attempt", attemptNumber.toLong)
        .setAttribute("span.kind", "Spark.stage")
        .setAttribute("correlation.event.start.id", eventId)
      
      // Add semantic attributes
      semanticOperationType.foreach(op => spanBuilder.setAttribute("spark.semantic.operation.type", op))
      semanticSourceFile.foreach(file => spanBuilder.setAttribute("spark.semantic.source.file", file))
      semanticSourceLine.foreach(line => spanBuilder.setAttribute("spark.semantic.source.line", line.toLong))
      
      // Multi-signal operation classification with confidence scoring
      var operationScores = scala.collection.mutable.Map[String, Double]().withDefaultValue(0.0)
      
      // Signal 1: Stage name parsing (weight 0.4)
      semanticOperationType.foreach { op =>
        val normalizedOp = op.toLowerCase match {
          case "count" | "groupby" | "reducebykey" | "aggregatebykey" => "aggregation"
          case "join" | "cogroup" | "leftjoin" | "rightjoin" | "outerjoin" => "join"
          case "filter" => "filter"
          case "map" | "mappartitions" | "flatmap" | "mapvalues" => "transformation"
          case "union" => "union"
          case "distinct" => "distinct"
          case _ => "unknown"
        }
        if (normalizedOp != "unknown") {
          operationScores(normalizedOp) += 0.4
        }
      }
      
      // Signal 2: RDD type analysis (weight 0.3)
      rddTypes.foreach { types =>
        spanBuilder.setAttribute("spark.semantic.rdd.types", types)
        spanBuilder.setAttribute("spark.semantic.rdd.count", rddInfos.length.toLong)
        
        if (types.contains("ShuffledRDD")) {
          if (types.contains("CoGroupedRDD")) {
            operationScores("join") += 0.3
          } else {
            operationScores("aggregation") += 0.3
          }
        } else if (types.contains("MapPartitionsRDD")) {
          operationScores("transformation") += 0.3
        } else if (types.contains("UnionRDD")) {
          operationScores("union") += 0.3
        }
      }
      
      // Select best operation and set confidence
      if (operationScores.nonEmpty) {
        val bestOperation = operationScores.maxBy(_._2)
        val confidence = bestOperation._2
        
        spanBuilder.setAttribute("spark.semantic.operation", bestOperation._1)
        spanBuilder.setAttribute("spark.semantic.confidence", confidence)
        
        // Store for refinement in onStageCompleted
        stageSemanticData.put(stageId, (bestOperation._1, confidence))
        
        // Flag low confidence for review
        if (confidence < 0.7) {
          spanBuilder.setAttribute("spark.semantic.low_confidence", true)
        }
      }

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      // Add parent stage information if this is a retry
      if (attemptNumber > 0) {
        spanBuilder.setAttribute("spark.stage.is.retry", true)
      }

      val span = spanBuilder.startSpan()
      val spanId = span.getSpanContext.getSpanId
      val traceId = span.getSpanContext.getTraceId
      stageSpans.put(stageId, span)
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.debug(s"onStageSubmitted completed in ${elapsedMs}ms for stage $stageId")
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onStageSubmitted for stage ${stageSubmitted.stageInfo.stageId} (${elapsedMs}ms)", e)
    }
  }

  override def onStageCompleted(stageCompleted: SparkListenerStageCompleted): Unit = {
    val startNanos = System.nanoTime()
    try {
      val stageInfo = stageCompleted.stageInfo
      val stageId = stageInfo.stageId
      val completionTime = stageInfo.completionTime.getOrElse(System.currentTimeMillis())
      val timestamp = Instant.ofEpochMilli(completionTime)
      val submissionTime = stageInfo.submissionTime.getOrElse(completionTime)
      val durationMs = completionTime - submissionTime

      logger.debug(s"Stage $stageId completed")

      // Get app ID and parent job ID for composite key
      // Stages usually have jobs, but handle gracefully if job context is missing
      val appId = applicationSpan.keys.headOption.getOrElse("unknown")
      val parentJobId = jobSpans.keys.headOption.getOrElse {
        logger.warn(s"Stage $stageId completed without parent job context - using job ID 0 as fallback")
        0
      }
      
      // Generate composite correlation key (must match onStageSubmitted)
      val correlationKey = stageKey(appId, parentJobId, stageId)
      
      // Get unified metadata
      val metadata = stageEventMetadata.get(correlationKey)
      
      stageSpans.get(stageId).foreach { span =>
        val spanId = span.getSpanContext.getSpanId
        val traceId = span.getSpanContext.getTraceId
        
        // Error if metadata is missing
        if (metadata.isEmpty) {
          logger.error(s"CRITICAL: START event metadata missing for stage $stageId (key: $correlationKey) in onStageCompleted - START event will remain open!")
        }
        
        // Generate end event ID (standard UUID)
        val endEventId = UUID.randomUUID().toString
        
        // Calculate duration: end time - start time
        val duration = metadata match {
          case Some(m) =>
            val durationMs = completionTime - m.startTime
            Some(durationMs * 1000000)  // Convert to nanoseconds
          case None =>
            logger.error(s"CRITICAL: Start metadata missing for stage $stageId - cannot calculate duration")
            None
        }
        
        // Determine result
        val result = if (stageInfo.failureReason.isDefined) "FAILED" else "SUCCESS"
        
        // Collect metrics
        val taskMetrics = stageInfo.taskMetrics
        val metricsData = if (taskMetrics != null) {
          Some(SparkEventMetrics(
            `duration.ms` = Some(durationMs),
            `shuffle.read.bytes` = Some(taskMetrics.shuffleReadMetrics.totalBytesRead),
            `shuffle.write.bytes` = Some(taskMetrics.shuffleWriteMetrics.bytesWritten),
            `input.bytes` = Some(taskMetrics.inputMetrics.bytesRead),
            `output.bytes` = Some(taskMetrics.outputMetrics.bytesWritten),
            `memory.spilled.bytes` = Some(taskMetrics.memoryBytesSpilled),
            `disk.spilled.bytes` = Some(taskMetrics.diskBytesSpilled)
          ))
        } else None
        
        // Emit END event with correlation key and span ID
        val endEvent = ApplicationEvent(
          `@timestamp` = isoFormatter.format(timestamp),
          event = EventMetadata(
            id = endEventId,
            `type` = "end",
            state = "closed",
            duration = duration
          ),
          application = "spark",
          operation = Operation(
            `type` = "stage",
            id = s"stage-$stageId",
            name = stageInfo.name,
            result = Some(result),
            `correlation.key` = Some(correlationKey)
          ),
          correlation = Correlation(
            `span.id` = Some(spanId),
            `trace.id` = Some(traceId),
            `start.event.id` = metadata.map(_.eventId),
            `correlation.key` = Some(correlationKey)
          ),
          spark = Some(SparkMetadata(
            `app.id` = applicationSpan.keys.headOption,
            `stage.id` = Some(stageId.toLong),
            `stage.name` = Some(stageInfo.name),
            `stage.result` = Some(result),
            metrics = metricsData
          ))
        )
        
        // Close residual child events FIRST (before emitting end event and closing the stage itself)
        logger.debug(s"Checking for residual child events for stage $stageId")
        stageCloseResidualChildren(correlationKey)
        
        // Emit END event AFTER closing residual children
        eventEmitter.emitEndEvent(endEvent, correlationKey)
        
        // Close the corresponding START event with close_by="end" AFTER emitting end event
        metadata match {
          case Some(m) =>
            eventEmitter.closeStartEvent(m.eventId, closedBy = "end", correlationKey = Some(correlationKey), eventType = Some("stage"))
            stageEventMetadata.remove(correlationKey)
          case None =>
            logger.error(s"CRITICAL: Cannot close START event for stage $stageId - metadata is None")
        }
        
        // Remove span after update
        stageSpans.remove(stageId)
        
        // Add metrics to span
        span.setAttribute("spark.stage.tasks.completed", stageInfo.numTasks.toLong)
        
        if (taskMetrics != null) {
          span.setAttribute("spark.stage.shuffle.read.bytes", taskMetrics.shuffleReadMetrics.totalBytesRead)
          span.setAttribute("spark.stage.shuffle.write.bytes", taskMetrics.shuffleWriteMetrics.bytesWritten)
          span.setAttribute("spark.stage.input.bytes", taskMetrics.inputMetrics.bytesRead)
          span.setAttribute("spark.stage.output.bytes", taskMetrics.outputMetrics.bytesWritten)
          span.setAttribute("spark.stage.memory.spilled.bytes", taskMetrics.memoryBytesSpilled)
          span.setAttribute("spark.stage.disk.spilled.bytes", taskMetrics.diskBytesSpilled)
          
          // Shuffle classification
          val shuffleWrite = taskMetrics.shuffleWriteMetrics.bytesWritten
          val shuffleRead = taskMetrics.shuffleReadMetrics.totalBytesRead
          
          val classification = (shuffleWrite > 0, shuffleRead > 0) match {
            case (true, false) => "shuffle_producer"
            case (false, true) => "shuffle_consumer"
            case (true, true) => "shuffle_exchange"
            case _ => "narrow_transformation"
          }
          span.setAttribute("spark.semantic.shuffle.classification", classification)
          
          // Shuffle intensity
          val intensity = if (shuffleWrite > 100000000) "very_high"      // > 100 MB
                          else if (shuffleWrite > 10000000) "high"       // > 10 MB
                          else if (shuffleWrite > 1000000) "medium"      // > 1 MB
                          else if (shuffleWrite > 0) "low"                // > 0
                          else "none"
          span.setAttribute("spark.semantic.shuffle.intensity", intensity)
          
          // Signal 3: Shuffle pattern (weight 0.3) - refine operation classification
          // This is done here because we have shuffle metrics available
          stageSemanticData.remove(stageId).foreach { case (opStr, currentConfidence) =>
            var refinedConfidence = currentConfidence
            
            // Refine based on shuffle pattern
            classification match {
              case "shuffle_producer" =>
                if (opStr == "aggregation" || opStr == "join") {
                  refinedConfidence = math.min(currentConfidence + 0.3, 1.0)
                }
              case "shuffle_consumer" =>
                if (opStr == "join") {
                  refinedConfidence = math.min(currentConfidence + 0.3, 1.0)
                }
              case "narrow_transformation" =>
                if (opStr == "transformation" || opStr == "filter") {
                  refinedConfidence = math.min(currentConfidence + 0.3, 1.0)
                }
              case _ => // shuffle_exchange - no refinement
            }
            
            // Update confidence and low_confidence flag
            span.setAttribute("spark.semantic.confidence", refinedConfidence: Double)
            if (refinedConfidence < 0.7) {
              span.setAttribute("spark.semantic.low_confidence", true)
            } else {
              span.setAttribute("spark.semantic.low_confidence", false)
            }
          }
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

        // Complete span with end event correlation
        span.setAttribute("correlation.event.end.id", endEventId)
        span.end(timestamp)
      }
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      if (elapsedMs > 100) {
        logger.warn(s"onStageCompleted took ${elapsedMs}ms for stage $stageId")
      } else {
        logger.debug(s"onStageCompleted completed in ${elapsedMs}ms for stage $stageId")
      }
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onStageCompleted for stage ${stageCompleted.stageInfo.stageId} (${elapsedMs}ms)", e)
    }
  }

  override def onTaskStart(taskStart: SparkListenerTaskStart): Unit = {
    val startNanos = System.nanoTime()
    try {
      val stageId = taskStart.stageId
      val taskInfo = taskStart.taskInfo

      logger.debug(s"Task ${taskInfo.taskId} started in stage $stageId")

      val launchTime = taskInfo.launchTime
      val appId = applicationSpan.keys.headOption.getOrElse("unknown")
      val appName = appNames.get(appId)
      
      // CRITICAL: Check if stage start event exists - if not, create it now
      // This handles cases where onStageSubmitted was never called (e.g., skipped stages, immediate failures)
      val stageCorrelationKey = stageEventMetadata.keys.find { key =>
        key.endsWith(s"|Stage:$stageId")
      }.getOrElse {
        logger.warn(s"Stage $stageId not found in metadata when creating task ${taskInfo.taskId} - creating synthetic stage start event")
        // Fallback: construct from available context
        val parentJobId = jobSpans.keys.headOption.getOrElse(0)
        val syntheticStageKey = stageKey(appId, parentJobId, stageId)
        
        // Create synthetic stage start event
        val stageEventId = UUID.randomUUID().toString
        val syntheticStageEvent = ApplicationEvent(
          `@timestamp` = isoFormatter.format(Instant.ofEpochMilli(launchTime)),
          event = EventMetadata(
            id = stageEventId,
            `type` = "start",
            state = "open"
          ),
          application = "spark",
          operation = Operation(
            `type` = "stage",
            id = s"stage-$stageId",
            name = s"Stage $stageId (synthetic)",
            `parent.id` = Some(s"job-$parentJobId"),
            `correlation.key` = Some(syntheticStageKey)
          ),
          correlation = Correlation(
            `span.id` = None,
            `trace.id` = None,
            `correlation.key` = Some(syntheticStageKey)
          ),
          spark = Some(SparkMetadata(
            `app.id` = Some(appId),
            `stage.id` = Some(stageId.toLong),
            `job.id` = Some(parentJobId.toLong)
          ))
        )
        eventEmitter.emitStartEvent(syntheticStageEvent, syntheticStageKey)
        
        // Store metadata
        val metadata = EventStartMetadata(stageEventId, launchTime, syntheticStageKey)
        stageEventMetadata.put(syntheticStageKey, metadata)
        
        syntheticStageKey
      }
      
      // Generate event ID and correlation key for tasks (if enabled) - emit as early as possible
      // Task key needs the stage's correlation key to include full hierarchy
      val (eventIdOpt, correlationKeyOpt) = if (emitTaskEvents) {
        val eventId = UUID.randomUUID().toString
        val correlationKey = taskKey(stageCorrelationKey, taskInfo.taskId)
        
        // Emit START event immediately (before span creation to ensure event is emitted early)
        val event = ApplicationEvent(
          `@timestamp` = Instant.ofEpochMilli(launchTime).toString,
          event = EventMetadata(
            id = eventId,
            `type` = "start",
            category = "application",
            state = "open"
          ),
          application = "spark",
          operation = Operation(
            `type` = "task",
            id = s"task-${taskInfo.taskId}",
            name = s"Task ${taskInfo.taskId}",
            `parent.id` = Some(s"stage-$stageId"),
            `correlation.key` = Some(correlationKey)
          ),
          correlation = Correlation(
            `span.id` = None, // Will be updated later if needed
            `trace.id` = None, // Will be updated later if needed
            `correlation.key` = Some(correlationKey)
          ),
          spark = Some(SparkMetadata(
            `app.id` = Some(appId),
            `app.name` = appName,
            `task.id` = Some(taskInfo.taskId),
            `task.index` = Some(taskInfo.index),
            `task.executor.id` = Some(taskInfo.executorId),
            `stage.id` = Some(stageId)
          ))
        )
        eventEmitter.emitStartEvent(event, correlationKey)
        
        // Store unified metadata AFTER emitting (prevents race condition)
        val metadata = EventStartMetadata(eventId, launchTime, correlationKey)
        taskEventMetadata.put(correlationKey, metadata)
        
        (Some(eventId), Some(correlationKey))
      } else {
        (None, None)
      }
      
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

      // Add correlation event ID if task events enabled
      eventIdOpt.foreach { eventId =>
        spanBuilder.setAttribute("correlation.event.start.id", eventId)
      }

      // Set parent if available
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }

      val span = spanBuilder.startSpan()
      taskSpans.put(taskInfo.taskId, span)

      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.debug(s"onTaskStart completed in ${elapsedMs}ms for task ${taskInfo.taskId}")
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onTaskStart for task in stage ${taskStart.stageId} (${elapsedMs}ms)", e)
    }
  }

  override def onTaskEnd(taskEnd: SparkListenerTaskEnd): Unit = {
    val startNanos = System.nanoTime()
    try {
      val taskInfo = taskEnd.taskInfo
      val taskMetrics = taskEnd.taskMetrics

      // Emit task end event if enabled
      if (emitTaskEvents) {
        val stageId = taskEnd.stageId
        val appId = applicationSpan.keys.headOption.getOrElse("unknown")
        
        // Generate composite correlation key (must match onTaskStart)
        // Look up stage's correlation key to build full task hierarchy
        val stageCorrelationKey = stageEventMetadata.keys.find { key =>
          key.endsWith(s"|Stage:$stageId")
        }.getOrElse {
          logger.error(s"CRITICAL: Stage $stageId not found in metadata when ending task ${taskInfo.taskId}")
          // Fallback: construct from available context (shouldn't happen normally)
          val parentJobId = jobSpans.keys.headOption.getOrElse(0)
          stageKey(appId, parentJobId, stageId)
        }
        val correlationKey = taskKey(stageCorrelationKey, taskInfo.taskId)
        
        // Get unified metadata
        val metadata = taskEventMetadata.get(correlationKey)
        
        // Error if metadata is missing
        if (metadata.isEmpty) {
          logger.error(s"CRITICAL: START event metadata missing for task ${taskInfo.taskId} (key: $correlationKey) in onTaskEnd! Map contains ${taskEventMetadata.size} entries. This means either:")
          logger.error(s"  1. onTaskStart was never called for this task, OR")
          logger.error(s"  2. The correlation key doesn't match (onTaskStart used different key), OR")
          logger.error(s"  3. The map was cleared prematurely")
          // List some keys in the map for debugging
          val sampleKeys = taskEventMetadata.keys.take(5).mkString(", ")
          logger.error(s"  Sample correlation keys in map: $sampleKeys")
        }
        
        val spanOption = taskSpans.get(taskInfo.taskId)
        val spanId = spanOption.map(s => s.getSpanContext.getSpanId)
        val traceId = spanOption.map(s => s.getSpanContext.getTraceId)
        val endEventId = UUID.randomUUID().toString
        // appId already defined above (line 1052)
        val appName = appNames.get(appId)
        val finishTime = taskInfo.finishTime

        // Calculate duration: end time - start time
        val duration = metadata match {
          case Some(m) =>
            val durationMs = finishTime - m.startTime
            Some(durationMs * 1000000)  // Convert to nanoseconds
          case None =>
            logger.error(s"CRITICAL: Start metadata missing for task ${taskInfo.taskId} - cannot calculate duration")
            None
        }

        val result = taskEnd.reason match {
          case _: org.apache.spark.Success.type => "SUCCESS"
          case _ => "FAILED"
        }

        val taskMetricsData = if (taskMetrics != null) {
          Some(SparkEventMetrics(
            `duration.ms` = Some(taskMetrics.executorRunTime),
            `shuffle.read.bytes` = Some(taskMetrics.shuffleReadMetrics.totalBytesRead),
            `shuffle.write.bytes` = Some(taskMetrics.shuffleWriteMetrics.bytesWritten),
            `input.bytes` = Some(taskMetrics.inputMetrics.bytesRead),
            `output.bytes` = Some(taskMetrics.outputMetrics.bytesWritten),
            `executor.run.time.ms` = Some(taskMetrics.executorRunTime),
            `executor.cpu.time.ms` = Some(taskMetrics.executorCpuTime / 1000000)
          ))
        } else None

        val event = ApplicationEvent(
          `@timestamp` = Instant.ofEpochMilli(finishTime).toString,
          event = EventMetadata(
            id = endEventId,
            `type` = "end",
            category = "application",
            state = "closed",
            duration = duration
          ),
          application = "spark",
          operation = Operation(
            `type` = "task",
            id = s"task-${taskInfo.taskId}",
            name = s"Task ${taskInfo.taskId}",
            result = Some(result),
            `correlation.key` = Some(correlationKey)
          ),
          correlation = Correlation(
            `span.id` = spanId,
            `trace.id` = traceId,
            `start.event.id` = metadata.map(_.eventId),
            `correlation.key` = Some(correlationKey)
          ),
          spark = Some(SparkMetadata(
            `app.id` = Some(appId),
            `app.name` = appName,
            `task.id` = Some(taskInfo.taskId),
            `task.index` = Some(taskInfo.index),
            `task.executor.id` = Some(taskInfo.executorId),
            `stage.id` = Some(taskEnd.stageId),
            metrics = taskMetricsData
          ))
        )

        eventEmitter.emitEndEvent(event, correlationKey)
        
        // Close the corresponding START event with close_by="end"
        metadata match {
          case Some(m) =>
            eventEmitter.closeStartEvent(m.eventId, closedBy = "end", correlationKey = Some(correlationKey), eventType = Some("task"))
            taskEventMetadata.remove(correlationKey)
          case None =>
            logger.error(s"CRITICAL: Cannot close START event for task ${taskInfo.taskId} - metadata is None")
        }
      }

      // Get the span we created in onTaskStart
      taskSpans.remove(taskInfo.taskId).foreach { span =>
        logger.debug(s"Task ${taskInfo.taskId} ended in stage ${taskEnd.stageId}: ${taskEnd.reason}")

        // Add task metrics
        if (taskMetrics != null) {
          span.setAttribute("spark.task.executor.run.time.ms", taskMetrics.executorRunTime)
          span.setAttribute("spark.task.executor.cpu.time.ms", taskMetrics.executorCpuTime / 1000000)
          span.setAttribute("spark.task.result.size.bytes", taskMetrics.resultSize)
        }

        // Add correlation event ID if task events enabled
        if (emitTaskEvents) {
          span.setAttribute("correlation.event.end.id", UUID.randomUUID().toString)
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

      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      if (elapsedMs > 100) {
        logger.warn(s"onTaskEnd took ${elapsedMs}ms for task ${taskInfo.taskId}")
      }
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onTaskEnd for task in stage ${taskEnd.stageId} (${elapsedMs}ms)", e)
    }
  }

  // SQL Execution tracking - handle via onOtherEvent
  override def onOtherEvent(event: SparkListenerEvent): Unit = {
    event match {
      case sqlStart: SparkListenerSQLExecutionStart =>
        onSQLExecutionStart(sqlStart)
      case sqlEnd: SparkListenerSQLExecutionEnd =>
        onSQLExecutionEnd(sqlEnd)
      case _ => // Ignore other events
    }
  }

  private def onSQLExecutionStart(sqlStart: SparkListenerSQLExecutionStart): Unit = {
    val startNanos = System.nanoTime()
    try {
      val executionId = sqlStart.executionId
      val description = sqlStart.description
      val physicalPlanDescription = sqlStart.physicalPlanDescription
      val time = sqlStart.time
      
      logger.info(s"SQL execution $executionId started: $description")

      // Get app ID and name
      val appId = applicationSpan.keys.headOption.getOrElse("unknown")
      val appName = appNames.get(appId)
      
      // Generate event ID and composite correlation key
      val eventId = UUID.randomUUID().toString
      val correlationKey = sqlKey(appId, executionId)
      
      // Store unified metadata BEFORE emitting
      val metadata = EventStartMetadata(eventId, time, correlationKey)
      sqlEventMetadata.put(correlationKey, metadata)
      
      // Create OTel span first to get span ID
      val parentSpan = applicationSpan.values.headOption
      
      val spanBuilder = tracer.spanBuilder(s"spark.sql.$executionId")
        .setSpanKind(SpanKind.INTERNAL)
        .setStartTimestamp(Instant.ofEpochMilli(time))
        .setAttribute("spark.sql.execution.id", executionId.toLong)
        .setAttribute("spark.sql.description", description)
        .setAttribute("spark.sql.physical_plan", physicalPlanDescription)
        .setAttribute("correlation.event.start.id", eventId)
        .setAttribute("span.kind", "Spark.SQL")
      
      parentSpan.foreach { parent =>
        spanBuilder.setParent(Context.current().`with`(parent))
      }
      
      val span = spanBuilder.startSpan()
      val spanId = span.getSpanContext.getSpanId
      val traceId = span.getSpanContext.getTraceId
      sqlExecutionSpans.put(executionId, span)
      
      // Emit start event with correlation key and span ID
      val event = ApplicationEvent(
        `@timestamp` = Instant.ofEpochMilli(time).toString,
        event = EventMetadata(
          id = eventId,
          `type` = "start",
          category = "application",
          state = "open"
        ),
        application = "spark",
        operation = Operation(
          `type` = "sql",
          id = s"sql-$executionId",
          name = description,
          `parent.id` = None,
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = Some(spanId),
          `trace.id` = Some(traceId),
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `app.name` = appName,
          `sql.execution.id` = Some(executionId),
          `sql.description` = Some(description),
          `sql.query_plan.simplified` = Some(physicalPlanDescription),
          `sql.query_plan.verbose` = None
        ))
      )
      
      eventEmitter.emitStartEvent(event, correlationKey)
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.debug(s"SQL execution $executionId span created (${elapsedMs}ms)")
      
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onSQLExecutionStart for execution ${sqlStart.executionId} (${elapsedMs}ms)", e)
    }
  }

  private def onSQLExecutionEnd(sqlEnd: SparkListenerSQLExecutionEnd): Unit = {
    val startNanos = System.nanoTime()
    try {
      val executionId = sqlEnd.executionId
      val time = sqlEnd.time
      
      logger.info(s"SQL execution $executionId ended")
      
      // Get app ID and name
      val appId = applicationSpan.keys.headOption.getOrElse("unknown")
      val appName = appNames.get(appId)
      
      // Generate composite correlation key (must match onSQLExecutionStart)
      val correlationKey = sqlKey(appId, executionId)
      
      // Get unified metadata
      val metadata = sqlEventMetadata.get(correlationKey)
      
      // Error if metadata is missing
      if (metadata.isEmpty) {
        logger.error(s"CRITICAL: START event metadata missing for SQL execution $executionId (key: $correlationKey) in onSQLExecutionEnd - START event will remain open!")
      }
      
      // Get span for correlation
      val spanOption = sqlExecutionSpans.get(executionId)
      val spanId = spanOption.map(s => s.getSpanContext.getSpanId)
      val traceId = spanOption.map(s => s.getSpanContext.getTraceId)
      
      // Generate end event ID (standard UUID)
      val endEventId = UUID.randomUUID().toString
      
      // Calculate duration: end time - start time
      val duration = metadata match {
        case Some(m) =>
          val durationMs = time - m.startTime
          Some(durationMs * 1000000)  // Convert to nanoseconds
        case None =>
          logger.error(s"CRITICAL: Start metadata missing for SQL execution $executionId - cannot calculate duration")
          None
      }
      
      // Emit end event with correlation key and span ID
      val event = ApplicationEvent(
        `@timestamp` = Instant.ofEpochMilli(time).toString,
        event = EventMetadata(
          id = endEventId,
          `type` = "end",
          category = "application",
          state = "closed",
          duration = duration
        ),
        application = "spark",
        operation = Operation(
          `type` = "sql",
          id = s"sql-$executionId",
          name = s"SQL $executionId",
          result = Some("SUCCESS"),
          `correlation.key` = Some(correlationKey)
        ),
        correlation = Correlation(
          `span.id` = spanId,
          `trace.id` = traceId,
          `start.event.id` = metadata.map(_.eventId),
          `correlation.key` = Some(correlationKey)
        ),
        spark = Some(SparkMetadata(
          `app.id` = Some(appId),
          `app.name` = appName,
          `sql.execution.id` = Some(executionId)
        ))
      )
      
      eventEmitter.emitEndEvent(event, correlationKey)
      
      // Close the corresponding START event with close_by="end"
      metadata match {
        case Some(m) =>
          eventEmitter.closeStartEvent(m.eventId, closedBy = "end", correlationKey = Some(correlationKey), eventType = Some("sql"))
          sqlEventMetadata.remove(correlationKey)
        case None =>
          logger.error(s"CRITICAL: Cannot close START event for SQL execution $executionId - metadata is None")
      }
      
      // Remove span after update
      sqlExecutionSpans.remove(executionId)
      
      // Complete span
      spanOption.foreach { span =>
        span.setAttribute("correlation.event.end.id", endEventId)
        span.setStatus(StatusCode.OK)
        span.end(Instant.ofEpochMilli(time))
      }
      
      val elapsedMs = (System.nanoTime() - startNanos) / 1000000
      logger.debug(s"SQL execution $executionId completed (${elapsedMs}ms)")
      
    } catch {
      case e: Exception =>
        val elapsedMs = (System.nanoTime() - startNanos) / 1000000
        logger.error(s"Error in onSQLExecutionEnd for execution ${sqlEnd.executionId} (${elapsedMs}ms)", e)
    }
  }

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

