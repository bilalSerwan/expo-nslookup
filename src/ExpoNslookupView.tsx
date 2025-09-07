import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoNslookupViewProps } from './ExpoNslookup.types';

const NativeView: React.ComponentType<ExpoNslookupViewProps> =
  requireNativeView('ExpoNslookup');

export default function ExpoNslookupView(props: ExpoNslookupViewProps) {
  return <NativeView {...props} />;
}
