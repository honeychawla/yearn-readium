import React, {
  useCallback,
  useState,
  useEffect,
  forwardRef,
  useRef,
  useMemo,
  useImperativeHandle,
} from 'react';
import { View, Platform, findNodeHandle, StyleSheet, UIManager } from 'react-native';

import type {
  BaseReadiumViewProps,
  Dimensions,
  Preferences,
} from '../interfaces';
import { createFragment, getWidthOrHeightValue as dimension } from '../utils';
import { BaseReadiumView } from './BaseReadiumView';

export type ReadiumProps = Omit<BaseReadiumViewProps, 'preferences'> & {
  preferences: Preferences;
};

export const ReadiumView: React.FC<ReadiumProps> = forwardRef(
  (
    {
      onLocationChange: wrappedOnLocationChange,
      onTableOfContents: wrappedOnTableOfContents,
      onDecorationTapped: wrappedOnDecorationTapped,
      onTextSelected: wrappedOnTextSelected,
      decorations,
      preferences,
      ...props
    },
    forwardedRef
  ) => {
    const defaultRef = useRef<any>(null);
    const [{ height, width }, setDimensions] = useState<Dimensions>({
      width: 0,
      height: 0,
    });

    // set the view dimensions on layout
    const onLayout = useCallback(
      ({
        nativeEvent: {
          layout: { width, height },
        },
      }: any) => {
        setDimensions({
          width: dimension(width),
          height: dimension(height),
        });
      },
      []
    );

    // wrap the native onLocationChange and extract the raw event value
    const onLocationChange = useCallback(
      (event: any) => {
        if (wrappedOnLocationChange) {
          wrappedOnLocationChange(event.nativeEvent);
        }
      },
      [wrappedOnLocationChange]
    );

    const onTableOfContents = useCallback(
      (event: any) => {
        if (wrappedOnTableOfContents) {
          const toc = event.nativeEvent.toc || null;
          wrappedOnTableOfContents(toc);
        }
      },
      [wrappedOnTableOfContents]
    );

    const onDecorationTapped = useCallback(
      (event: any) => {
        if (wrappedOnDecorationTapped) {
          wrappedOnDecorationTapped(event.nativeEvent);
        }
      },
      [wrappedOnDecorationTapped]
    );

    const onTextSelected = useCallback(
      (event: any) => {
        if (wrappedOnTextSelected) {
          wrappedOnTextSelected(event.nativeEvent);
        }
      },
      [wrappedOnTextSelected]
    );

    // create the view fragment on android
    useEffect(() => {
      if (Platform.OS === 'android' && defaultRef.current) {
        const viewId = findNodeHandle(defaultRef.current);
        createFragment(viewId);
      }
    }, []);

    // Expose methods to the forwarded ref
    useImperativeHandle(forwardedRef, () => ({
      updateLocation: (locator: any) => {
        console.log('📍 ReadiumView.updateLocation called with:', locator);
        if (defaultRef.current) {
          const viewId = findNodeHandle(defaultRef.current);
          if (viewId) {
            // Call the native updateLocation command
            UIManager.dispatchViewManagerCommand(
              viewId,
              UIManager.getViewManagerConfig('ReadiumView').Commands.updateLocation,
              [locator]
            );
            console.log('✅ Dispatched updateLocation command to native');
            return true;
          }
        }
        console.warn('⚠️ Could not dispatch updateLocation');
        return false;
      },
    }), [defaultRef.current]);

    const stringifiedPreferences = useMemo(
      () => JSON.stringify(preferences),
      [preferences]
    );

    const stringifiedDecorations = useMemo(
      () => decorations ? JSON.stringify(decorations) : undefined,
      [decorations]
    );

    return (
      <View style={styles.container} onLayout={onLayout}>
        <BaseReadiumView
          height={height}
          width={width}
          {...props}
          preferences={stringifiedPreferences}
          decorations={stringifiedDecorations}
          onLocationChange={onLocationChange}
          onTableOfContents={onTableOfContents}
          onDecorationTapped={onDecorationTapped}
          onTextSelected={onTextSelected}
          ref={defaultRef}
        />
      </View>
    );
  }
);

const styles = StyleSheet.create({
  container: { width: '100%', height: '100%' },
});
