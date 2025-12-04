package expo.modules.nslookup

import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch


/**
 * Expo module for performing DNS lookups with configurable timeout support
 */
class ExpoNslookupModule : Module() {

    override fun definition() = ModuleDefinition {
        Name("ExpoNslookup")

        AsyncFunction("nsLookUpWithCustomDnsServer") { domain: String, dnsServers: List<String>, timeoutInSeconds: Int, promise: Promise ->
            if (domain.isEmpty())
                promise.reject(
                    DNSErrorCode.INVALID_DOMAIN.code,
                    "Domain is empty",
                    null
                )

            if (dnsServers.isEmpty())
                promise.reject(
                    DNSErrorCode.INVALID_DOMAIN.code,
                    "DNS servers list is empty",
                    null
                )


            resolveDomain(
                domain,
                dnsServers,
                timeoutInSeconds,
                promise
            )
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun resolveDomain(
        domain: String,
        dnsServers: List<String>,
        timeout: Int,
        promise: Promise
    ) = GlobalScope.launch(Dispatchers.IO) {
        val errors = mutableListOf<String>()
        try {
            val result = DNSClient.resolve(
                domain,
                dnsServers = dnsServers,
                maxRetries = 3,
                retryTimeoutMs = 500,
                totalTimeoutMs = timeout * 1000
            )
            promise.resolve(result)
            return@launch
        } catch (e: Exception) {
            errors.add(e.message ?: "Unknown")
        }

        promise.reject(
            code = DNSErrorCode.NO_ADDRESSES_FOUND.code,
            message = "No Address Found, Failed to resolve $domain. Errors: ${errors.joinToString(" --|-- ")}",
            null
        )
    }
}

/**
 * Custom error codes for DNS operations
 */
private enum class DNSErrorCode(val code: String) {
    INVALID_DOMAIN("INVALID_DOMAIN"),
    NO_ADDRESSES_FOUND("50")
}