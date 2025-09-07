package expo.modules.nslookup

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.net.URL

class ExpoNslookupModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoNslookup")

    Function("hello") {
      "Hello world! 👋"
    }

    AsyncFunction("lookup") { hostname: String ->
      return runCatching {
        withContext(Dispatchers.IO) {
            InetAddress.getAllByName(hostname).isNotEmpty()
        }
    }.getOrDefault(false)
    }
  }
}
