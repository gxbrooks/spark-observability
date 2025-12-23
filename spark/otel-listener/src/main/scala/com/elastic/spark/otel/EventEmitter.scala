package com.elastic.spark.otel

import org.json4s._
import org.json4s.native.Serialization
import org.json4s.native.Serialization.write
import org.slf4j.LoggerFactory

import java.io.{File, FileWriter, PrintWriter}
import java.net.URI
import java.net.http.{HttpClient, HttpRequest, HttpResponse}
import java.nio.file.{Files, Paths}
import java.time.{Duration, Instant}
import java.util.{Base64, UUID}
import java.util.concurrent.{Executors, ScheduledExecutorService, TimeUnit}
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.{SSLContext, TrustManager, X509TrustManager}
import java.security.cert.X509Certificate
import java.security.SecureRandom
import scala.collection.mutable
import scala.util.{Failure, Success, Try}

/**
 * Event emitter for sending application events to Elasticsearch.
 * 
 * Architecture:
 * - Events are queued in buffers and flushed periodically
 * - flushAll() builds a single ordered bulk request: START events → close updates → END events
 * - Single bulk request with refresh=wait_for maintains order and ensures START events are indexed before updates
 * - Buffer swapping prevents blocking during network I/O
 * 
 * WATCHER_FREQUENCY: 5 seconds (Grafana watcher polling interval)
 * FLUSH_INTERVAL: 2.5 seconds (WATCHER_FREQUENCY/2, ensures continuous graph)
 */
class EventEmitter(elasticsearchUrl: String, username: String, password: String) {
  
  private val logger = LoggerFactory.getLogger(classOf[EventEmitter])
  
  // JSON serialization
  private implicit val formats: Formats = DefaultFormats
  
  // Configuration
  private val WATCHER_FREQUENCY_SECONDS = 5
  private val FLUSH_INTERVAL_SECONDS = WATCHER_FREQUENCY_SECONDS / 2.0 // 2.5 seconds
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
  
  // HTTP client
  private val httpClient: HttpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(10))
    .sslContext(sslContext)
    .build()
  
  // Base64-encoded credentials
  private val credentials: String = Base64.getEncoder.encodeToString(
    s"$username:$password".getBytes("UTF-8")
  )
  
  // Sealed trait for event types in the unified buffer
  sealed trait BufferedEvent
  case class StartEvent(event: ApplicationEvent, correlationKey: String) extends BufferedEvent
  case class CloseStartEvent(eventId: String, closedBy: String, state: String = "closed") extends BufferedEvent
  case class EndEvent(event: ApplicationEvent, correlationKey: String) extends BufferedEvent
  
  // Single unified event buffer (maintains arrival order)
  private val eventBuffer: mutable.Buffer[BufferedEvent] = mutable.Buffer.empty
  
  // Lock for buffer access
  private val bufferLock = new Object
  
  // Scheduled executor for periodic flushing
  private val flushExecutor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
  private val isShutdown = new AtomicBoolean(false)
  
  // Analytics logging - EventAnalytics class handles all CSV writing
  private val eventStats: EventAnalytics = new EventAnalytics()
  
  // Initialize periodic flushing
  flushExecutor.scheduleAtFixedRate(
    new Runnable {
      def run(): Unit = {
        if (!isShutdown.get()) {
          flushAll()
        }
      }
    },
    (FLUSH_INTERVAL_SECONDS * 1000).toLong,
    (FLUSH_INTERVAL_SECONDS * 1000).toLong,
    TimeUnit.MILLISECONDS
  )
  
  logger.info(s"EventEmitter initialized - Elasticsearch URL: $elasticsearchUrl")
  logger.info(s"Batching: Flush interval ${FLUSH_INTERVAL_SECONDS}s with refresh=wait_for")
  logger.info(s"Analytics log file: ${eventStats.logFile}")
  
  /**
   * Emit a START event (queued for batch transmission).
   * Lean routine - just adds to buffer, no HTTP body generation.
   */
  def emitStartEvent(event: ApplicationEvent, correlationKey: String): Long = {
    val emitStartNanos = System.nanoTime()
    val startTimeMs = System.currentTimeMillis()
    
    bufferLock.synchronized {
      eventBuffer += StartEvent(event, correlationKey)
    }
    
    val emitDurationNanos = System.nanoTime() - emitStartNanos
    eventStats.logStartEvent(correlationKey, event.event.id, startTimeMs, emitDurationNanos, event.operation.`type`)
    
    emitDurationNanos
  }
  
  /**
   * Close a START event (queued for batch transmission).
   * Lean routine - just adds to buffer.
   * @param eventId The ID of the start event to close
   * @param closedBy How the event was closed: "end" (matched END event) or "parent" (hierarchical closure)
   */
  def closeStartEvent(eventId: String, closedBy: String = "end"): Unit = {
    bufferLock.synchronized {
      eventBuffer += CloseStartEvent(eventId, closedBy)
    }
    
    eventStats.logCloseStartEvent(eventId)
  }
  
  /**
   * Emit an END event (queued for batch transmission).
   * Lean routine - just adds to buffer.
   */
  def emitEndEvent(event: ApplicationEvent, correlationKey: String): Long = {
    val emitStartNanos = System.nanoTime()
    val startTimeMs = System.currentTimeMillis()
    
    bufferLock.synchronized {
      eventBuffer += EndEvent(event, correlationKey)
    }
    
    val emitDurationNanos = System.nanoTime() - emitStartNanos
    eventStats.logEndEvent(correlationKey, event.event.id, startTimeMs, emitDurationNanos, event.operation.`type`)
    
    emitDurationNanos
  }
  
  /**
   * Build bulk request body maintaining arrival order.
   * Processes events in order: START events → close updates → END events.
   * For close updates, sets both state and closed_by fields.
   */
  private def buildBulkBody(events: Seq[BufferedEvent]): String = {
    val bodyParts = mutable.Buffer[String]()
    
    events.foreach {
      case StartEvent(event, _) =>
        // START events (index operations)
        bodyParts += s"""{"index":{"_index":"app-events","_id":"${event.event.id}"}}"""
        bodyParts += write(event)
        
      case CloseStartEvent(eventId, closedBy, state) =>
        // Close updates (update operations for START events)
        // Update both state and closed_by fields
        bodyParts += s"""{"update":{"_index":"app-events","_id":"$eventId"}}"""
        bodyParts += s"""{"script":{"source":"ctx._source.event.state = params.state; ctx._source.event.closed_by = params.closed_by","lang":"painless","params":{"state":"$state","closed_by":"$closedBy"}}}"""
        
      case EndEvent(event, _) =>
        // END events (index operations)
        bodyParts += s"""{"index":{"_index":"app-events","_id":"${event.event.id}"}}"""
        bodyParts += write(event)
    }
    
    bodyParts.mkString("\n") + "\n"
  }
  
  /**
   * Send bulk request with retry logic.
   */
  private def sendOrderedBulkRequest(bulkBody: String, totalEvents: Int, retryCount: Int = 0): Unit = {
    val request = HttpRequest.newBuilder()
      .uri(URI.create(s"$elasticsearchUrl/_bulk?refresh=wait_for"))
      .header("Content-Type", "application/x-ndjson")
      .header("Authorization", s"Basic $credentials")
      .timeout(Duration.ofSeconds(60))
      .POST(HttpRequest.BodyPublishers.ofString(bulkBody))
      .build()
    
    Try {
      val startTime = System.nanoTime()
      val response = httpClient.send(request, HttpResponse.BodyHandlers.ofString())
      val elapsedMs = (System.nanoTime() - startTime) / 1000000
      
      if (response.statusCode() >= 200 && response.statusCode() < 300) {
        val responseBody = response.body()
        if (responseBody.contains("\"errors\":true")) {
          // Check for "document missing" errors in close updates (acceptable if START event failed to index)
          val errorPattern = """"error":\s*\{[^}]*"reason":\s*"([^"]+)"""".r
          val errors = errorPattern.findAllMatchIn(responseBody).toSeq.map(_.group(1))
          
          // Document missing errors are acceptable for close updates (START event may have failed)
          val allDocumentMissing = errors.nonEmpty && errors.forall(_.contains("document missing"))
          
          if (allDocumentMissing) {
            logger.debug(s"Bulk request: $totalEvents events, some documents missing (acceptable, ${elapsedMs}ms)")
            return
          }
          
          val errorSummary = errors.take(3).mkString("; ")
          throw new Exception(s"Bulk API returned errors: $errorSummary")
        }
        logger.debug(s"Bulk request: $totalEvents events sent successfully (${elapsedMs}ms)")
      } else {
        throw new Exception(s"HTTP ${response.statusCode()}: ${response.body().take(500)}")
      }
    } match {
      case Success(_) =>
        // Success
      case Failure(e) if retryCount < MAX_RETRIES =>
        val delay = RETRY_DELAY_MS * (retryCount + 1)
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.warn(s"Failed to send bulk request ($totalEvents events, attempt ${retryCount + 1}/${MAX_RETRIES}), retrying in ${delay}ms: $errorMsg")
        Thread.sleep(delay)
        sendOrderedBulkRequest(bulkBody, totalEvents, retryCount + 1)
      case Failure(e) =>
        val errorMsg = Option(e.getMessage).getOrElse(e.getClass.getName)
        logger.error(s"Failed to send bulk request ($totalEvents events) after $MAX_RETRIES retries: $errorMsg", e)
    }
  }
  
  /**
   * Flush all events to Elasticsearch.
   * Uses buffer swapping to avoid blocking event emission - events are extracted atomically
   * and processed outside the lock, maintaining arrival order.
   */
  def flushAll(): Unit = {
    val flushStartNanos = System.nanoTime()
    val flushStartTimeMs = System.currentTimeMillis()
    
    // Extract all events atomically (buffer swap) - maintains arrival order
    val eventsToProcess = bufferLock.synchronized {
      if (eventBuffer.nonEmpty) {
        val events = eventBuffer.toSeq
        eventBuffer.clear()
        events
      } else {
        Seq.empty[BufferedEvent]
      }
    }
    
    val totalEvents = eventsToProcess.size
    
    if (totalEvents > 0) {
      eventStats.logFlushStart(flushStartTimeMs, totalEvents)
      
      var flushError: Option[Throwable] = None
      
      Try {
        // Build bulk body maintaining arrival order
        val bulkBody = buildBulkBody(eventsToProcess)
        
        // Send single bulk request with refresh=wait_for
        sendOrderedBulkRequest(bulkBody, totalEvents)
      } match {
        case Success(_) =>
          // Success
        case Failure(e) =>
          flushError = Some(e)
          logger.error(s"Error during flushAll ($totalEvents events): ${e.getMessage}", e)
      }
      
      // Calculate duration and log flush end marker (always executed)
      val flushDurationNanos = System.nanoTime() - flushStartNanos
      val flushEndTimeMs = System.currentTimeMillis()
      
      eventStats.logFlushEnd(flushEndTimeMs, flushDurationNanos, totalEvents, isError = flushError.isDefined)
      
      if (flushError.isEmpty) {
        logger.debug(s"Flushed $totalEvents events in ${flushDurationNanos / 1000000}ms")
      }
    }
  }
  
  /**
   * Shutdown the emitter and flush all remaining events.
   */
  def shutdown(): Unit = {
    if (isShutdown.compareAndSet(false, true)) {
      logger.info("Shutting down EventEmitter, flushing all remaining events...")
      
      flushExecutor.shutdown()
      try {
        if (!flushExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
          flushExecutor.shutdownNow()
        }
      } catch {
        case e: InterruptedException =>
          flushExecutor.shutdownNow()
          Thread.currentThread().interrupt()
      }
      
      flushAll()
      eventStats.close()
      
      logger.info("EventEmitter shutdown complete")
    }
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
  duration: Option[Long] = None,
  closedBy: Option[String] = None  // "end" or "parent" for start events
)

case class Operation(
  `type`: String,
  id: String,
  name: String,
  result: Option[String] = None,
  `parent.id`: Option[String] = None,
  `correlation.key`: Option[String] = None
)

case class Correlation(
  `span.id`: Option[String] = None,
  `trace.id`: Option[String] = None,
  `start.event.id`: Option[String] = None,
  `parent.event.id`: Option[String] = None,
  `correlation.key`: Option[String] = None
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

/**
 * EventAnalytics class handles all CSV analytics logging.
 * Encapsulates CSV file creation and writing operations.
 * Log file location: ${SPARK_LOG_DIR}/event-analytics-YYYYMMDD-HHMMSS.csv (default: /opt/spark/logs)
 * Falls back to /tmp if SPARK_LOG_DIR is not writable.
 */
class EventAnalytics {
  private val logger = LoggerFactory.getLogger(classOf[EventAnalytics])
  
  // CSV writer and file - initialized via helper method
  // Using lazy initialization pattern
  private lazy val writerAndFile: (java.io.File, PrintWriter) = {
    val sparkLogDir = sys.env.getOrElse("SPARK_LOG_DIR", "/opt/spark/logs")
    val logDir = Paths.get(sparkLogDir)
    
    val writableLogDir = Try {
      if (!Files.exists(logDir)) {
        Files.createDirectories(logDir)
      }
      val testFile = logDir.resolve(".write-test")
      Files.write(testFile, "test".getBytes)
      Files.delete(testFile)
      logDir
    }.getOrElse {
      logger.warn(s"Cannot write to $sparkLogDir, using /tmp for analytics logs")
      Paths.get("/tmp")
    }
    
    val timestampSuffix = java.time.LocalDateTime.now().format(
      java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
    )
    
    val file = writableLogDir.resolve(s"event-analytics-$timestampSuffix.csv").toFile
    val pw = new PrintWriter(new FileWriter(file, true))
    pw.println("timestamp,op_type,correlation_id,event_id,start_time_ms,duration_nanos,event_type,event_count")
    pw.flush()
    (file, pw)
  }
  
  val logFile: java.io.File = writerAndFile._1
  private val writer: PrintWriter = writerAndFile._2
  
  /**
   * Format timestamp for LibreOffice Calc (MM/dd/yyyy HH:mm:ss.SSS)
   */
  private def formatTimestamp(millis: Long): String = {
    val instant = Instant.ofEpochMilli(millis)
    val dateTime = java.time.LocalDateTime.ofInstant(instant, java.time.ZoneId.systemDefault())
    val formatter = java.time.format.DateTimeFormatter.ofPattern("MM/dd/yyyy HH:mm:ss.SSS")
    dateTime.format(formatter)
  }
  
  
  /**
   * Log start event to CSV.
   */
  def logStartEvent(correlationKey: String, eventId: String, startTimeMs: Long, durationNanos: Long, eventType: String): Unit = {
    val timestamp = formatTimestamp(startTimeMs)
    writer.synchronized {
      writer.println(s"$timestamp,start,$correlationKey,$eventId,$startTimeMs,$durationNanos,$eventType,")
      writer.flush()
    }
  }
  
  /**
   * Log end event to CSV.
   */
  def logEndEvent(correlationKey: String, eventId: String, startTimeMs: Long, durationNanos: Long, eventType: String): Unit = {
    val timestamp = formatTimestamp(startTimeMs)
    writer.synchronized {
      writer.println(s"$timestamp,end,$correlationKey,$eventId,$startTimeMs,$durationNanos,$eventType,")
      writer.flush()
    }
  }
  
  /**
   * Log close_start event to CSV.
   */
  def logCloseStartEvent(eventId: String): Unit = {
    val timestamp = formatTimestamp(System.currentTimeMillis())
    writer.synchronized {
      writer.println(s"$timestamp,close_start,,$eventId,,,,")
      writer.flush()
    }
  }
  
  /**
   * Log flush start marker to CSV.
   */
  def logFlushStart(flushStartTimeMs: Long, eventCount: Int): Unit = {
    val timestamp = formatTimestamp(flushStartTimeMs)
    writer.synchronized {
      writer.println(s"$timestamp,flush_start,,,,,,$eventCount")
      writer.flush()
    }
  }
  
  /**
   * Log flush end marker to CSV.
   */
  def logFlushEnd(flushEndTimeMs: Long, durationNanos: Long, eventCount: Int, isError: Boolean = false): Unit = {
    val timestamp = formatTimestamp(flushEndTimeMs)
    val opType = if (isError) "flush_end_error" else "flush_end"
    writer.synchronized {
      writer.println(s"$timestamp,$opType,,,,$durationNanos,,$eventCount")
      writer.flush()
    }
  }
  
  /**
   * Close the analytics writer.
   */
  def close(): Unit = {
    writer.synchronized {
      writer.close()
    }
  }
}

/**
 * Metadata for START events stored in-memory for correlation and closure.
 * Used in OTelSparkListener to track events that need to be closed.
 * NOT serialized to Elasticsearch - this is runtime-only metadata.
 */
case class EventStartMetadata(
  eventId: String,
  startTime: Long,
  correlationKey: String
)
