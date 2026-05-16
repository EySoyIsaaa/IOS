/** iOS-only DSP placeholder. Native DSP/EQ/FX will be implemented in a later phase. */
export interface StreamingEpicenterParams {
  sweepFreq: number;
  width: number;
  intensity: number;
  balance: number;
  volume: number;
}

export function useStreamingEpicenter() {
  return {
    isInitialized: false,
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    loadFile: async () => false,
    play: () => undefined,
    pause: () => undefined,
    seek: () => undefined,
    setParams: () => undefined,
    cleanup: () => undefined,
  };
}
