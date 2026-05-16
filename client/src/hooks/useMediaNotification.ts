import { useCallback, useRef } from 'react';

interface NotificationMetadata {
  title: string;
  artist?: string;
  album?: string;
  artwork?: string;
}

interface NotificationHandlers {
  onPlay?: () => void;
  onPause?: () => void;
  onNext?: () => void;
  onPrevious?: () => void;
  onStop?: () => void;
  onSeek?: (time: number) => void;
}

/**
 * iOS-only safe no-op facade.
 *
 * Now Playing and remote commands are handled by EpicenterNative on iOS, so the
 * frontend must not import external media-session plugin or own media session
 * state through legacy notification plugins.
 */
export function useMediaNotification() {
  const handlersRef = useRef<NotificationHandlers>({});

  const setHandlers = useCallback((handlers: NotificationHandlers) => {
    handlersRef.current = handlers;
  }, []);

  const noop = useCallback(async () => undefined, []);

  return {
    setHandlers,
    updateMetadata: useCallback(async (_metadata: NotificationMetadata) => undefined, []),
    updatePlaybackState: useCallback(async (_isPlaying: boolean) => undefined, []),
    updatePosition: useCallback(async (_currentTime: number, _duration: number) => undefined, []),
    start: noop,
    stop: noop,
    clear: noop,
  };
}

export default useMediaNotification;
