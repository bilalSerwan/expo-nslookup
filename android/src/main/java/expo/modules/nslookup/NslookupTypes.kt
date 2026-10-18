package expo.modules.nslookup

import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import expo.modules.kotlin.types.Enumerable

/** Mirrors `LookupReason` in src/ExpoNslookup.types.ts. */
enum class LookupReason(val value: String) : Enumerable {
  RESOLVED("resolved"),
  NOT_FOUND("notFound"),
  TIMEOUT("timeout"),
  OFFLINE("offline"),
}

/** Mirrors `CustomDnsLookupResult` in src/ExpoNslookup.types.ts. */
class LookupResult : Record {
  @Field var isPrivate: Boolean = false
  @Field var reason: LookupReason = LookupReason.TIMEOUT
  @Field var domain: String = ""
  @Field var ip: List<String> = emptyList()
  @Field var server: String? = null
  @Field var elapsedMs: Int = 0
}

/** Mirrors `DnsServerComparison` in src/ExpoNslookup.types.ts. */
class DnsServerComparison : Record {
  @Field var deviceServers: List<String> = emptyList()
  @Field var expectedServers: List<String> = emptyList()
  @Field var matchedServers: List<String> = emptyList()
  @Field var isMatch: Boolean = false
}

/** A coded JS error. The code is explicit because inferred codes come from class names, which minification renames. */
internal class NslookupException(code: String, message: String?) : CodedException(code, message, null)

internal fun LookupOutcome.toResult(domain: String, elapsedMs: Int) = LookupResult().also {
  it.domain = domain
  it.elapsedMs = elapsedMs
  when (this) {
    is LookupOutcome.Resolved -> {
      it.isPrivate = true
      it.reason = LookupReason.RESOLVED
      it.ip = ips
      it.server = server
    }
    is LookupOutcome.NotFound -> {
      it.reason = LookupReason.NOT_FOUND
      it.server = server
    }
    LookupOutcome.TimedOut -> it.reason = LookupReason.TIMEOUT
    LookupOutcome.Offline -> it.reason = LookupReason.OFFLINE
  }
}

/** Runs [block], turning an [InvalidArgumentException] into a coded JS error. */
internal inline fun <T> rejectingInvalidArguments(block: () -> T): T =
  try {
    block()
  } catch (e: InvalidArgumentException) {
    throw NslookupException(e.errorCode.value, e.message)
  }
