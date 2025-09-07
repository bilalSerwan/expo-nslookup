// Reexport the native module. On web, it will be resolved to ExpoNslookupModule.web.ts
// and on native platforms to ExpoNslookupModule.ts
export { default } from './ExpoNslookupModule';
export { default as ExpoNslookupView } from './ExpoNslookupView';
export * from  './ExpoNslookup.types';
