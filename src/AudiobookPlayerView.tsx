import React, { useCallback } from 'react';
import { requireNativeComponent, StyleSheet, ViewStyle, UIManager } from 'react-native';
import type { Locator } from './interfaces';

interface AudiobookPlayerViewProps {
  file: {
    url: string;
    initialLocation?: Locator;
    lcpPassphrase?: string;
  };
  style?: ViewStyle;
  onLocationChange?: (event: { nativeEvent: Locator }) => void;
  onPlaybackStateChange?: (event: { nativeEvent: { isPlaying: boolean } }) => void;
}

const COMPONENT_NAME = 'AudiobookPlayerView';

const LINKING_ERROR =
  `The package 'react-native-readium' doesn't seem to be linked. Make sure: \n\n` +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const NativeAudiobookPlayerView =
  UIManager.getViewManagerConfig(COMPONENT_NAME) != null
    ? requireNativeComponent<AudiobookPlayerViewProps>(COMPONENT_NAME)
    : () => {
        throw new Error(LINKING_ERROR);
      };

export const AudiobookPlayerView: React.FC<AudiobookPlayerViewProps> = ({
  file,
  style,
  onLocationChange,
  onPlaybackStateChange,
}) => {
  const handleLocationChange = useCallback(
    (event: { nativeEvent: Locator }) => {
      onLocationChange?.(event);
    },
    [onLocationChange]
  );

  const handlePlaybackStateChange = useCallback(
    (event: { nativeEvent: { isPlaying: boolean } }) => {
      onPlaybackStateChange?.(event);
    },
    [onPlaybackStateChange]
  );

  return (
    <NativeAudiobookPlayerView
      file={file}
      style={style || styles.container}
      onLocationChange={handleLocationChange}
      onPlaybackStateChange={handlePlaybackStateChange}
    />
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
