package expo.modules.nslookup

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger

/** Talks to fake DNS servers on the loopback interfaces (127.0.0.1 and ::1). */
class DnsResolverTest {
  private val servers = mutableListOf<FakeDnsServer>()

  @After
  fun tearDown() = servers.forEach { it.close() }

  @Test
  fun resolvesFromAnsweringServer() = runBlocking {
    val server = fake("127.0.0.1") { query -> listOf(answerA(query, 10, 0, 0, 5)) }
    val outcome = resolve(listOf("127.0.0.1"), port = server.port)
    assertEquals(LookupOutcome.Resolved("127.0.0.1", listOf("10.0.0.5")), outcome)
  }

  @Test
  fun ignoresResponseWithWrongIdThenAcceptsTheRightOne() = runBlocking {
    val server = fake("127.0.0.1") { query ->
      val wrongId = query.copyOf().also { it[0] = (it[0] + 1).toByte() }
      listOf(answerA(wrongId, 10, 0, 0, 1), answerA(query, 10, 0, 0, 2))
    }
    val outcome = resolve(listOf("127.0.0.1"), port = server.port)
    assertEquals(LookupOutcome.Resolved("127.0.0.1", listOf("10.0.0.2")), outcome)
  }

  @Test
  fun resendsWhenTheFirstQueryIsDropped() = runBlocking {
    val seen = AtomicInteger()
    val server = fake("127.0.0.1") { query ->
      if (seen.incrementAndGet() == 1) emptyList() else listOf(answerA(query, 10, 0, 0, 3))
    }
    val start = System.nanoTime()
    val outcome = resolve(listOf("127.0.0.1"), port = server.port, schedule = listOf(0L, 150L), timeoutMs = 2_000)
    assertEquals(LookupOutcome.Resolved("127.0.0.1", listOf("10.0.0.3")), outcome)
    assertTrue("should wait for the resend", elapsedMs(start) >= 140)
    assertEquals(2, seen.get())
  }

  @Test
  fun returnsNotFoundQuicklyOnNxdomain() = runBlocking {
    val server = fake("127.0.0.1") { query -> listOf(response(query, rcode = 3)) }
    val start = System.nanoTime()
    val outcome = resolve(listOf("127.0.0.1"), port = server.port, timeoutMs = 3_000)
    assertEquals(LookupOutcome.NotFound("127.0.0.1"), outcome)
    assertTrue("NXDOMAIN must not wait for the deadline", elapsedMs(start) < 1_000)
  }

  @Test
  fun timesOutWhenNoServerAnswers() = runBlocking {
    val server = fake("127.0.0.1") { emptyList() }
    val start = System.nanoTime()
    val outcome = resolve(listOf("127.0.0.1"), port = server.port, timeoutMs = 300)
    assertEquals(LookupOutcome.TimedOut, outcome)
    assertTrue(elapsedMs(start) in 280..1_000)
  }

  @Test
  fun servfailOnlyBecomesNotFoundAtTheDeadline() = runBlocking {
    val server = fake("127.0.0.1") { query -> listOf(response(query, rcode = 2)) }
    val start = System.nanoTime()
    val outcome = resolve(listOf("127.0.0.1"), port = server.port, timeoutMs = 300)
    assertEquals(LookupOutcome.NotFound("127.0.0.1"), outcome)
    assertTrue(elapsedMs(start) >= 280)
  }

  @Test
  fun fastServerWinsWithoutWaitingForASilentOne() = runBlocking {
    val fast = fake("127.0.0.1") { query -> listOf(answerA(query, 10, 0, 0, 4)) }
    fake("::1", port = fast.port) { emptyList() }
    val start = System.nanoTime()
    val outcome = resolve(listOf("::1", "127.0.0.1"), port = fast.port, timeoutMs = 3_000)
    assertEquals(LookupOutcome.Resolved("127.0.0.1", listOf("10.0.0.4")), outcome)
    assertTrue("must not wait for the silent server", elapsedMs(start) < 1_000)
  }

  @Test
  fun keepsWaitingForOtherServersAfterANegativeAnswer() = runBlocking {
    val negative = fake("127.0.0.1") { query -> listOf(response(query, rcode = 3)) }
    fake("::1", port = negative.port) { query ->
      Thread.sleep(200)
      listOf(answerA(query, 10, 0, 0, 6))
    }
    val outcome = resolve(listOf("127.0.0.1", "::1"), port = negative.port, timeoutMs = 3_000)
    assertEquals(LookupOutcome.Resolved("::1", listOf("10.0.0.6")), outcome)
  }

  @Test
  fun unreachableServerEndsEarly() = runBlocking {
    // Nothing listens on this port, so the connected socket gets ICMP port unreachable.
    val port = DatagramSocket(0, InetAddress.getByName("127.0.0.1")).use { it.localPort }
    val start = System.nanoTime()
    val outcome = resolve(listOf("127.0.0.1"), port = port, timeoutMs = 3_000)
    assertEquals(LookupOutcome.TimedOut, outcome)
    assertTrue("ICMP unreachable must not wait for the deadline", elapsedMs(start) < 2_000)
  }

  @Test
  fun cancellationStopsBlockedReceives() = runBlocking {
    val server = fake("127.0.0.1") { emptyList() }
    val start = System.nanoTime()
    val lookup = async { resolve(listOf("127.0.0.1"), port = server.port, timeoutMs = 10_000) }
    delay(100)
    lookup.cancel()
    lookup.join()
    assertTrue("cancellation must close the socket promptly", elapsedMs(start) < 2_000)
  }

  private suspend fun resolve(
    servers: List<String>,
    port: Int,
    schedule: List<Long> = DnsResolver.DEFAULT_SEND_SCHEDULE_MS,
    timeoutMs: Int = 2_000,
  ): LookupOutcome {
    val request = LookupRequest.of("intranet.example", servers, timeoutMs.toDouble())
    return DnsResolver(port = port, sendScheduleMs = schedule).resolve(request)
  }

  private fun fake(host: String, port: Int = 0, handler: (ByteArray) -> List<ByteArray>): FakeDnsServer =
    FakeDnsServer(InetSocketAddress(InetAddress.getByName(host), port), handler).also { servers += it }

  private fun elapsedMs(startNs: Long) = (System.nanoTime() - startNs) / 1_000_000

  private fun answerA(query: ByteArray, a: Int, b: Int, c: Int, d: Int): ByteArray =
    response(query, answers = 1) + byteArrayOf(0xc0.toByte(), 0x0c, 0, 1, 0, 1, 0, 0, 0x0e, 0x10, 0, 4) +
      byteArrayOf(a.toByte(), b.toByte(), c.toByte(), d.toByte())

  /** Echoes the query's ID and question with the given RCODE and ANCOUNT. */
  private fun response(query: ByteArray, rcode: Int = 0, answers: Int = 0): ByteArray =
    query.copyOf().also {
      it[2] = 0x81.toByte()
      it[3] = (0x80 or rcode).toByte()
      it[7] = answers.toByte()
    }
}

/** A UDP server on a background thread that answers each query with whatever [handler] returns. */
internal class FakeDnsServer(
  bindAddress: InetSocketAddress,
  private val handler: (ByteArray) -> List<ByteArray>,
) : AutoCloseable {
  private val socket = DatagramSocket(bindAddress)
  val port: Int get() = socket.localPort

  private val thread = Thread {
    val buffer = ByteArray(4096)
    while (!socket.isClosed) {
      val packet = DatagramPacket(buffer, buffer.size)
      try {
        socket.receive(packet)
      } catch (e: Exception) {
        return@Thread
      }
      val query = buffer.copyOf(packet.length)
      for (reply in handler(query)) {
        socket.send(DatagramPacket(reply, reply.size, packet.socketAddress))
      }
    }
  }.apply {
    isDaemon = true
    start()
  }

  override fun close() {
    socket.close()
    thread.join(1_000)
  }
}
