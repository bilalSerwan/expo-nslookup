import { NativeModule, requireNativeModule } from 'expo';

import { ExpoNslookupModuleEvents } from './ExpoNslookup.types';

declare class ExpoNslookupModule extends NativeModule<ExpoNslookupModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoNslookupModule>('ExpoNslookup');
