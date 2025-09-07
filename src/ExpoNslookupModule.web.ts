import { registerWebModule, NativeModule } from 'expo';

import { ExpoNslookupModuleEvents } from './ExpoNslookup.types';

class ExpoNslookupModule extends NativeModule<ExpoNslookupModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoNslookupModule, 'ExpoNslookupModule');
