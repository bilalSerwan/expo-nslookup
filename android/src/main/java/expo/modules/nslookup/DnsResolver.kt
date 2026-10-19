package expo.modules.nslookup

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketException
import java.net.SocketTimeoutException
import java.security.SecureRandom

/** How one lookup ended. `server` is the canonical IP text of the deciding DNS server. */
internal sealed interface LookupOutcome {
  data class Resolved(val server: String, val ips: List<String>) : LookupOutcome
  data class NotFound(val server: String) : LookupOutcome
  data object TimedOut : LookupOutcome
  data object Offline : LookupOutcome
}

/** How the exchange with one server ended. */
internal sealed interface ServerOutcome {
  data class Answered(val ips: List<String>) : ServerOutcome
  data object Negative : ServerOutcome
  data object TimedOut : ServerOutcome
  data object Unreachable : ServerOutcome
}

/**
 * Queries every server in parallel over UDP and returns the first positive answer.
 * ios/Core/DnsResolver.swift and ios/Core/DnsUdpExchange.swift implement the same behaviour.
 *
 * Per server: one connected socket; the same query is (re)sent at each [sendScheduleMs] offset that falls
 * before the deadline, and a late answer to an earlier send still counts. A negative answer ends that
 * server. Socket errors (including ICMP port unreachable) end it as Unreachable. At the deadline it is
 * Negative if a SERVFAIL/truncated answer was seen, else TimedOut.
 *
 * Overall: the first Answered wins and cancels the rest. When every server is done: any Negative gives
 * NotFound (the first one to arrive), otherwise TimedOut. One negative never stops the others, because
 * another server may still resolve the domain.
 */
internal class DnsResolver(
  private val port: Int = DNS_PORT,
  private val sendScheduleMs: List<Long> = DEFAULT_SEND_SCHEDULE_MS,
  private val nextId: () -> Int = { random.nextInt(0x10000) },
) {
  suspend fun resolve(request: LookupRequest): LookupOutcome = coroutineScope {
    val deadlineNs = System.nanoTime() + request.timeoutMs * NANOS_PER_MS
    val outcomes = Channel<Pair<DnsServer, ServerOutcome>>(request.servers.size)
    request.servers.forEach { server ->
      launch { outcomes.send(server to queryServer(server, request.question, deadlineNs)) }
    }
    try {
      var firstNegative: DnsServer? = null
      repeat(request.servers.size) {
        val (server, outcome) = outcomes.receive()
        when (outcome) {
          is ServerOutcome.Answered -> return@coroutineScope LookupOutcome.Resolved(server.text, outcome.ips)
          ServerOutcome.Negative -> if (firstNegative == null) firstNegative = server
          ServerOutcome.TimedOut, ServerOutcome.Unreachable -> Unit
        }
      }
      firstNegative?.let { LookupOutcome.NotFound(it.text) } ?: LookupOutcome.TimedOut
    } finally {
      coroutineContext.cancelChildren()
    }
  }

  private suspend fun queryServer(server: DnsServer, question: ByteArray, deadlineNs: Long): ServerOutcome =
    withContext(Dispatchers.IO) {
      val socket = try {
        DatagramSocket()
      } catch (e: SocketException) {
        return@withContext ServerOutcome.Unreachable
      }
      // receive() ignores thread interrupts; closing the socket is the supported way to unblock it on cancellation.
      val closer = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
          awaitCancellation()
        } finally {
          socket.close()
        }
      }
      try {
        exchange(socket, server, question, deadlineNs)
      } catch (e: IOException) {
        ensureActive() // an IOException caused by our own close() is really a cancellation
        ServerOutcome.Unreachable
      } finally {
        closer.cancel()
        socket.close()
      }
    }

  /** Blocking send/receive loop for one server. Runs on Dispatchers.IO. */
  private fun CoroutineScope.exchange(
    socket: DatagramSocket,
    server: DnsServer,
    question: ByteArray,
    deadlineNs: Long,
  ): ServerOutcome {
    socket.connect(InetSocketAddress(server.address, port))
    val id = nextId()
    val query = DnsMessage.buildQuery(id, question)
    val startNs = System.nanoTime()
    val sendTimesNs = sendScheduleMs.map { startNs + it * NANOS_PER_MS }.filter { it < deadlineNs }
    val buffer = ByteArray(RECEIVE_BUFFER_SIZE)
    val packet = DatagramPacket(buffer, buffer.size)
    var nextSend = 0
    var sawTransient = false

    while (true) {
      ensureActive()
      val now = System.nanoTime()
      if (now >= deadlineNs) return if (sawTransient) ServerOutcome.Negative else ServerOutcome.TimedOut
      if (nextSend < sendTimesNs.size && now >= sendTimesNs[nextSend]) {
        socket.send(DatagramPacket(query, query.size))
        nextSend++
        continue
      }

      val wakeNs = if (nextSend < sendTimesNs.size) minOf(sendTimesNs[nextSend], deadlineNs) else deadlineNs
      // soTimeout 0 would mean "wait forever", so never go below 1 ms.
      socket.soTimeout = ((wakeNs - now + NANOS_PER_MS - 1) / NANOS_PER_MS).coerceIn(1, Int.MAX_VALUE.toLong()).toInt()
      packet.setLength(buffer.size)
      try {
        socket.receive(packet)
      } catch (e: SocketTimeoutException) {
        continue
      }

      when (val result = DnsMessage.classify(buffer, packet.length, id, question)) {
        DnsMessage.Classification.Ignore -> Unit
        is DnsMessage.Classification.Addresses -> return ServerOutcome.Answered(result.ips)
        DnsMessage.Classification.Negative -> return ServerOutcome.Negative
        DnsMessage.Classification.Transient -> sawTransient = true
      }
    }
  }

  companion object {
    const val DNS_PORT = 53
    val DEFAULT_SEND_SCHEDULE_MS = listOf(0L, 500L, 1_500L, 3_500L)

    private const val NANOS_PER_MS = 1_000_000L
    private const val RECEIVE_BUFFER_SIZE = 4096
    private val random = SecureRandom()
  }
}
