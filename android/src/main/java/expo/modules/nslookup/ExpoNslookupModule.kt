package expo.modules.nslookup

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.net.InetAddress

class ExpoNslookupModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoNslookup")

    Function("hello") {
      "Hello world! 👋"
    }

    AsyncFunction("lookup") { hostname: String ->
      runCatching {
        val addresses = InetAddress.getAllByName(hostname)
        addresses != null && addresses.isNotEmpty()
      }.getOrDefault(false)
    }
  }
}
