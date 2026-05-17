import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { EpicenterNative, type IOSNativePlaybackState } from '@/native/iosNativeAudio';

export interface StreamingParams {
  sweepFreq: number;
  width: number;
  intensity: number;
  balance: number;
  volume: number;
}

export interface EqBand {
  frequency: number;
  label: string;
  gain: number;
}

export interface SpatialEffectsConfig {
  reverbEnabled: boolean;
  reverbAmount: number;
  concertHallEnabled: boolean;
  concertHallAmount: number;
}

const DEFAULT_EQ_BANDS: EqBand[] = [
  32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
].map((frequency) => ({
  frequency,
  label: frequency >= 1000 ? `${frequency / 1000} kHz` : `${frequency} Hz`,
  gain: 0,
}));

const logState = (state: IOSNativePlaybackState) => {
  console.info('[iOS Native Playback] state', state);
};

export function useIosNativeAudioProcessor() {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [currentTrackId, setCurrentTrackId] = useState<string | null>(null);
  const [epicenterEnabled, setEpicenterEnabledState] = useState(false);
  const [eqEnabled, setEqEnabledState] = useState(false);
  const [eqBands, setEqBands] = useState<EqBand[]>(DEFAULT_EQ_BANDS);
  const [spatialEffects, setSpatialEffects] = useState({
    reverbEnabled: false,
    reverbAmount: 0,
    concertHallEnabled: false,
    concertHallAmount: 0,
  });
  const onTrackEndedRef = useRef<(() => void) | null>(null);
  const onTrackErrorRef = useRef<((error: unknown) => void) | null>(null);

  const applyState = useCallback((state: IOSNativePlaybackState) => {
    logState(state);
    setIsPlaying(!!state.isPlaying);
    setCurrentTime(state.currentTime || 0);
    setDuration(state.duration || (state.durationMs ? state.durationMs / 1000 : 0));
    setCurrentTrackId(state.currentTrackId ?? state.currentTrack?.id ?? null);
    if (state.epicenter) {
      setEpicenterEnabledState(!!state.epicenter.enabled);
    }
  }, []);

  const reportError = useCallback((error: unknown) => {
    console.error('[iOS Native Playback] error', error);
    onTrackErrorRef.current?.(error);
  }, []);

  const getPlaybackState = useCallback(async () => {
    try {
      const state = await EpicenterNative.getPlaybackState();
      applyState(state);
      return state;
    } catch (error) {
      reportError(error);
      throw error;
    }
  }, [applyState, reportError]);

  useEffect(() => {
    void getPlaybackState().catch(() => undefined);

    const handles: Array<{ remove: () => Promise<void> }> = [];
    void EpicenterNative.addListener('playbackStateChanged', applyState).then((handle) => handles.push(handle));
    void EpicenterNative.addListener('progressChanged', applyState).then((handle) => handles.push(handle));
    void EpicenterNative.addListener('playbackError', (event) => reportError(event)).then((handle) => handles.push(handle));

    return () => {
      for (const handle of handles) void handle.remove();
    };
  }, [applyState, getPlaybackState, reportError]);

  const playTrackId = useCallback(async (trackId: string) => {
    console.info('[iOS Native Playback] play trackId', trackId);
    try {
      const state = await EpicenterNative.play({ trackId });
      applyState(state);
      return true;
    } catch (error) {
      reportError(error);
      return false;
    }
  }, [applyState, reportError]);

  const play = useCallback(async () => {
    try {
      const state = await EpicenterNative.play(currentTrackId ? { trackId: currentTrackId } : undefined);
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, currentTrackId, reportError]);

  const pause = useCallback(async () => {
    try {
      const state = await EpicenterNative.pause();
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const seek = useCallback(async (seconds: number) => {
    try {
      const state = await EpicenterNative.seek({ seconds });
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const stop = useCallback(async () => {
    try {
      const state = await EpicenterNative.stop();
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const setEqBandGain = useCallback((index: number, gain: number) => {
    setEqBands((prev) => prev.map((band, bandIndex) => bandIndex === index ? { ...band, gain } : band));
  }, []);

  useEffect(() => {
    if (!eqEnabled) return;
    void EpicenterNative.setEqBands({ gains: eqBands.map((band) => band.gain) }).catch(reportError);
  }, [eqBands, eqEnabled, reportError]);

  const setEpicenterEnabled = useCallback((enabled: boolean) => {
    setEpicenterEnabledState(enabled);
    void EpicenterNative.setEpicenterEnabled({ enabled }).catch(reportError);
  }, [reportError]);

  const setDspParam = useCallback((key?: keyof StreamingParams, value?: number) => {
    if (!key || typeof value !== 'number') return;
    void EpicenterNative.setEpicenterParams({ [key]: value }).catch(reportError);
  }, [reportError]);

  const setEqEnabled = useCallback((enabled: boolean) => {
    setEqEnabledState(enabled);
    if (enabled) void EpicenterNative.setEqBands({ gains: eqBands.map((band) => band.gain) }).catch(reportError);
  }, [eqBands, reportError]);

  const setReverbEnabled = useCallback((enabled: boolean) => {
    setSpatialEffects((prev) => ({ ...prev, reverbEnabled: enabled }));
    void EpicenterNative.setReverbEnabled({ enabled }).catch(reportError);
  }, [reportError]);

  return useMemo(() => ({
    currentTime,
    duration,
    isPlaying,
    currentTrackId,
    epicenterEnabled,
    eqEnabled,
    eqBands,
    spatialEffects,
    playTrackId,
    play,
    pause,
    seek,
    stop,
    getPlaybackState,
    loadFile: async () => true,
    getActiveSource: () => currentTrackId ?? '',
    resetAfterError: () => {},
    setOnTrackEnded: (handler: (() => void) | null) => { onTrackEndedRef.current = handler; },
    setOnTrackError: (handler: ((error: unknown) => void) | null) => { onTrackErrorRef.current = handler; },
    getAnalyserNode: () => null as AnalyserNode | null,
    setCrossfadeConfig: (_config?: unknown) => {},
    setDspParam,
    setEpicenterEnabled,
    setEqEnabled,
    setEqBandGain,
    setEqPreampDb: (_value?: number) => {},
    setReverbEnabled,
    setReverbAmount: (amount: number) => setSpatialEffects((prev) => ({ ...prev, reverbAmount: amount })),
    setConcertHallEnabled: (enabled: boolean) => setSpatialEffects((prev) => ({ ...prev, concertHallEnabled: enabled })),
    setConcertHallAmount: (amount: number) => setSpatialEffects((prev) => ({ ...prev, concertHallAmount: amount })),
  }), [
    currentTime,
    duration,
    isPlaying,
    currentTrackId,
    epicenterEnabled,
    eqEnabled,
    eqBands,
    spatialEffects,
    playTrackId,
    play,
    pause,
    seek,
    stop,
    getPlaybackState,
    setEpicenterEnabled,
    setDspParam,
    setEqEnabled,
    setEqBandGain,
    setReverbEnabled,
  ]);
}
