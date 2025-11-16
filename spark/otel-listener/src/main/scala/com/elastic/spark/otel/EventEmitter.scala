package com.elastic.spark.otel

import org.json4s._
import org.json4s.native.Serialization
import org.json4s.native.Serialization.write
import org.slf4j.LoggerFactory

import java.net.URI
import java.net.http.{HttpClient, HttpRequest, HttpResponse}
import java.time.{Duration, Instant}
import java.util.{Base64, UUID}
import java.util.concurrent.{CompletableFuture, ConcurrentLinkedQueue, Executors, TimeUnit}
import scala.util.{Failure, Success, Try}
import javax.net.ssl.{SSLContext, TrustManager, X509TrustManager}
import java.security.cert.X509Certificate
import java.security.SecureRandom

/**
 * Event emitter for sending application events to Elasticsearch.
 * 
 * Supports:
 * - Async, non-blocking event emission
 * - Retry queue for failed emissions
 * - Configurable timeout
 * - Correlation with OpenTelemetry spans
 */
class EventEmitter(elasticsearchUrl: String, username: String, password: String) {
  
  private val logger = LoggerFactory.getLogger(classOf[EventEmitter])
  
  // JSON serialization
  private implicit val formats: Formats = DefaultFormats
  
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
  
  // Retry queue for failed emissions
  private val retryQueue: ConcurrentLinkedQueue[ApplicationEvent] = new ConcurrentLinkedQueue()
  
  // Background retry thread
  private val retryExecutor = Executors.newSingleThreadScheduledExecutor()
  
  // Start retry thread
  retryExecutor.scheduleWithFixedDelay(
    () => processRetryQueue(),
    5, 5, TimeUnit.SECONDS
  )
  
  logger.info(s"EventEmitter initialized - Elasticsearch URL: $elasticsearchUrl")
  
  /**
   * Emit an application event to Elasticsearch.
   * Non-blocking - returns immediately.
   */
  def emitEvent(event: ApplicationEvent): Unit = {
    val startTime = System.nanoTime()
    
    try {
      val json = write(event)
      val eventId = event.event.id
      
      // Build HTTP request
      val request = HttpRequest.newBuilder()
        .uri(URI.create(s"$elasticsearchUrl/app-events/_doc/$eventId"))
        .header("Content-Type", "application/json")
        .header("Authorization", s"Basic $credentials")
        .timeout(Duration.ofSeconds(5))
        .POST(HttpRequest.BodyPublishers.ofString(json))
        .build()
      
      // Send async
      httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
        .thenAccept { response =>
          val elapsedMs = (System.nanoTime() - startTime) / 1000000
          
          if (response.statusCode() >= 200 && response.statusCode() < 300) {
            logger.debug(s"Event $eventId emitted successfully (${elapsedMs}ms)")
          } else {
            logger.warn(s"Event $eventId emission failed: HTTP ${response.statusCode()} - ${response.body()} (${elapsedMs}ms)")
            retryQueue.offer(event)
          }
        }
        .exceptionally { throwable =>
          val elapsedMs = (System.nanoTime() - startTime) / 1000000
          logger.warn(s"Event $eventId emission failed: ${throwable.getMessage} (${elapsedMs}ms), queuing for retry")
          retryQueue.offer(event)
          null
        }
        
    } catch {
      case e: Exception =>
        logger.error(s"Error preparing event ${event.event.id} for emission", e)
        // Don't propagate - event emission failure should not fail Spark job
    }
  }
  
  /**
   * Process retry queue - attempt to resend failed events.
   */
  private def processRetryQueue(): Unit = {
    try {
      val maxRetries = 10
      var processed = 0
      
      while (processed < maxRetries && !retryQueue.isEmpty) {
        val event = retryQueue.poll()
        if (event != null) {
          logger.debug(s"Retrying event ${event.event.id}")
          emitEventSync(event) match {
            case Success(_) =>
              logger.info(s"Retry successful for event ${event.event.id}")
            case Failure(e) =>
              logger.warn(s"Retry failed for event ${event.event.id}: ${e.getMessage}, re-queuing")
              retryQueue.offer(event)
          }
          processed += 1
        }
      }
      
    } catch {
      case e: Exception =>
        logger.error("Error processing retry queue", e)
    }
  }
  
  /**
   * Synchronous event emission (for retries).
   */
  private def emitEventSync(event: ApplicationEvent): Try[Unit] = Try {
    val json = write(event)
    val eventId = event.event.id
    
    val request = HttpRequest.newBuilder()
      .uri(URI.create(s"$elasticsearchUrl/app-events/_doc/$eventId"))
      .header("Content-Type", "application/json")
      .header("Authorization", s"Basic $credentials")
      .timeout(Duration.ofSeconds(5))
      .POST(HttpRequest.BodyPublishers.ofString(json))
      .build()
    
    val response = httpClient.send(request, HttpResponse.BodyHandlers.ofString())
    
    if (response.statusCode() >= 200 && response.statusCode() < 300) {
      ()
    } else {
      throw new Exception(s"HTTP ${response.statusCode()}: ${response.body()}")
    }
  }
  
  /**
   * Shutdown the emitter, flushing any remaining events.
   */
  def shutdown(): Unit = {
    logger.info("Shutting down EventEmitter...")
    
    // Process remaining retries
    val remaining = retryQueue.size()
    if (remaining > 0) {
      logger.info(s"Processing $remaining remaining events...")
      processRetryQueue()
    }
    
    // Shutdown retry executor
    retryExecutor.shutdown()
    try {
      if (!retryExecutor.awaitTermination(10, TimeUnit.SECONDS)) {
        retryExecutor.shutdownNow()
      }
    } catch {
      case e: InterruptedException =>
        retryExecutor.shutdownNow()
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

