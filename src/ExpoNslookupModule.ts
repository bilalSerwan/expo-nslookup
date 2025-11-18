import { NativeModule, requireNativeModule } from "expo";

export interface DNSLookupResult {
  success: boolean;
  domain: string;
  hasAddresses: boolean;
}

export interface CustomDnsLookupResult {
  isPrivate: boolean;
  domain: string;
  ip: string[];
  server: string;
}

declare class ExpoNslookupModule extends NativeModule {
  advanceLookUp(domain: string, timeout: number): Promise<DNSLookupResult>;

  nsLookUpWithCustomDnsServer(
    domain: string,
    dnsServers: string[],
    timeoutInSeconds: number
  ): Promise<CustomDnsLookupResult>;
}

export default requireNativeModule<ExpoNslookupModule>("ExpoNslookup");
