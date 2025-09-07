import ExpoModulesCore

public class ExpoNslookupModule: Module {

  public func definition() -> ModuleDefinition {
    Name("ExpoNslookup")

    Function("hello") {
      return "Hello world! 👋"
    }

    AsyncFunction("lookup") { (domain: String) in
      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          let result = lookup(domain)
          continuation.resume(returning: result)
        }
      }
    }
  }
}
