import { NativeModule, requireNativeModule } from 'expo';

declare class ExpoNslookupModule extends NativeModule {
  hello(): string;
  lookup(domain: string): Promise<string>;
}

export default requireNativeModule<ExpoNslookupModule>('ExpoNslookup');
