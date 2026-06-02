package com.elastic.spark.otel

import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.metrics.{LongCounter, LongUpDownCounter, Meter}
import org.slf4j.LoggerFactory

import java.util.concurrent.atomic.AtomicLong

/**
 * OTLP metrics for Spark execution lifecycle (Phase 1).
 *
 * Active execution counts use LongUpDownCounter (spark.executions.active.*): +1 on start,
 * -1 on close — the same semantics as the application-events Watcher (open START minus closed).
 * Monotonic opened/closed counters are retained for audit and opened-minus-closed panel queries.
 */
class SparkMetricsRegistry(meter: Meter, enabled: Boolean) {

  private val logger = LoggerFactory.getLogger(classOf[SparkMetricsRegistry])

  private val openedApp: LongCounter = meter.counterBuilder("spark.executions.opened.app").setUnit("{execution}").build()
  private val openedJob: LongCounter = meter.counterBuilder("spark.executions.opened.job").setUnit("{execution}").build()
  private val openedStage: LongCounter = meter.counterBuilder("spark.executions.opened.stage").setUnit("{execution}").build()
  private val openedTask: LongCounter = meter.counterBuilder("spark.executions.opened.task").setUnit("{execution}").build()
  private val openedSql: LongCounter = meter.counterBuilder("spark.executions.opened.sql").setUnit("{execution}").build()

  private val closedApp: LongCounter = meter.counterBuilder("spark.executions.closed.app").setUnit("{execution}").build()
  private val closedJob: LongCounter = meter.counterBuilder("spark.executions.closed.job").setUnit("{execution}").build()
  private val closedStage: LongCounter = meter.counterBuilder("spark.executions.closed.stage").setUnit("{execution}").build()
  private val closedTask: LongCounter = meter.counterBuilder("spark.executions.closed.task").setUnit("{execution}").build()
  private val closedSql: LongCounter = meter.counterBuilder("spark.executions.closed.sql").setUnit("{execution}").build()

  private val activeApp: LongUpDownCounter = meter.upDownCounterBuilder("spark.executions.active.app").setUnit("{execution}").build()
  private val activeJob: LongUpDownCounter = meter.upDownCounterBuilder("spark.executions.active.job").setUnit("{execution}").build()
  private val activeStage: LongUpDownCounter = meter.upDownCounterBuilder("spark.executions.active.stage").setUnit("{execution}").build()
  private val activeTask: LongUpDownCounter = meter.upDownCounterBuilder("spark.executions.active.task").setUnit("{execution}").build()
  private val activeSql: LongUpDownCounter = meter.upDownCounterBuilder("spark.executions.active.sql").setUnit("{execution}").build()

  private val openedCounters = Map(
    "app" -> openedApp, "job" -> openedJob, "stage" -> openedStage, "task" -> openedTask, "sql" -> openedSql
  )
  private val closedCounters = Map(
    "app" -> closedApp, "job" -> closedJob, "stage" -> closedStage, "task" -> closedTask, "sql" -> closedSql
  )
  private val activeUpDownCounters = Map(
    "app" -> activeApp, "job" -> activeJob, "stage" -> activeStage, "task" -> activeTask, "sql" -> activeSql
  )

  // In-memory guard against orphan closes (mirrors UpDownCounter; logged when close exceeds opens).
  private val activeGuard = Map(
    "app" -> new AtomicLong(0), "job" -> new AtomicLong(0), "stage" -> new AtomicLong(0),
    "task" -> new AtomicLong(0), "sql" -> new AtomicLong(0)
  )

  private val totalStageFailures = new AtomicLong(0)
  private val totalSpillMemoryBytes = new AtomicLong(0)
  private val totalSpillDiskBytes = new AtomicLong(0)

  private val stagesCompleted: LongCounter = meter
    .counterBuilder("spark.stage.outcomes.completed")
    .setUnit("{stage}")
    .build()

  private val stageShuffleReadBytes: LongCounter = meter
    .counterBuilder("spark.stage.shuffle.read.bytes")
    .setUnit("By")
    .build()

  private val stageShuffleWriteBytes: LongCounter = meter
    .counterBuilder("spark.stage.shuffle.write.bytes")
    .setUnit("By")
    .build()

  private val stageFailuresGauge = meter
    .upDownCounterBuilder("spark.stage.outcomes.failures")
    .setUnit("{failure}")
    .build()

  private val stageSpillMemoryGauge = meter
    .upDownCounterBuilder("spark.stage.outcomes.spill.memory.bytes")
    .setUnit("By")
    .build()

  private val stageSpillDiskGauge = meter
    .upDownCounterBuilder("spark.stage.outcomes.spill.disk.bytes")
    .setUnit("By")
    .build()

  if (enabled) {
    logger.info("OTLP execution metrics enabled (spark.executions.{opened,closed,active}.*, spark.stage.*)")
  }

  def recordExecutionStart(application: String, executionType: String): Unit = {
    if (!enabled || executionType == null || executionType.isEmpty) return
    try {
      openedCounters.get(executionType).foreach(_.add(1))
      activeUpDownCounters.get(executionType).foreach(_.add(1))
      activeGuard.get(executionType).foreach(_.incrementAndGet())
    } catch {
      case e: Exception =>
        logger.error(s"Failed to record execution start for type=$executionType application=$application", e)
    }
  }

  def recordExecutionClose(application: String, executionType: String): Unit = {
    if (!enabled || executionType == null || executionType.isEmpty) return
    try {
      activeGuard.get(executionType).foreach { guard =>
        if (guard.get() <= 0) {
          logger.warn(s"Orphan execution close ignored for type=$executionType application=$application (active guard already 0)")
        } else {
          guard.decrementAndGet()
          closedCounters.get(executionType).foreach(_.add(1))
          activeUpDownCounters.get(executionType).foreach(_.add(-1))
        }
      }
    } catch {
      case e: Exception =>
        logger.error(s"Failed to record execution close for type=$executionType application=$application", e)
    }
  }

  /** Register stage-outcome series at application start (net-zero add) so flat-zero lines appear in backends. */
  def publishStageOutcomeBaseline(): Unit = {
    if (!enabled) return
    try {
      val attrs = Attributes.empty()
      // add(0) is a no-op in OTLP; a +1/-1 pair registers the instrument without changing totals.
      stageFailuresGauge.add(1, attrs)
      stageFailuresGauge.add(-1, attrs)
      stageSpillMemoryGauge.add(1, attrs)
      stageSpillMemoryGauge.add(-1, attrs)
      stageSpillDiskGauge.add(1, attrs)
      stageSpillDiskGauge.add(-1, attrs)
    } catch {
      case e: Exception =>
        logger.warn(s"Failed to publish stage outcome baseline metrics: ${e.getMessage}", e)
    }
  }

  def recordStageCompleted(
      shuffleReadBytes: Long,
      shuffleWriteBytes: Long,
      memorySpillBytes: Long,
      diskSpillBytes: Long,
      failed: Boolean
  ): Unit = {
    if (!enabled) return
    try {
      val attrs = Attributes.empty()
      stagesCompleted.add(1, attrs)
      stageShuffleReadBytes.add(shuffleReadBytes, attrs)
      stageShuffleWriteBytes.add(shuffleWriteBytes, attrs)
      if (failed) {
        totalStageFailures.incrementAndGet()
        stageFailuresGauge.add(1, attrs)
      }
      stageSpillMemoryGauge.add(memorySpillBytes, attrs)
      stageSpillDiskGauge.add(diskSpillBytes, attrs)
      if (memorySpillBytes > 0) totalSpillMemoryBytes.addAndGet(memorySpillBytes)
      if (diskSpillBytes > 0) totalSpillDiskBytes.addAndGet(diskSpillBytes)
    } catch {
      case e: Exception =>
        logger.error("Failed to record stage completed metrics", e)
    }
  }
}
