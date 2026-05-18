import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  EpicenterNative,
  type IOSNativePlaybackState,
} from "@/native/iosNativeAudio";
import {
  nativeTrackToAppTrack,
  type IOSAppTrack,
} from "@/native/iosTrackMapper";

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

const EQ_FREQUENCIES = [
  20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
  800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500,
  16000, 20000,
];

const formatEqLabel = (frequency: number) => {
  if (frequency < 1000) return `${frequency} Hz`;
  const khz = frequency / 1000;
  return `${Number.isInteger(khz) ? khz.toFixed(0) : khz.toString()} kHz`;
};

const EQ_GAIN_MIN = -8;
const EQ_GAIN_MAX = 8;

const clampEqGain = (gain: number) =>
  Math.max(EQ_GAIN_MIN, Math.min(EQ_GAIN_MAX, gain));

const DEFAULT_EQ_BANDS: EqBand[] = EQ_FREQUENCIES.map((frequency) => ({
  frequency,
  label: formatEqLabel(frequency),
  gain: 0,
}));

const logState = (state: IOSNativePlaybackState) => {
  console.info("[iOS Native Playback] state", state);
};

export function useIosNativeAudioProcessor() {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [currentTrackId, setCurrentTrackId] = useState<string | null>(null);
  const [currentTrack, setCurrentTrack] = useState<IOSAppTrack | null>(null);
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
  const lastAppliedTrackIdRef = useRef<string | null>(null);
  const currentTrackIdRef = useRef<string | null>(null);
  const nativeTransitionRequestRef = useRef(0);
  const nativeTransitionContextRef = useRef<{
    requestId: number;
    reason: string;
    fromTrackId: string | null;
    expectedTrackId: string | null;
  } | null>(null);
  const nativeTransitionTimeoutRef = useRef<ReturnType<
    typeof setTimeout
  > | null>(null);

  const clearNativeTransition = useCallback(() => {
    if (nativeTransitionTimeoutRef.current) {
      clearTimeout(nativeTransitionTimeoutRef.current);
      nativeTransitionTimeoutRef.current = null;
    }
  }, []);

  const finishNativeTransition = useCallback(
    (trackId: string | null) => {
      if (!nativeTransitionRequestRef.current) return;
      console.info("[iOS Native Playback] transition confirmed", {
        requestId: nativeTransitionRequestRef.current,
        currentTrackId: trackId,
      });
      nativeTransitionRequestRef.current = 0;
      nativeTransitionContextRef.current = null;
      clearNativeTransition();
    },
    [clearNativeTransition],
  );

  const shouldConfirmNativeTransition = useCallback(
    (trackId: string | null) => {
      const context = nativeTransitionContextRef.current;
      if (!context || !trackId) return false;
      if (context.expectedTrackId) return trackId === context.expectedTrackId;
      return trackId !== context.fromTrackId;
    },
    [],
  );

  const beginNativeTransition = useCallback(
    (reason: string, expectedTrackId: string | null = null) => {
      const fromTrackId = currentTrackIdRef.current;
      const requestId = nativeTransitionRequestRef.current + 1;
      nativeTransitionRequestRef.current = requestId;
      nativeTransitionContextRef.current = {
        requestId,
        reason,
        fromTrackId,
        expectedTrackId,
      };
      clearNativeTransition();
      nativeTransitionTimeoutRef.current = setTimeout(() => {
        if (nativeTransitionRequestRef.current === requestId) {
          console.info("[iOS Native Playback] transition settled by timeout", {
            reason,
            requestId,
          });
          nativeTransitionRequestRef.current = 0;
          nativeTransitionContextRef.current = null;
        }
      }, 1500);
      console.info("[iOS Native Playback] transition requested", {
        reason,
        requestId,
        fromTrackId,
        expectedTrackId,
      });
      return requestId;
    },
    [clearNativeTransition],
  );

  const applyState = useCallback(
    (state: IOSNativePlaybackState | null | undefined) => {
      if (!state || typeof state !== "object") {
        console.warn("[iOS Native Playback] ignored invalid state", state);
        return;
      }
      logState(state);
      setIsPlaying(!!state.isPlaying);
      setCurrentTime(state.currentTime || 0);
      setDuration(
        state.duration || (state.durationMs ? state.durationMs / 1000 : 0),
      );
      const nextTrackId =
        state.currentTrackId ?? state.currentTrack?.id ?? null;
      currentTrackIdRef.current = nextTrackId;
      setCurrentTrackId(nextTrackId);
      if (state.currentTrack?.id) {
        if (
          lastAppliedTrackIdRef.current === state.currentTrack.id &&
          currentTrackIdRef.current === state.currentTrack.id
        ) {
          console.info("[Bridge] event ignored duplicate currentTrack", {
            trackId: state.currentTrack.id,
          });
        } else {
          lastAppliedTrackIdRef.current = state.currentTrack.id;
          setCurrentTrack(nativeTrackToAppTrack(state.currentTrack));
        }
      } else {
        lastAppliedTrackIdRef.current = null;
        setCurrentTrack(null);
      }
      if (shouldConfirmNativeTransition(nextTrackId)) {
        finishNativeTransition(nextTrackId);
      }
      if (state.epicenter) {
        setEpicenterEnabledState(!!state.epicenter.enabled);
      }
      if (state.eq) {
        setEqEnabledState(!!state.eq.enabled);
        if (
          Array.isArray(state.eq.bands) &&
          state.eq.bands.length === DEFAULT_EQ_BANDS.length
        ) {
          setEqBands((prev) => {
            const nextGains = state.eq?.bands ?? [];
            const unchanged = prev.every(
              (band, index) => band.gain === (nextGains[index] ?? 0),
            );
            return unchanged
              ? prev
              : prev.map((band, index) => ({
                  ...band,
                  gain: nextGains[index] ?? 0,
                }));
          });
        }
      }
      if (state.fx) {
        setSpatialEffects((prev) => {
          const next = {
            reverbEnabled: !!state.fx?.reverbEnabled,
            reverbAmount: state.fx?.reverbAmount ?? 0,
            concertHallEnabled: !!state.fx?.concertHallEnabled,
            concertHallAmount: state.fx?.concertHallAmount ?? 0,
          };
          return prev.reverbEnabled === next.reverbEnabled &&
            prev.reverbAmount === next.reverbAmount &&
            prev.concertHallEnabled === next.concertHallEnabled &&
            prev.concertHallAmount === next.concertHallAmount
            ? prev
            : next;
        });
      }
    },
    [finishNativeTransition, shouldConfirmNativeTransition],
  );

  const reportError = useCallback((error: unknown) => {
    console.error("[iOS Native Playback] error", error);
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
    void EpicenterNative.addListener("playbackStateChanged", applyState).then(
      (handle) => handles.push(handle),
    );
    void EpicenterNative.addListener("currentTrackChanged", (event) => {
      if (!event.track?.id) return;
      console.info(`[Web] currentTrackChanged received requestId=${event.requestId ?? "none"} trackId=${event.track.id}`);
      if (lastAppliedTrackIdRef.current === event.track.id) {
        console.info("[Bridge] event ignored duplicate currentTrackChanged", {
          trackId: event.track.id,
        });
        return;
      }
      lastAppliedTrackIdRef.current = event.track.id;
      currentTrackIdRef.current = event.track.id;
      setCurrentTrackId(event.track.id);
      setCurrentTrack(nativeTrackToAppTrack(event.track));
      if (shouldConfirmNativeTransition(event.track.id)) {
        finishNativeTransition(event.track.id);
      }
    }).then((handle) => handles.push(handle));
    void EpicenterNative.addListener("progressChanged", applyState).then(
      (handle) => handles.push(handle),
    );
    void EpicenterNative.addListener("playbackError", (event) =>
      reportError(event),
    ).then((handle) => handles.push(handle));

    return () => {
      for (const handle of handles) void handle.remove();
    };
  }, [
    applyState,
    finishNativeTransition,
    getPlaybackState,
    reportError,
    shouldConfirmNativeTransition,
  ]);

  const playTrackId = useCallback(
    async (trackId: string) => {
      const requestId = beginNativeTransition("playTrackId", trackId);
      console.info("[iOS Native Playback] play trackId", {
        trackId,
        requestId,
      });
      try {
        const state = await EpicenterNative.play({ trackId });
        applyState(state);
        return true;
      } catch (error) {
        reportError(error);
        return false;
      }
    },
    [applyState, beginNativeTransition, reportError],
  );

  const play = useCallback(async () => {
    try {
      const activeTrackId = currentTrackIdRef.current;
      const state = await EpicenterNative.play(
        activeTrackId ? { trackId: activeTrackId } : undefined,
      );
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const pause = useCallback(async () => {
    try {
      const state = await EpicenterNative.pause();
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const seek = useCallback(
    async (seconds: number) => {
      try {
        const state = await EpicenterNative.seek({ seconds });
        applyState(state);
      } catch (error) {
        reportError(error);
      }
    },
    [applyState, reportError],
  );

  const stop = useCallback(async () => {
    try {
      const state = await EpicenterNative.stop();
      applyState(state);
    } catch (error) {
      reportError(error);
    }
  }, [applyState, reportError]);

  const next = useCallback(async (incomingRequestId?: string) => {
    const requestId = incomingRequestId ?? `processor-next-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    console.info(`[Processor] next called requestId=${requestId}`);
    beginNativeTransition("next");
    try {
      const state = await EpicenterNative.next({ requestId });
      applyState(state);
    } catch (error) {
      nativeTransitionRequestRef.current = 0;
      nativeTransitionContextRef.current = null;
      clearNativeTransition();
      reportError(error);
    }
  }, [applyState, beginNativeTransition, clearNativeTransition, reportError]);

  const previous = useCallback(async (incomingRequestId?: string) => {
    const requestId = incomingRequestId ?? `processor-previous-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    console.info(`[Processor] previous called requestId=${requestId}`);
    beginNativeTransition("previous");
    try {
      const state = await EpicenterNative.previous({ requestId });
      applyState(state);
    } catch (error) {
      nativeTransitionRequestRef.current = 0;
      nativeTransitionContextRef.current = null;
      clearNativeTransition();
      reportError(error);
    }
  }, [applyState, beginNativeTransition, clearNativeTransition, reportError]);

  const setEqBandGain = useCallback(
    (index: number, gain: number) => {
      const clampedGain = clampEqGain(gain);
      setEqBands((prev) =>
        prev.map((band, bandIndex) =>
          bandIndex === index ? { ...band, gain: clampedGain } : band,
        ),
      );
      void EpicenterNative.setEqBand({ index, gain: clampedGain }).catch(
        reportError,
      );
    },
    [reportError],
  );

  useEffect(() => {
    if (!eqEnabled) return;
    void EpicenterNative.setEqBands({
      gains: eqBands.map((band) => clampEqGain(band.gain)),
    }).catch(reportError);
  }, [eqBands, eqEnabled, reportError]);

  const setEpicenterEnabled = useCallback(
    (enabled: boolean) => {
      setEpicenterEnabledState(enabled);
      void EpicenterNative.setEpicenterEnabled({ enabled }).catch(reportError);
    },
    [reportError],
  );

  const setDspParam = useCallback(
    (key?: keyof StreamingParams, value?: number) => {
      if (!key || typeof value !== "number") return;
      void EpicenterNative.setEpicenterParams({ [key]: value }).catch(
        reportError,
      );
    },
    [reportError],
  );

  const setEqEnabled = useCallback(
    (enabled: boolean) => {
      setEqEnabledState(enabled);
      void EpicenterNative.setEqEnabled({ enabled }).catch(reportError);
      if (enabled)
        void EpicenterNative.setEqBands({
          gains: eqBands.map((band) => clampEqGain(band.gain)),
        }).catch(reportError);
    },
    [eqBands, reportError],
  );

  const setReverbEnabled = useCallback(
    (enabled: boolean) => {
      setSpatialEffects((prev) => ({ ...prev, reverbEnabled: enabled }));
      void EpicenterNative.setReverbEnabled({ enabled }).catch(reportError);
    },
    [reportError],
  );

  const setReverbAmount = useCallback(
    (amount: number) => {
      setSpatialEffects((prev) => ({ ...prev, reverbAmount: amount }));
      void EpicenterNative.setReverbAmount({ amount }).catch(reportError);
    },
    [reportError],
  );

  const setConcertHallEnabled = useCallback(
    (enabled: boolean) => {
      setSpatialEffects((prev) => ({ ...prev, concertHallEnabled: enabled }));
      void EpicenterNative.setConcertHallEnabled({ enabled }).catch(
        reportError,
      );
    },
    [reportError],
  );

  const setConcertHallAmount = useCallback(
    (amount: number) => {
      setSpatialEffects((prev) => ({ ...prev, concertHallAmount: amount }));
      void EpicenterNative.setConcertHallAmount({ amount }).catch(reportError);
    },
    [reportError],
  );

  const resetEq = useCallback(() => {
    setEqBands(DEFAULT_EQ_BANDS);
    void EpicenterNative.resetEq().catch(reportError);
  }, [reportError]);

  return useMemo(
    () => ({
      currentTime,
      duration,
      isPlaying,
      currentTrackId,
      currentTrack,
      epicenterEnabled,
      eqEnabled,
      eqBands,
      spatialEffects,
      playTrackId,
      play,
      pause,
      seek,
      stop,
      next,
      previous,
      getPlaybackState,
      loadFile: async () => true,
      getActiveSource: () => currentTrackId ?? "",
      resetAfterError: () => {},
      setOnTrackEnded: (handler: (() => void) | null) => {
        onTrackEndedRef.current = handler;
      },
      setOnTrackError: (handler: ((error: unknown) => void) | null) => {
        onTrackErrorRef.current = handler;
      },
      getAnalyserNode: () => null as AnalyserNode | null,
      setCrossfadeConfig: (_config?: unknown) => {},
      setDspParam,
      setEpicenterEnabled,
      setEqEnabled,
      setEqBandGain,
      setEqPreampDb: (_value?: number) => {},
      resetEq,
      setReverbEnabled,
      setReverbAmount,
      setConcertHallEnabled,
      setConcertHallAmount,
    }),
    [
      currentTime,
      duration,
      isPlaying,
      currentTrackId,
      currentTrack,
      epicenterEnabled,
      eqEnabled,
      eqBands,
      spatialEffects,
      playTrackId,
      play,
      pause,
      seek,
      stop,
      next,
      previous,
      getPlaybackState,
      setEpicenterEnabled,
      setDspParam,
      setEqEnabled,
      setEqBandGain,
      resetEq,
      setReverbEnabled,
      setReverbAmount,
      setConcertHallEnabled,
      setConcertHallAmount,
    ],
  );
}
