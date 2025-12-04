package expo.modules.nslookup

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException

object DNSClient {

    suspend fun resolve(
        domain: String,
        dnsServers: List<String>,
        maxRetries: Int = 2,
        retryTimeoutMs: Int = 500,
        totalTimeoutMs: Int = 3000
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        val startNs = System.nanoTime()
        val resultChannel = Channel<Map<String, Any>>(1)
        val jobs = mutableListOf<Job>()

        // Launch parallel queries for ALL servers
        for (server in dnsServers) {
            val job = launch {
                queryWithRetryAndReport(
                    domain = domain,
                    server = server,
                    maxRetries = maxRetries,
                    retryTimeoutMs = retryTimeoutMs,
                    resultChannel = resultChannel
                )
            }
            jobs.add(job)
        }

        // Wait for first success OR total timeout
        val result = withTimeoutOrNull(totalTimeoutMs.toLong()) {
            resultChannel.receive()
        }

        // Cancel all remaining jobs
        jobs.forEach { it.cancel() }

        val elapsedSeconds = (System.nanoTime() - startNs) / 1_000_000_000.0
        result?.let { it + ("elapsedSeconds" to elapsedSeconds) } ?: throw Exception("All DNS servers failed or timed out")
    }

    private suspend fun queryWithRetryAndReport(
        domain: String,
        server: String,
        maxRetries: Int,
        retryTimeoutMs: Int,
        resultChannel: Channel<Map<String, Any>>
    ) {
        repeat(maxRetries) { attempt ->
            if (!currentCoroutineContext().isActive) return

            try {
                val ips = queryDNS(domain, server, retryTimeoutMs)

                if (ips.isNotEmpty()) {
                    resultChannel.trySend(
                        mapOf(
                            "isPrivate" to true,
                            "domain" to domain,
                            "ip" to ips,
                            "server" to server
                        )
                    )
                    return
                }
            } catch (_: SocketTimeoutException) {
                // Retry
            } catch (_: Exception) {
                return // Abandon
            }
        }
    }


    fun queryDNS(domain: String, dnsServer: String, timeoutMs: Int = 3000): List<String> {
        val socket = DatagramSocket().apply { soTimeout = timeoutMs }

        return try {
            val query = buildQuery(domain)
            val server = InetAddress.getByName(dnsServer)

            socket.send(DatagramPacket(query, query.size, server, 53))

            val buffer = ByteArray(512)
            val response = DatagramPacket(buffer, buffer.size)
            socket.receive(response)

            parseResponse(buffer)
        } finally {
            socket.close()
        }
    }

    private fun buildQuery(domain: String): ByteArray {
        val buffer = ByteArray(512)
        var pos = 0

        // Transaction ID
        val id = (System.currentTimeMillis() and 0xFFFF).toInt()
        buffer[pos++] = (id shr 8).toByte()
        buffer[pos++] = id.toByte()

        // Flags: Standard query, recursion desired
        buffer[pos++] = 0x01
        buffer[pos++] = 0x00

        // Questions: 1
        buffer[pos++] = 0x00
        buffer[pos++] = 0x01

        // Answer/Authority/Additional: 0
        pos += 6

        // Domain name
        for (label in domain.split(".")) {
            buffer[pos++] = label.length.toByte()
            for (c in label) buffer[pos++] = c.code.toByte()
        }
        buffer[pos++] = 0x00

        // Type: A (1)
        buffer[pos++] = 0x00
        buffer[pos++] = 0x01

        // Class: IN (1)
        buffer[pos++] = 0x00
        buffer[pos++] = 0x01

        return buffer.copyOf(pos)
    }

    private fun parseResponse(data: ByteArray): List<String> {
        if (data.size < 12) return emptyList()

        val ips = mutableListOf<String>()
        val answerCount = ((data[6].toInt() and 0xFF) shl 8) or (data[7].toInt() and 0xFF)
        if (answerCount == 0) return emptyList()

        // Skip header + question
        var pos = 12
        while (pos < data.size && data[pos] != 0.toByte()) {
            pos += (data[pos].toInt() and 0xFF) + 1
        }
        pos += 5

        // Parse answers
        repeat(answerCount) {
            if (pos + 12 > data.size) return@repeat

            // Skip name (handle compression)
            pos += if ((data[pos].toInt() and 0xC0) == 0xC0) 2 else {
                var p = pos
                while (p < data.size && data[p] != 0.toByte()) p += (data[p].toInt() and 0xFF) + 1
                p - pos + 1
            }

            if (pos + 10 > data.size) return@repeat

            val type = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos + 1].toInt() and 0xFF)
            pos += 8

            val len = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos + 1].toInt() and 0xFF)
            pos += 2

            // A record
            if (type == 1 && len == 4 && pos + 4 <= data.size) {
                ips.add("${data[pos].toInt() and 0xFF}.${data[pos+1].toInt() and 0xFF}.${data[pos+2].toInt() and 0xFF}.${data[pos+3].toInt() and 0xFF}")
            }
            pos += len
        }
        return ips
    }
}