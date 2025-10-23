import { NativeModule, requireNativeModule } from 'expo';

export interface DNSLookupResult {
  success: boolean;
  domain: string;
  hasAddresses: boolean;
}

export interface DNSLookupOptions {
  /**
   * Timeout in seconds (default: 1.0)
   */
  timeout?: number;
}

declare class ExpoNslookupModule extends NativeModule {
  lookup(domain: string,  options?: DNSLookupOptions): Promise<DNSLookupResult>;
}

export default requireNativeModule<ExpoNslookupModule>('ExpoNslookup');
