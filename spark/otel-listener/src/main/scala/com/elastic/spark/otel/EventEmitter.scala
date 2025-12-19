package com.elastic.spark.otel

import org.json4s._
import org.json4s.native.Serialization
import org.json4s.native.Serialization.write
import org.slf4j.LoggerFactory

import java.net.URI
import java.net.http.{HttpClient, HttpRequest, HttpResponse}
import java.time.{Duration, Instant}
import java.util.{Base64, UUID}
import java.util.concurrent.{ConcurrentLinkedQueue, Executors, TimeUnit}
import java.util.concurrent.locks.ReentrantLock
import scala.collection.mutable.ArrayBuffer
import scala.util.{Failure, Success, Try}
import javax.net.ssl.{SSLContext, TrustManager, X509TrustManager}
import java.security.cert.X509Certificate
import java.security.SecureRandom

/**
 * Event emitter for sending application events to Elasticsearch.
 * 
 * Supports:
 * - Synchronous event emission with retries
 * - Batching for events and state updates
 * - Error logging to file (via SLF4J) and Elasticsearch
 * - Configurable timeout and retry counts
 * - Correlation with OpenTelemetry spans
 */
class EventEmitter(elasticsearchUrl: String, username: String, password: String) {
  
  private val logger = LoggerFactory.getLogger(classOf[EventEmitter])
  
  // JSON serialization
  private implicit val formats: Formats = DefaultFormats
  
  // Configuration
  private val BATCH_SIZE = 100
  private val BATCH_FLUSH_INTERVAL_SECONDS = 5
  private val MAX_RETRIES = 3
  private val RETRY_DELAY_MS = 1000
  
  // Trust manager that accepts all certificates (for development/testing)
  private val trustAllCerts: Array[TrustManager] = Array(new X509TrustManager {
    def getAcceptedIssuers: Array[X509Certificate] = Array.empty
    def checkClientTrusted(certs: Array[X509Certificate], authType: String): Unit = ()
    def checkServerTrusted(certs: Array[X509Certificate], authType: String): Unit = ()
  })
  
  // SSL context that trusts all certificates
  private val sslContext: SSLContext = {
    val ctx = SSLContext.getInstance("TLS")
    ctx.init(null, trustAllCerts, new SecureRandom())
    ctx
  }
  
  // HTTP client with timeout and SSL context that accepts self-signed certificates
  private val httpClient: HttpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(10))
    .sslContext(sslContext)
    .build()
  
  // Base64-encoded credentials
  private val credentials: String = Base64.getEncoder.encodeToString(
    s"$username:$password".getBytes("UTF-8")
  )
  
  // Event batching
  private val eventBatch: ArrayBuffer[ApplicationEvent] = new ArrayBuffer[ApplicationEvent]()
  private val eventBatchLock = new ReentrantLock()
  
  // State update batching (eventId -> state)
  private val stateUpdateBatch: ArrayBuffer[(String, String)] = new ArrayBuffer[(String, String)]()
  private val stateUpdateBatchLock = new ReentrantLock()
  
  // Batch flush executor
  private val batchExecutor = Executors.newSingleThreadScheduledExecutor()
  
  // Start periodic batch flush
  batchExecutor.scheduleWithFixedDelay(
    () => flushBatches(),
    BATCH_FLUSH_INTERVAL_SECONDS, BATCH_FLUSH_INTERVAL_SECONDS, TimeUnit.SECONDS
  )
  
  logger.info(s"EventEmitter initialized - Elasticsearch URL: $elasticsearchUrl, Batch size: $BATCH_SIZE, Flush interval: ${BATCH_FLUSH_INTERVAL_SECONDS}s")
  
  /**
   * Update an existing event's state field in Elasticsearch.
   * Batched - added to batch queue, flushed periodically or when batch size reached.
   * Use this for high-volume updates (e.g., tasks).
   */
  def updateEventState(eventId: String, state: String): Unit = {
    stateUpdateBatchLock.lock()
    try {
      stateUpdateBatch += ((eventId, state))
      if (stateUpdateBatch.size >= BATCH_SIZE) {
        flushStateUpdates()
      }
    } finally {
      stateUpdateBatchLock.unlock()
    }
  }

  /**
   * Update an existing event's state field in Elasticsearch immediately (synchronous).
   * Use this for critical updates (e.g., app, job, stage end events) where we need
   * guaranteed delivery before application termination.
   * 
   * IMPORTANT: Flushes any pending event batches first to ensure the START event
   * is indexed before attempting the update.
   * 
   * @param eventId The event ID to update
   * @param state The new state (typically "closed")
   * @param maxRetries Maximum number of retry attempts (default: 5)
   */
  def updateEventStateImmediate(eventId: String, state: String, maxRetries: Int = 5): Unit = {
    if (eventId == null || eventId.isEmpty) {
      logger.warn(s"Cannot update event state: eventId is null or empty")
      return
    }

    // CRITICAL: Flush pending event batches first to ensure START events are indexed
    // before we try to update them
    flushEvents()

    var retryCount = 0
    var success = false

    while (!success && retryCount < maxRetries) {
      Try {
        sendSingleStateUpdate(eventId, state)
        success = true
        logger.debug(s"Immediately updated event $eventId state to $state")
      } match {
        case Success(_) =>
          // Success, exit loop
        case Failure(e) if retryCount < maxRetries - 1 =>
          val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
          // For "document missing" errors, wait a bit and retry (START event may still be indexing)
          if (errorMsg.contains("document missing") || errorMsg.contains("not_found")) {
            retryCount += 1
            val delay = RETRY_DELAY_MS * retryCount * 2 // Longer delay for indexing to complete
            logger.warn(s"Event $eventId not found in Elasticsearch (attempt $retryCount/$maxRetries), waiting ${delay}ms for indexing to complete")
            Thread.sleep(delay)
          } else {
            retryCount += 1
            val delay = RETRY_DELAY_MS * retryCount
            logger.warn(s"Failed to immediately update event $eventId state (attempt $retryCount/$maxRetries), retrying in ${delay}ms: $errorMsg")
            Thread.sleep(delay)
          }
        case Failure(e) =>
          retryCount += 1
          val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
          logger.error(s"Failed to immediately update event $eventId state after $maxRetries retries: $errorMsg", e)
          logError("state_update_immediate_failed_final", e, eventInfo = Some((eventId, "state_update", None, None)), retryCount = Some(maxRetries))
          // Fallback to batching if immediate update fails
          logger.info(s"Falling back to batched update for event $eventId")
          updateEventState(eventId, state)
      }
    }
  }

  /**
   * Send a single state update synchronously (for immediate updates).
   */
  private def sendSingleStateUpdate(eventId: String, state: String): Unit = {
    val bulkBody = s"""{"update":{"_index":"app-events","_id":"$eventId"}}\n""" +
                   s"""{"script":{"source":"ctx._source.event.state = params.state","lang":"painless","params":{"state":"$state"}}}\n"""

    val request = HttpRequest.newBuilder()
      .uri(URI.create(s"$elasticsearchUrl/_bulk"))
      .header("Content-Type", "application/x-ndjson")
      .header("Authorization", s"Basic $credentials")
      .timeout(Duration.ofSeconds(10)) // Shorter timeout for immediate updates
      .POST(HttpRequest.BodyPublishers.ofString(bulkBody))
      .build()

    val startTime = System.nanoTime()
    val response = Try {
      httpClient.send(request, HttpResponse.BodyHandlers.ofString())
    }.getOrElse(throw new Exception(s"Failed to send HTTP request to $elasticsearchUrl/_bulk: connection failed or timeout"))
    val elapsedMs = (System.nanoTime() - startTime) / 1000000

    if (response.statusCode() >= 200 && response.statusCode() < 300) {
      val responseBody = response.body()
      if (responseBody.contains("\"errors\":true")) {
        // Parse individual errors from bulk response
        val errorPattern = """"error":\s*\{[^}]*"reason":\s*"([^"]+)"""".r
        val errors = errorPattern.findAllMatchIn(responseBody).map(_.group(1)).take(3).mkString("; ")
        throw new Exception(s"Bulk update API returned errors: $errors")
      }
      logger.debug(s"Immediate state update for event $eventId succeeded (${elapsedMs}ms)")
    } else {
      throw new Exception(s"HTTP ${response.statusCode()}: ${response.body().take(500)}")
    }
  }

  /**
   * Emit an application event to Elasticsearch.
   * Batched - added to batch queue, flushed periodically or when batch size reached.
   */
  def emitEvent(event: ApplicationEvent): Unit = {
    eventBatchLock.lock()
    try {
      eventBatch += event
      if (eventBatch.size >= BATCH_SIZE) {
        flushEvents()
      }
    } finally {
      eventBatchLock.unlock()
    }
  }
  
  /**
   * Flush all batches (events and state updates).
   */
  private def flushBatches(): Unit = {
    flushEvents()
    flushStateUpdates()
  }
  
  /**
   * Flush event batch - send all events in batch synchronously with retries.
   */
  private def flushEvents(): Unit = {
    var eventsToFlush: ArrayBuffer[ApplicationEvent] = ArrayBuffer.empty
    
    eventBatchLock.lock()
    try {
      if (eventBatch.nonEmpty) {
        eventsToFlush = eventBatch.clone()
        eventBatch.clear()
      }
    } finally {
      eventBatchLock.unlock()
    }
    
    if (eventsToFlush.nonEmpty) {
      logger.debug(s"Flushing ${eventsToFlush.size} events to Elasticsearch")
      sendEventsBatchWithRetry(eventsToFlush.toSeq)
    }
  }
  
  /**
   * Flush state update batch - send all updates in batch synchronously with retries.
   */
  private def flushStateUpdates(): Unit = {
    var updatesToFlush: ArrayBuffer[(String, String)] = ArrayBuffer.empty
    
    stateUpdateBatchLock.lock()
    try {
      if (stateUpdateBatch.nonEmpty) {
        updatesToFlush = stateUpdateBatch.clone()
        stateUpdateBatch.clear()
      }
    } finally {
      stateUpdateBatchLock.unlock()
    }
    
    if (updatesToFlush.nonEmpty) {
      logger.debug(s"Flushing ${updatesToFlush.size} state updates to Elasticsearch")
      sendStateUpdatesBatchWithRetry(updatesToFlush.toSeq)
    }
  }
  
  /**
   * Send events batch with retry logic (synchronous).
   */
  private def sendEventsBatchWithRetry(events: Seq[ApplicationEvent], retryCount: Int = 0): Unit = {
    Try {
      sendEventsBatch(events)
    } match {
      case Success(_) =>
        logger.debug(s"Successfully sent ${events.size} events to Elasticsearch")
      case Failure(e) if retryCount < MAX_RETRIES =>
        val delay = RETRY_DELAY_MS * (retryCount + 1)
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.warn(s"Failed to send ${events.size} events (attempt ${retryCount + 1}/${MAX_RETRIES}), retrying in ${delay}ms: $errorMsg")
        logError("event_emission_batch_failed", e, eventInfo = events.headOption.map(e => (e.event.id, e.operation.`type`, e.spark.flatMap(_.`app.id`), e.spark.flatMap(_.`app.name`))), retryCount = Some(retryCount + 1))
        Thread.sleep(delay)
        sendEventsBatchWithRetry(events, retryCount + 1)
      case Failure(e) =>
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.error(s"Failed to send ${events.size} events after $MAX_RETRIES retries: $errorMsg", e)
        logError("event_emission_batch_failed_final", e, eventInfo = events.headOption.map(e => (e.event.id, e.operation.`type`, e.spark.flatMap(_.`app.id`), e.spark.flatMap(_.`app.name`))), retryCount = Some(MAX_RETRIES))
        // Re-queue events for retry by background processor
        events.foreach { event =>
          eventBatchLock.lock()
          try {
            eventBatch += event
          } finally {
            eventBatchLock.unlock()
          }
        }
    }
  }
  
  /**
   * Send events batch using Elasticsearch bulk API (synchronous).
   */
  private def sendEventsBatch(events: Seq[ApplicationEvent]): Unit = {
    if (events.isEmpty) return
    
    val bulkBody = events.map { event =>
      val action = s"""{"index":{"_index":"app-events","_id":"${event.event.id}"}}"""
      val source = write(event)
      s"$action\n$source"
    }.mkString("\n") + "\n"
    
    val request = HttpRequest.newBuilder()
      .uri(URI.create(s"$elasticsearchUrl/_bulk"))
      .header("Content-Type", "application/x-ndjson")
      .header("Authorization", s"Basic $credentials")
      .timeout(Duration.ofSeconds(30))
      .POST(HttpRequest.BodyPublishers.ofString(bulkBody))
      .build()
    
    val startTime = System.nanoTime()
    val response = httpClient.send(request, HttpResponse.BodyHandlers.ofString())
    val elapsedMs = (System.nanoTime() - startTime) / 1000000
    
    if (response.statusCode() >= 200 && response.statusCode() < 300) {
      // Parse bulk response to check for errors
      val responseBody = response.body()
      if (responseBody.contains("\"errors\":true")) {
        throw new Exception(s"Bulk API returned errors: ${responseBody.take(500)}")
      }
      logger.debug(s"Bulk sent ${events.size} events successfully (${elapsedMs}ms)")
    } else {
      throw new Exception(s"HTTP ${response.statusCode()}: ${response.body().take(500)}")
    }
  }
  
  /**
   * Send state updates batch with retry logic (synchronous).
   */
  private def sendStateUpdatesBatchWithRetry(updates: Seq[(String, String)], retryCount: Int = 0): Unit = {
    Try {
      sendStateUpdatesBatch(updates)
    } match {
      case Success(_) =>
        logger.debug(s"Successfully sent ${updates.size} state updates to Elasticsearch")
      case Failure(e) if retryCount < MAX_RETRIES =>
        val delay = RETRY_DELAY_MS * (retryCount + 1)
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.warn(s"Failed to send ${updates.size} state updates (attempt ${retryCount + 1}/${MAX_RETRIES}), retrying in ${delay}ms: $errorMsg")
        logError("state_update_batch_failed", e, eventInfo = None, updates = Some(updates), retryCount = Some(retryCount + 1))
        Thread.sleep(delay)
        sendStateUpdatesBatchWithRetry(updates, retryCount + 1)
      case Failure(e) =>
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.error(s"Failed to send ${updates.size} state updates after $MAX_RETRIES retries: $errorMsg", e)
        logError("state_update_batch_failed_final", e, eventInfo = None, updates = Some(updates), retryCount = Some(MAX_RETRIES))
        // Re-queue updates for retry
        updates.foreach { case (eventId, state) =>
          stateUpdateBatchLock.lock()
          try { stateUpdateBatch += ((eventId, state)) } finally { stateUpdateBatchLock.unlock() }
        }
    }
  }
  
  /**
   * Send state updates batch using Elasticsearch bulk update API (synchronous).
   */
  private def sendStateUpdatesBatch(updates: Seq[(String, String)]): Unit = {
    if (updates.isEmpty) return
    
    val bulkBody = updates.map { case (eventId, state) =>
      val action = s"""{"update":{"_index":"app-events","_id":"$eventId"}}"""
      val doc = s"""{"script":{"source":"ctx._source.event.state = params.state","lang":"painless","params":{"state":"$state"}}}"""
      s"$action\n$doc"
    }.mkString("\n") + "\n"
    
    val request = HttpRequest.newBuilder()
      .uri(URI.create(s"$elasticsearchUrl/_bulk"))
      .header("Content-Type", "application/x-ndjson")
      .header("Authorization", s"Basic $credentials")
      .timeout(Duration.ofSeconds(30))
      .POST(HttpRequest.BodyPublishers.ofString(bulkBody))
      .build()
    
    val startTime = System.nanoTime()
    val response = Try {
      httpClient.send(request, HttpResponse.BodyHandlers.ofString())
    }.getOrElse(throw new Exception(s"Failed to send HTTP request to $elasticsearchUrl/_bulk: connection failed or timeout"))
    val elapsedMs = (System.nanoTime() - startTime) / 1000000
    
    if (response.statusCode() >= 200 && response.statusCode() < 300) {
      // Parse bulk response to check for errors
      val responseBody = response.body()
      if (responseBody.contains("\"errors\":true")) {
        // Parse individual errors from bulk response
        val errorPattern = """"error":\s*\{[^}]*"reason":\s*"([^"]+)"""".r
        val errors = errorPattern.findAllMatchIn(responseBody).map(_.group(1)).take(5).mkString("; ")
        throw new Exception(s"Bulk update API returned errors: $errors. Full response: ${responseBody.take(1000)}")
      }
      logger.debug(s"Bulk updated ${updates.size} event states successfully (${elapsedMs}ms)")
    } else {
      throw new Exception(s"HTTP ${response.statusCode()}: ${response.body().take(500)}")
    }
  }
  
  /**
   * Log error to file (via SLF4J) and to Elasticsearch.
   */
  private def logError(
    errorType: String,
    exception: Throwable,
    eventInfo: Option[(String, String, Option[String], Option[String])] = None,
    updates: Option[Seq[(String, String)]] = None,
    httpStatus: Option[Int] = None,
    responseBody: Option[String] = None,
    retryCount: Option[Int] = None
  ): Unit = {
    val errorId = UUID.randomUUID().toString
    val timestamp = Instant.now().toString
    
    // Log to file via SLF4J (will be picked up by Elastic Agent)
    val errorMsg = Option(exception.getMessage).getOrElse(exception.getClass.getName)
    val logMessage = s"[$errorType] $errorMsg"
    logger.error(logMessage, exception)
    
    // Log to Elasticsearch (async, best effort)
    Try {
      val errorDoc = Map(
        "@timestamp" -> timestamp,
        "log.level" -> "ERROR",
        "log.logger" -> classOf[EventEmitter].getName,
        "message" -> logMessage,
        "error.type" -> exception.getClass.getName,
        "error.message" -> errorMsg,
        "error.stack_trace" -> exception.getStackTrace.map(_.toString).mkString("\n"),
        "elasticsearch.url" -> elasticsearchUrl,
        "elasticsearch.operation" -> errorType,
        "elasticsearch.failed" -> true
      ) ++ (eventInfo.map { case (eventId, opType, appId, appName) =>
        Map(
          "event.id" -> eventId,
          "event.operation.type" -> opType,
          "spark.app.id" -> appId.getOrElse(""),
          "spark.app.name" -> appName.getOrElse("")
        )
      }.getOrElse(Map.empty)) ++
      (httpStatus.map(s => Map("elasticsearch.http_status" -> s)).getOrElse(Map.empty)) ++
      (responseBody.map(b => Map("elasticsearch.response_body" -> b.take(1000))).getOrElse(Map.empty)) ++
      (retryCount.map(r => Map("elasticsearch.retry_count" -> r)).getOrElse(Map.empty)) ++
      (updates.map(u => Map("state_updates.count" -> u.size)).getOrElse(Map.empty)) ++
      Map(
        "service.name" -> "spark-otel-listener",
        "error.id" -> errorId
      )
      
      val json = write(errorDoc)
      val errorIndexUrl = s"$elasticsearchUrl/logs-spark-otel-errors-default/_doc/$errorId"
      val request = HttpRequest.newBuilder()
        .uri(URI.create(errorIndexUrl))
        .header("Content-Type", "application/json")
        .header("Authorization", s"Basic $credentials")
        .timeout(Duration.ofSeconds(5))
        .POST(HttpRequest.BodyPublishers.ofString(json))
        .build()
      
      // Send async for error logging (best effort, don't block)
      httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
        .thenAccept { response =>
          if (response.statusCode() >= 200 && response.statusCode() < 300) {
            logger.debug(s"Error logged to Elasticsearch: $errorId")
          } else {
            logger.warn(s"Failed to log error to Elasticsearch: HTTP ${response.statusCode()}")
          }
        }
        .exceptionally { throwable =>
          logger.warn(s"Failed to log error to Elasticsearch: ${throwable.getMessage}")
          null
        }
    }.recover { case e =>
      logger.warn(s"Failed to prepare error log for Elasticsearch: ${e.getMessage}")
    }
  }
  
  /**
   * Shutdown the emitter, flushing any remaining batches.
   */
  def shutdown(): Unit = {
    logger.info("Shutting down EventEmitter...")
    
    // Flush remaining batches
    flushBatches()
    
    // Shutdown batch executor
    batchExecutor.shutdown()
    try {
      if (!batchExecutor.awaitTermination(10, TimeUnit.SECONDS)) {
        batchExecutor.shutdownNow()
      }
    } catch {
      case e: InterruptedException =>
        batchExecutor.shutdownNow()
    }
    
    logger.info("EventEmitter shutdown complete")
  }
}

/**
 * Application event data structures.
 */
case class ApplicationEvent(
  `@timestamp`: String,
  event: EventMetadata,
  application: String,
  operation: Operation,
  correlation: Correlation,
  spark: Option[SparkMetadata] = None
)

case class EventMetadata(
  id: String,
  `type`: String,
  category: String = "application",
  state: String,
  duration: Option[Long] = None
)

case class Operation(
  `type`: String,
  id: String,
  name: String,
  result: Option[String] = None,
  `parent.id`: Option[String] = None
)

case class Correlation(
  `span.id`: Option[String] = None,
  `trace.id`: Option[String] = None,
  `start.event.id`: Option[String] = None,
  `parent.event.id`: Option[String] = None
)

case class SparkMetadata(
  `app.id`: Option[String] = None,
  `app.name`: Option[String] = None,
  user: Option[String] = None,
  `job.id`: Option[Long] = None,
  `job.stage.count`: Option[Long] = None,
  `stage.id`: Option[Long] = None,
  `stage.name`: Option[String] = None,
  `stage.attempt`: Option[Long] = None,
  `stage.num.tasks`: Option[Long] = None,
  `stage.result`: Option[String] = None,
  `task.id`: Option[Long] = None,
  `task.index`: Option[Long] = None,
  `task.executor.id`: Option[String] = None,
  `sql.execution.id`: Option[Long] = None,
  `sql.description`: Option[String] = None,
  `sql.query_plan.simplified`: Option[String] = None,
  `sql.query_plan.verbose`: Option[String] = None,
  metrics: Option[SparkEventMetrics] = None
)

case class SparkEventMetrics(
  `duration.ms`: Option[Long] = None,
  `shuffle.read.bytes`: Option[Long] = None,
  `shuffle.write.bytes`: Option[Long] = None,
  `input.bytes`: Option[Long] = None,
  `output.bytes`: Option[Long] = None,
  `memory.spilled.bytes`: Option[Long] = None,
  `disk.spilled.bytes`: Option[Long] = None,
  `executor.run.time.ms`: Option[Long] = None,
  `executor.cpu.time.ms`: Option[Long] = None
)
