import ExpoModulesCore
import CoreFoundation

public class ExpoNslookupModule: Module {
    private let resolver = UltraFastDNSResolver()
    
    public func definition() -> ModuleDefinition {
    
        Name("ExpoNslookup")
        
        AsyncFunction("nsLookUpWithCustomDnsServer") { (domain: String, dnsServers: [String], timeoutInSeconds: Int) -> [String: Any] in
            if domain.isEmpty {
                throw NSError(domain: "ExpoNslookup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Domain name cannot be empty."])
            }
            
            if dnsServers.isEmpty {
                throw NSError(domain: "ExpoNslookup", code: -1, userInfo: [NSLocalizedDescriptionKey : "DNS servers cannot be empty."])
            }
            
            if timeoutInSeconds < 1 {
                throw NSError(domain: "ExpoNslookup", code: -1, userInfo: [NSLocalizedDescriptionKey : "Timeout must be greater than 1."])
            }
            
            let config = UltraFastDNSResolver.Config(
                            maxRetries: 2,
                            retryTimeoutMs: 500,
                            totalTimeoutMs: timeoutInSeconds * 1000
                        )
                        
            return try await self.resolver.resolve(
                            domain: domain,
                            dnsServers: dnsServers,
                            config: config
                        )
        
        }
    }
}
