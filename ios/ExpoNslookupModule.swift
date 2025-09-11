import ExpoModulesCore

public class ExpoNslookupModule: Module {

  public func definition() -> ModuleDefinition {
    Name("ExpoNslookup")

    Function("hello") {
      return "Hello world! 👋"
    }

      AsyncFunction("lookup") { (domain: String) in
          let host = CFHostCreateWithName(nil, domain as CFString).takeRetainedValue()
          CFHostStartInfoResolution(host, .addresses, nil)
          var success: DarwinBoolean = false
          if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray?,
             addresses.count > 0 {
              return true
          }
          return false
      }
  }
}
