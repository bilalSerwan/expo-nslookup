package expo.modules.nslookup

import java.net.InetAddress

/** Error codes shared with iOS and with `NslookupErrorCode` in src/ExpoNslookup.types.ts. */
internal enum class NslookupErrorCode(val value: String) {
  INVALID_DOMAIN("ERR_INVALID_DOMAIN"),
  INVALID_DNS_SERVER("ERR_INVALID_DNS_SERVER"),
  INVALID_TIMEOUT("ERR_INVALID_TIMEOUT"),
}

/** A rejected argument. The module turns it into a coded JS error; it stays Expo-free so it can be unit tested. */
internal class InvalidArgumentException(
  val errorCode: NslookupErrorCode,
  message: String,
) : IllegalArgumentException(message)

/** A DNS server given as an IP literal, with its canonical text. */
internal data class DnsServer(val text: String, val address: InetAddress)

/** Validated arguments for one lookup. */
internal class LookupRequest(
  val domain: String,
  val question: ByteArray,
  val servers: List<DnsServer>,
  val timeoutMs: Long,
) {
  companion object {
    const val MIN_TIMEOUT_MS = 100
    const val MAX_TIMEOUT_MS = 60_000

    const val MAX_SERVERS = 16

    /** Validates in argument order (domain, servers, timeout), the same order as iOS, so both reject with the same code. */
    fun of(domain: String, dnsServers: List<String>, timeoutMs: Double): LookupRequest {
      val name = DnsMessage.normalizeDomain(domain)
        ?: throw InvalidArgumentException(NslookupErrorCode.INVALID_DOMAIN, "Invalid domain name: '$domain'")
      val servers = parseServers(dnsServers)
      if (!timeoutMs.isFinite() || timeoutMs < MIN_TIMEOUT_MS || timeoutMs > MAX_TIMEOUT_MS) {
        throw InvalidArgumentException(
          NslookupErrorCode.INVALID_TIMEOUT,
          "timeoutMs must be between $MIN_TIMEOUT_MS and $MAX_TIMEOUT_MS, got $timeoutMs",
        )
      }
      return LookupRequest(name, DnsMessage.encodeQuestion(name), servers, timeoutMs.toLong())
    }

    /** Validates 1-16 IP literals (never hostnames) and dedupes them by canonical text, keeping input order. */
    fun parseServers(dnsServers: List<String>): List<DnsServer> {
      if (dnsServers.isEmpty() || dnsServers.size > MAX_SERVERS) {
        throw InvalidArgumentException(
          NslookupErrorCode.INVALID_DNS_SERVER,
          "Expected 1 to $MAX_SERVERS DNS servers, got ${dnsServers.size}",
        )
      }
      return dnsServers
        .map { text ->
          val bytes = IpAddressText.parse(text)
            ?: throw InvalidArgumentException(
              NslookupErrorCode.INVALID_DNS_SERVER,
              "DNS server must be an IPv4 or IPv6 address, got '$text'",
            )
          DnsServer(IpAddressText.format(bytes), InetAddress.getByAddress(bytes))
        }
        .distinctBy { it.text }
    }
  }
}
