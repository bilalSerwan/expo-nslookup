
import ExpoNslookupModule from './ExpoNslookupModule';
export { default } from './ExpoNslookupModule';

export async function lookup(domain: string): Promise<boolean> {
    return await ExpoNslookupModule.lookup(domain)
}
