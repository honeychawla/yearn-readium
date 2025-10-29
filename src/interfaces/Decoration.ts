import type { Locator } from './Locator';

/**
 * Decoration to render in the reader (highlights, underlines)
 */
export interface Decoration {
  id: string;
  locator: Locator;
  style: DecorationStyle;
}

/**
 * Style for rendering decorations
 */
export type DecorationStyle = {
  type: 'highlight' | 'underline';
  color?: string; // Hex color (e.g., "#FFFF00")
};

/**
 * Event emitted when a decoration is tapped
 */
export interface DecorationTapEvent {
  decorationId: string;
  locator: Locator;
  style: 'highlight' | 'underline';
}

/**
 * Event emitted when text is selected
 */
export interface TextSelectionEvent {
  selectedText: string;
  locator: Locator;
}
