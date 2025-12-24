import React, { useCallback } from 'react';
import { requireNativeComponent, StyleSheet, ViewStyle, UIManager } from 'react-native';
import type { Locator } from './interfaces';

interface AudiobookPlayerViewProps {
  file: {
    url: string;
    initialLocation?: Locator;
    lcpPassphrase?: string;
    licensePath?: string;
  };
  style?: ViewStyle;
  onLocationChange?: (event: { nativeEvent: Locator }) => void;
  onPlaybackStateChange?: (event: { nativeEvent: { isPlaying: boolean } }) => void;
}

const COMPONENT_NAME = 'AudiobookPlayerView';

const NativeAudiobookPlayerView = requireNativeComponent<AudiobookPlayerViewProps>(COMPONENT_NAME);

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
