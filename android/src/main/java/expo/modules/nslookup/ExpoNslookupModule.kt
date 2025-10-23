package expo.modules.nslookup

import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.InetAddress
import java.net.UnknownHostException

/**
 * Options for DNS lookup
 */
class DNSLookupOptions : Record {
    @Field
    val timeout: Double? = null // Timeout in seconds
}

/**
 * Expo module for performing DNS lookups with configurable timeout support
 */
class ExpoNslookupModule : Module() {

    override fun definition() = ModuleDefinition {
        Name("ExpoNslookup")

        // MARK: - DNS Lookup Function with Optional Configuration
        AsyncFunction("lookup") { domain: String, options: DNSLookupOptions?, promise: Promise ->
            // Validate input domain
            if (domain.isEmpty()) {
                promise.reject(
                    DNSErrorCode.INVALID_DOMAIN.code,
                    DNSErrorCode.INVALID_DOMAIN.getMessage(),
                    null
                )
                return@AsyncFunction
            }

            // Get timeout from options or use default (1 second)
            val timeoutMs = ((options?.timeout ?: DEFAULT_TIMEOUT_SECONDS) * 1000).toLong()

            // Perform DNS lookup with timeout
            performDNSLookupWithTimeout(domain, timeoutMs, promise)
        }
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

                withContext(Dispatchers.Main) {
                    promise.resolve(
                        mapOf(
                            "success" to true,
                            "domain" to domain,
                            "hasAddresses" to hasAddresses
                        )
                    )
                }
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                withContext(Dispatchers.Main) {
                    promise.reject(
                        DNSErrorCode.TIMEOUT.code,
                        DNSErrorCode.TIMEOUT.getMessage(domain, timeoutMs / 1000.0),
                        e
                    )
                }
            } catch (e: UnknownHostException) {
                withContext(Dispatchers.Main) {
                    promise.reject(
                        DNSErrorCode.NO_ADDRESSES_FOUND.code,
                        DNSErrorCode.NO_ADDRESSES_FOUND.getMessage(domain),
                        e
                    )
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    promise.reject(
                        DNSErrorCode.UNKNOWN.code,
                        e.message ?: DNSErrorCode.UNKNOWN.getMessage(domain),
                        e
                    )
                }
            }
        }
    }

    @Throws(UnknownHostException::class)
    private suspend fun performDNSLookup(domain: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val addresses = InetAddress.getAllByName(domain)
                val hasAddresses = addresses.isNotEmpty()
                hasAddresses
            } catch (e: UnknownHostException) {
                throw e
            } catch (e: Exception) {
                throw UnknownHostException("Failed to resolve domain: ${e.message}")
            }
        }
    }


    companion object {
        private const val DEFAULT_TIMEOUT_SECONDS = 1.0
    }
}

/**
 * Custom error codes for DNS operations
 */
private enum class DNSErrorCode(val code: String) {
    INVALID_DOMAIN("INVALID_DOMAIN"),
    NO_ADDRESSES_FOUND("NO_ADDRESSES_FOUND"),
    TIMEOUT("TIMEOUT"),
    UNKNOWN("UNKNOWN_ERROR");

    fun getMessage(domain: String = "", timeoutSeconds: Double? = null): String {
        return when (this) {
            INVALID_DOMAIN -> "The provided domain name is empty or invalid"
            NO_ADDRESSES_FOUND -> "No addresses found for domain: '$domain'"
            TIMEOUT -> "DNS lookup timed out after ${timeoutSeconds ?: 1.0} second(s) for domain: '$domain'"
            UNKNOWN -> "An unknown error occurred during DNS lookup for domain: '$domain'"
        }
    }
}