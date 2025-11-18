package expo.modules.nslookup

import android.os.Build
import android.util.Log
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.net.InetAddress
import java.net.UnknownHostException
import org.xbill.DNS.*
import java.time.Duration


/**
 * Expo module for performing DNS lookups with configurable timeout support
 */
class ExpoNslookupModule : Module() {

    override fun definition() = ModuleDefinition {
        Name("ExpoNslookup")

        // MARK: - DNS Lookup Function with Optional Configuration
        AsyncFunction("advanceLookUp") { domain: String, timeout: Int, promise: Promise ->
            // Validate input domain
            if (domain.isEmpty()) {
                promise.reject(
                    DNSErrorCode.INVALID_DOMAIN.code,
                    DNSErrorCode.INVALID_DOMAIN.getMessage(),
                    null
                )
                return@AsyncFunction
            }

            // Perform DNS lookup with timeout
            performDNSLookupWithTimeout(
                domain = domain,
                timeoutMs = timeout.toLong(),
                promise = promise
            )
        }

        AsyncFunction("nsLookUpWithCustomDnsServer") { domain: String, dnsServers: List<String>, timeoutInSeconds: Int, promise: Promise ->
            resolveDomainWithMultipleServers(
                domain = domain,
                dnsServers = dnsServers,
                timeout = timeoutInSeconds,
                promise = promise,
            )
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun resolveDomainWithMultipleServers(
        domain: String,
        dnsServers: List<String>,
        timeout: Int,
        promise: Promise
    ) = GlobalScope.launch(Dispatchers.IO) {
        val errors: MutableList<String?> = mutableListOf()
        var isPublic: Boolean = false

        Log.d("ExpoNslookupModule", "Starting DNS resolution for domain: $domain")
        for (server in dnsServers) {
            try {
                Log.d("ExpoNslookupModule", "resolving using DNS server: $server")
                val resolver = SimpleResolver(server)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    resolver.timeout = Duration.ofSeconds(timeout.toLong())
                } else {
                    resolver.setTimeout(timeout)
                }

                Log.d("ExpoNslookupModule", "Using resolver with timeout: $timeout seconds")


                val lookup = Lookup(domain, Type.A)
                lookup.setCache(null)
                Log.d("ExpoNslookupModule", "Disabled cache for lookup")
                lookup.setResolver(resolver)
                Log.d("ExpoNslookupModule", "resolver set for lookup")
                val records = lookup.run()
                Log.d("ExpoNslookupModule", "Lookup result: ${lookup.result}, Records: $records")

                if (lookup.result == Lookup.SUCCESSFUL && records != null) {
                    val ips = records.mapNotNull { record ->
                        (record as? ARecord)?.address?.hostAddress
                    }

                    if (ips.isNotEmpty()) {
                        promise.resolve(
                            mapOf(
                                "isPrivate" to true,
                                "domain" to domain,
                                "ip" to ips,
                                "server" to server
                            )
                        )
                        return@launch
                    } else {
                        isPublic = true
                    }
                }
            } catch (e: Exception) {
                Log.d(
                    "ExpoNslookupModule",
                    "Error occurred while resolving with server $server: ${e.message}"
                )
                errors.add("$server -- ${e.message}")
            }
        }

        promise.reject(
            code = if (isPublic) DNSErrorCode.NO_ADDRESSES_FOUND.code else DNSErrorCode.UNKNOWN.code,
            message = errors.mapIndexed { index, string ->
                "e-${index + 1}" to string
            }.toString(),
            null
        )
        return@launch
    }

    // MARK: - Private Helper Methods
    /**
     * Performs DNS lookup for a given domain with timeout
     * @param domain The domain name to resolve
     * @param timeoutMs Timeout in milliseconds
     * @param promise Expo promise to resolve or reject
     */
    @OptIn(DelicateCoroutinesApi::class)
    private fun performDNSLookupWithTimeout(
        domain: String,
        timeoutMs: Long,
        promise: Promise
    ) {
        GlobalScope.launch(Dispatchers.IO) {
            try {
                val hasAddresses = withTimeout(timeoutMs) {
                    performDNSLookup(domain)
                }

                promise.resolve(
                    mapOf(
                        "success" to true,
                        "domain" to domain,
                        "hasAddresses" to hasAddresses
                    )
                )

            } catch (e: Exception) {
                when (e) {

                    is TimeoutCancellationException -> promise.reject(
                        DNSErrorCode.TIMEOUT.code,
                        DNSErrorCode.TIMEOUT.getMessage(domain, timeoutMs / 1000L),
                        e
                    )

                    is UnknownHostException -> promise.reject(
                        DNSErrorCode.NO_ADDRESSES_FOUND.code,
                        DNSErrorCode.NO_ADDRESSES_FOUND.getMessage(domain),
                        e
                    )

                    else -> promise.reject(
                        DNSErrorCode.UNKNOWN.code,
                        e.message ?: DNSErrorCode.UNKNOWN.getMessage(domain),
                        e
                    )
                }
            }
        }
    }

    @Throws(UnknownHostException::class)
    private fun performDNSLookup(domain: String): Boolean =
        InetAddress.getAllByName(domain)?.isNotEmpty() == true

}

/**
 * Custom error codes for DNS operations
 */
private enum class DNSErrorCode(val code: String) {
    INVALID_DOMAIN("INVALID_DOMAIN"),
    NO_ADDRESSES_FOUND("50"),
    TIMEOUT("TIMEOUT"),
    UNKNOWN("100");

    fun getMessage(domain: String = "", timeoutSeconds: Long = 0L): String {
        return when (this) {
            INVALID_DOMAIN -> "The provided domain name is empty or invalid"
            NO_ADDRESSES_FOUND -> "No addresses found for domain: '$domain'"
            TIMEOUT -> "DNS lookup timed out after ${timeoutSeconds / 1000} second(s) for domain: '$domain'"
            UNKNOWN -> "An unknown error occurred during DNS lookup for domain: '$domain'"
        }
    }
}