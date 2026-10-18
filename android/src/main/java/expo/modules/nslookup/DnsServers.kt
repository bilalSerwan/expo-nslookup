package expo.modules.nslookup

import android.content.Context
import android.net.ConnectivityManager

/**
 * Reads the active network's state. Needs ACCESS_NETWORK_STATE, declared in the library manifest.
 */
internal object DnsServers {

  /** The DNS server IPs configured on the active network, in canonical text (see [IpAddressText]). */
  fun read(context: Context): List<String> {
    val cm = connectivityManager(context) ?: return emptyList()
    val network = cm.activeNetwork ?: return emptyList()
    val linkProperties = cm.getLinkProperties(network) ?: return emptyList()
    return linkProperties.dnsServers.map { IpAddressText.format(it.address) }
  }

  /**
   * True when there is no active network at all. A network without validated internet access still counts as
   * online, because the company network (for example a private APN) may have no internet.
   */
  fun isOffline(context: Context): Boolean = connectivityManager(context)?.activeNetwork == null

  private fun connectivityManager(context: Context): ConnectivityManager? =
    context.getSystemService(ConnectivityManager::class.java)
}
