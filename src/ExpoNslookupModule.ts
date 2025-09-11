import { NativeModule, requireNativeModule } from 'expo';

declare class ExpoNslookupModule extends NativeModule {
  hello(): string;
  lookup(domain: string): Promise<boolean>;
}

export default requireNativeModule<ExpoNslookupModule>('ExpoNslookup');
