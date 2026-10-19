package expo.modules.nslookup

import android.content.Context
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.functions.Coroutine
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoNslookupModule : Module() {
  private val resolver = DnsResolver()

  private val context: Context
    get() = appContext.reactContext?.applicationContext ?: throw Exceptions.ReactContextLost()

  override fun definition() = ModuleDefinition {
    Name("ExpoNslookup")

    // Never rejects for a public network; only invalid arguments reject.
    AsyncFunction("nsLookupWithCustomDns") Coroutine { domain: String, dnsServers: List<String>, timeoutMs: Double ->
      val request = rejectingInvalidArguments { LookupRequest.of(domain, dnsServers, timeoutMs) }
      val startNs = System.nanoTime()
      val outcome = if (DnsServers.isOffline(context)) LookupOutcome.Offline else resolver.resolve(request)
      outcome.toResult(request.domain, elapsedMs = ((System.nanoTime() - startNs) / 1_000_000).toInt())
    }

    AsyncFunction("getDnsServers") {
      DnsServers.read(context)
    }

    AsyncFunction("compareDnsServers") { expectedServers: List<String> ->
      val expected = rejectingInvalidArguments { LookupRequest.parseServers(expectedServers) }.map { it.text }
      val device = DnsServers.read(context)
      val matched = device.filter { it in expected }
      DnsServerComparison().apply {
        deviceServers = device
        this.expectedServers = expected
        matchedServers = matched
        isMatch = matched.isNotEmpty()
      }
    }
  }
}
