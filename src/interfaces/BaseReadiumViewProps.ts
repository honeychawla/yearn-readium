import type { ViewStyle } from 'react-native';
import type { Link } from './Link';
import type { Locator } from './Locator';
import type { File } from './File';
import type { Decoration, DecorationTapEvent, TextSelectionEvent } from './Decoration';

// Native view props (decorations as JSON string)
export type BaseReadiumViewNativeProps = {
  file: File;
  location?: Locator | Link;
  preferences?: string; // JSON between native and JS
  decorations?: string; // JSON string of Decoration[]
  style?: ViewStyle;
  onLocationChange?: (locator: Locator) => void;
  onTableOfContents?: (toc: Link[] | null) => void;
  onDecorationTapped?: (event: DecorationTapEvent) => void;
  onTextSelected?: (event: TextSelectionEvent) => void;
  ref?: any;
  height?: number;
  width?: number;
};

// Public API props (decorations as typed array)
export type BaseReadiumViewProps = Omit<BaseReadiumViewNativeProps, 'decorations'> & {
  decorations?: Decoration[]; // User highlights and annotations
};
