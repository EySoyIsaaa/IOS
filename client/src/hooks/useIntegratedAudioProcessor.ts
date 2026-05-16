/**
 * Glassmorphism Nocturno Design
 * Hook integrado que combina Epicenter DSP + Ecualizador de 31 bandas
 * Arquitectura: AudioElement → Epicenter Worklet → Equalizer Filters → Destination
 *
 * v1.1.1 - Agregado soporte para:
 * - Callback onTrackEnded para continuar reproducción automática
 * - Crossfade entre canciones
 */

import { useEffect, useRef, useState, useCallback } from "react";

export interface StreamingParams {
  sweepFreq: number;
  width: number;
  intensity: number;
  balance: number;
  volume: number;
}

const clampStreamingParam = (
  name: keyof StreamingParams,
  value: number,
): number => {
  switch (name) {
    case "sweepFreq":
      return Math.max(27, Math.min(63, value));
    case "width":
    case "intensity":
    case "balance":
    case "volume":
      return Math.max(0, Math.min(100, value));
    default:
      return value;
  }
};

const clampStreamingParams = (params: StreamingParams): StreamingParams => ({
  sweepFreq: clampStreamingParam("sweepFreq", params.sweepFreq),
  width: clampStreamingParam("width", params.width),
  intensity: clampStreamingParam("intensity", params.intensity),
  balance: clampStreamingParam("balance", params.balance),
  volume: clampStreamingParam("volume", params.volume),
});

export interface EqualizerBand {
  frequency: number;
  gain: number;
  label: string;
}

export interface AudioAnalysisResult {
  bandGains: number[];
  suggestedDsp: Partial<StreamingParams>;
}

export interface CrossfadeConfig {
  enabled: boolean;
  duration: number; // segundos
}

export interface SpatialEffectsConfig {
  reverbEnabled: boolean;
  reverbAmount: number;
  concertHallEnabled: boolean;
  concertHallAmount: number;
}

const clampEffectAmount = (value: number): number =>
  Math.max(0, Math.min(100, value));

type SchroederCombFilter = {
  delay: DelayNode;
  feedback: GainNode;
  damping: BiquadFilterNode;
  tapGain: GainNode;
};

type SchroederAllPassFilter = {
  input: GainNode;
  output: GainNode;
  feedSum: GainNode;
  delay: DelayNode;
  inputToFeedSum: GainNode;
  feedback: GainNode;
  feedForward: GainNode;
};

type SchroederReverbGraph = {
  input: GainNode;
  inputGate: GainNode;
  preDelay: DelayNode;
  combs: SchroederCombFilter[];
  combSum: GainNode;
  allPasses: SchroederAllPassFilter[];
  tone: BiquadFilterNode;
  bassShelf?: BiquadFilterNode;
  wetLimiter: WaveShaperNode;
  output: GainNode;
};

type SchroederReverbPreset = {
  preDelayMs: number;
  combDelaysMs: number[];
  allPassDelaysMs: number[];
  feedback: number;
  dampingFrequency: number;
  toneFrequency: number;
  allPassFeedback: number;
  bassShelfGainDb?: number;
};

const clamp = (value: number, min: number, max: number): number =>
  Math.max(min, Math.min(max, value));

const createSoftClipCurve = (samples = 2048): Float32Array<ArrayBuffer> => {
  const curve = new Float32Array(
    new ArrayBuffer(samples * Float32Array.BYTES_PER_ELEMENT),
  );
  for (let i = 0; i < samples; i += 1) {
    const x = (i / (samples - 1)) * 4 - 2;
    curve[i] = Math.tanh(x);
  }
  return curve;
};

const createAllPassFilter = (
  ctx: AudioContext,
  delayMs: number,
  feedbackAmount: number,
): SchroederAllPassFilter => {
  const input = ctx.createGain();
  const output = ctx.createGain();
  const feedSum = ctx.createGain();
  const delay = ctx.createDelay(0.05);
  const inputToFeedSum = ctx.createGain();
  const feedback = ctx.createGain();
  const feedForward = ctx.createGain();

  const g = clamp(feedbackAmount, 0.3, 0.55);
  delay.delayTime.value = delayMs / 1000;
  feedback.gain.value = g;
  feedForward.gain.value = -g;
  inputToFeedSum.gain.value = 1 - g * g;

  input.connect(feedForward);
  feedForward.connect(output);
  input.connect(inputToFeedSum);
  inputToFeedSum.connect(feedSum);
  feedSum.connect(delay);
  delay.connect(output);
  delay.connect(feedback);
  feedback.connect(feedSum);

  return {
    input,
    output,
    feedSum,
    delay,
    inputToFeedSum,
    feedback,
    feedForward,
  };
};

const createSchroederReverbGraph = (
  ctx: AudioContext,
  preset: SchroederReverbPreset,
): SchroederReverbGraph => {
  const input = ctx.createGain();
  const inputGate = ctx.createGain();
  const preDelay = ctx.createDelay(0.12);
  const combSum = ctx.createGain();
  const output = ctx.createGain();

  preDelay.delayTime.value = preset.preDelayMs / 1000;
  inputGate.gain.value = 1;
  input.connect(inputGate);
  inputGate.connect(preDelay);

  const combs = preset.combDelaysMs.map((delayMs) => {
    const delay = ctx.createDelay(0.12);
    const feedback = ctx.createGain();
    const damping = ctx.createBiquadFilter();
    const tapGain = ctx.createGain();

    delay.delayTime.value = delayMs / 1000;
    feedback.gain.value = clamp(preset.feedback, 0, 0.75);
    damping.type = "lowpass";
    damping.frequency.value = preset.dampingFrequency;
    damping.Q.value = 0.707;
    tapGain.gain.value = 1 / preset.combDelaysMs.length;

    preDelay.connect(delay);
    delay.connect(damping);
    damping.connect(feedback);
    feedback.connect(delay);
    delay.connect(tapGain);
    tapGain.connect(combSum);

    return { delay, feedback, damping, tapGain };
  });

  const allPasses = preset.allPassDelaysMs.map((delayMs) =>
    createAllPassFilter(ctx, delayMs, preset.allPassFeedback),
  );

  let diffusionOutput: AudioNode = combSum;
  for (const allPass of allPasses) {
    diffusionOutput.connect(allPass.input);
    diffusionOutput = allPass.output;
  }

  const tone = ctx.createBiquadFilter();
  tone.type = "lowpass";
  tone.frequency.value = preset.toneFrequency;
  tone.Q.value = 0.65;

  diffusionOutput.connect(tone);

  let finalToneNode: AudioNode = tone;
  let bassShelf: BiquadFilterNode | undefined;
  if (preset.bassShelfGainDb !== undefined) {
    bassShelf = ctx.createBiquadFilter();
    bassShelf.type = "lowshelf";
    bassShelf.frequency.value = 180;
    bassShelf.gain.value = preset.bassShelfGainDb;
    tone.connect(bassShelf);
    finalToneNode = bassShelf;
  }

  const wetLimiter = ctx.createWaveShaper();
  wetLimiter.curve = createSoftClipCurve();
  wetLimiter.oversample = "2x";

  finalToneNode.connect(wetLimiter);
  wetLimiter.connect(output);

  return {
    input,
    inputGate,
    preDelay,
    combs,
    combSum,
    allPasses,
    tone,
    bassShelf,
    wetLimiter,
    output,
  };
};

const setSchroederFeedback = (
  graph: SchroederReverbGraph | null,
  feedbackAmount: number,
  ctx: AudioContext,
) => {
  if (!graph) return;

  graph.inputGate.gain.setTargetAtTime(
    feedbackAmount > 0 ? 1 : 0,
    ctx.currentTime,
    0.025,
  );

  for (const comb of graph.combs) {
    comb.feedback.gain.setTargetAtTime(
      clamp(feedbackAmount, 0, 0.75),
      ctx.currentTime,
      0.04,
    );
  }
};

export const EQ_GAIN_MIN = -8;
export const EQ_GAIN_MAX = 8;

const EQ_31_FREQUENCIES = [
  20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
  800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500,
  16000, 20000,
];

const formatEqLabel = (frequency: number) => {
  if (frequency >= 1000) {
    const khz = frequency / 1000;
    return Number.isInteger(khz) ? `${khz} kHz` : `${khz.toFixed(1)} kHz`;
  }
  return `${frequency} Hz`;
};

export const DEFAULT_EQ_BANDS: EqualizerBand[] = EQ_31_FREQUENCIES.map(
  (frequency) => ({
    frequency,
    gain: 0,
    label: formatEqLabel(frequency),
  }),
);

export interface LoadFileRequestGuard {
  requestId?: number;
  isCurrentRequest?: () => boolean;
}

export interface IntegratedAudioController {
  isReady: boolean;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  loadFile: (
    file: File | string,
    dspParams: StreamingParams,
    requestGuard?: LoadFileRequestGuard,
  ) => Promise<boolean>;
  play: () => boolean;
  getActiveSource: () => string;
  pause: () => void;
  seek: (time: number) => void;
  setDspParam: (name: keyof StreamingParams, value: number) => void;
  setEqBandGain: (index: number, gain: number) => void;
  setEqEnabled: (enabled: boolean) => void;
  setEpicenterEnabled: (enabled: boolean) => void;
  setEqPreampDb: (preampDb: number) => void;
  getAnalyserNode: () => AnalyserNode | null;
  getCurrentDspParams: () => StreamingParams;
  setOnTrackEnded: (callback: (() => void) | null) => void;
  setOnTrackError: (callback: ((error: Error) => void) | null) => void;
  setCrossfadeConfig: (config: CrossfadeConfig) => void;
  setReverbEnabled: (enabled: boolean) => void;
  setReverbAmount: (amount: number) => void;
  setConcertHallEnabled: (enabled: boolean) => void;
  setConcertHallAmount: (amount: number) => void;
  resetAfterError: () => void;
  eqBands: EqualizerBand[];
  eqEnabled: boolean;
  epicenterEnabled: boolean;
  spatialEffects: SpatialEffectsConfig;
}

export function useIntegratedAudioProcessor(): IntegratedAudioController {
  const audioElementRef = useRef<HTMLAudioElement | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const workletNodeRef = useRef<AudioWorkletNode | null>(null);
  const sourceNodeRef = useRef<MediaElementAudioSourceNode | null>(null);
  const activeLoadRequestIdRef = useRef<number | undefined>(undefined);
  const analyserNodeRef = useRef<AnalyserNode | null>(null);
  const eqFiltersRef = useRef<BiquadFilterNode[]>([]);
  const eqLowFiltersRef = useRef<BiquadFilterNode[]>([]);
  const eqHighFiltersRef = useRef<BiquadFilterNode[]>([]);
  const eqInputGainRef = useRef<GainNode | null>(null);
  const eqLowSplitRef = useRef<BiquadFilterNode | null>(null);
  const eqHighSplitRef = useRef<BiquadFilterNode | null>(null);
  const eqOutputGainRef = useRef<GainNode | null>(null);
  const effectsInputGainRef = useRef<GainNode | null>(null);
  const effectsDryGainRef = useRef<GainNode | null>(null);
  const reverbGraphRef = useRef<SchroederReverbGraph | null>(null);
  const reverbWetGainRef = useRef<GainNode | null>(null);
  const concertHallGraphRef = useRef<SchroederReverbGraph | null>(null);
  const concertWetGainRef = useRef<GainNode | null>(null);
  const concertSafetyAnalyserRef = useRef<AnalyserNode | null>(null);
  const concertSafetyTimerRef = useRef<number | null>(null);
  const concertSafetyMuteUntilRef = useRef(0);
  const masterGainRef = useRef<GainNode | null>(null);
  const fixedChainConnectedRef = useRef(false);
  const bypassConnectionRef = useRef<boolean>(false);
  const objectUrlRef = useRef<string | null>(null);
  const dspParamsRef = useRef<StreamingParams>({
    sweepFreq: 45,
    width: 50,
    intensity: 100,
    balance: 100,
    volume: 100,
  });

  // Callback para cuando termina una canción
  const onTrackEndedRef = useRef<(() => void) | null>(null);
  const onTrackErrorRef = useRef<((error: Error) => void) | null>(null);

  // Configuración de crossfade
  const crossfadeConfigRef = useRef<CrossfadeConfig>({
    enabled: false,
    duration: 5,
  });
  const crossfadeTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isCrossfadingRef = useRef(false);
  const pendingCrossfadeInRef = useRef(false);

  const [isReady, setIsReady] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [eqBands, setEqBands] = useState<EqualizerBand[]>(DEFAULT_EQ_BANDS);
  const [eqEnabled, setEqEnabledState] = useState(true);
  const [epicenterEnabled, setEpicenterEnabledState] = useState(false);
  const eqEnabledRef = useRef(true);
  const epicenterEnabledRef = useRef(false);
  const [spatialEffects, setSpatialEffects] = useState<SpatialEffectsConfig>({
    reverbEnabled: false,
    reverbAmount: 35,
    concertHallEnabled: false,
    concertHallAmount: 45,
  });
  const spatialEffectsRef = useRef<SpatialEffectsConfig>({
    reverbEnabled: false,
    reverbAmount: 35,
    concertHallEnabled: false,
    concertHallAmount: 45,
  });
  const eqBandsRef = useRef<EqualizerBand[]>(DEFAULT_EQ_BANDS);
  const eqUserPreampDbRef = useRef(0);

  useEffect(() => {
    eqBandsRef.current = eqBands;
  }, [eqBands]);

  useEffect(() => {
    spatialEffectsRef.current = spatialEffects;
  }, [spatialEffects]);

  useEffect(() => {
    eqEnabledRef.current = eqEnabled;
  }, [eqEnabled]);

  useEffect(() => {
    epicenterEnabledRef.current = epicenterEnabled;
  }, [epicenterEnabled]);

  useEffect(() => {
    const wetWindow = new Float32Array(256);
    let unsafeSamples = 0;

    concertSafetyTimerRef.current = window.setInterval(() => {
      const ctx = audioContextRef.current;
      const analyser = concertSafetyAnalyserRef.current;
      const shouldMonitorConcert =
        spatialEffectsRef.current.concertHallEnabled ||
        (ctx ? ctx.currentTime < concertSafetyMuteUntilRef.current : false);
      if (!ctx || !analyser || !shouldMonitorConcert) return;

      analyser.getFloatTimeDomainData(wetWindow);
      let peak = 0;
      let nanDetected = false;
      for (let i = 0; i < wetWindow.length; i += 1) {
        const sample = wetWindow[i];
        if (!Number.isFinite(sample)) {
          nanDetected = true;
          break;
        }
        peak = Math.max(peak, Math.abs(sample));
      }

      unsafeSamples = nanDetected || peak > 1.2 ? unsafeSamples + 1 : 0;
      const safetyMute = unsafeSamples >= 3;

      if (safetyMute) {
        concertSafetyMuteUntilRef.current = ctx.currentTime + 1.5;
        setSchroederFeedback(concertHallGraphRef.current, 0, ctx);
        if (concertWetGainRef.current) {
          concertWetGainRef.current.gain.cancelScheduledValues(ctx.currentTime);
          concertWetGainRef.current.gain.setValueAtTime(0, ctx.currentTime);
        }
        unsafeSamples = 0;
      }

      if (spatialEffectsRef.current.concertHallEnabled || safetyMute) {
        console.debug("[ConcertHallDiagnostics]", {
          concertHallWetPeak: peak,
          concertHallFeedback: safetyMute
            ? 0
            : 0.58 +
              (clampEffectAmount(spatialEffectsRef.current.concertHallAmount) /
                100) *
                0.1,
          concertHallDelaySamples: concertHallGraphRef.current
            ? concertHallGraphRef.current.combs.map((comb) =>
                Math.round(comb.delay.delayTime.value * ctx.sampleRate),
              )
            : [],
          concertHallNaNDetected: nanDetected,
          concertHallSafetyMute: safetyMute,
        });
      }
    }, 250);

    return () => {
      if (concertSafetyTimerRef.current !== null) {
        window.clearInterval(concertSafetyTimerRef.current);
        concertSafetyTimerRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    return () => {
      if (crossfadeTimeoutRef.current) {
        clearTimeout(crossfadeTimeoutRef.current);
      }
      if (concertSafetyTimerRef.current !== null) {
        window.clearInterval(concertSafetyTimerRef.current);
        concertSafetyTimerRef.current = null;
      }
      if (objectUrlRef.current) {
        URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = null;
      }
      if (audioElementRef.current) {
        audioElementRef.current.pause();
      }
      if (audioContextRef.current) {
        audioContextRef.current.close();
      }
    };
  }, []);

  const initAudioChain = useCallback(async () => {
    if (!audioContextRef.current) {
      const AudioContextCtor = window.AudioContext ||
        (window as any).webkitAudioContext;
      try {
        audioContextRef.current = new AudioContextCtor({ latencyHint: "playback" });
      } catch (_error) {
        audioContextRef.current = new AudioContextCtor();
      }
    }
    const ctx = audioContextRef.current;

    // Crear master gain para crossfade
    if (!masterGainRef.current) {
      masterGainRef.current = ctx.createGain();
      masterGainRef.current.gain.value = 1.0;
    }

    if (!effectsInputGainRef.current) {
      effectsInputGainRef.current = ctx.createGain();
      effectsDryGainRef.current = ctx.createGain();
      effectsDryGainRef.current.gain.value = 1.0;

      reverbGraphRef.current = createSchroederReverbGraph(ctx, {
        preDelayMs: 14,
        combDelaysMs: [19.37, 23.11, 29.17, 31.13],
        allPassDelaysMs: [5.03, 7.07],
        feedback: 0.62,
        dampingFrequency: 5600,
        toneFrequency: 7200,
        allPassFeedback: 0.5,
      });
      reverbWetGainRef.current = ctx.createGain();
      reverbWetGainRef.current.gain.value = 0;

      concertHallGraphRef.current = createSchroederReverbGraph(ctx, {
        preDelayMs: 35,
        combDelaysMs: [25.31, 26.94, 28.63, 30.47],
        allPassDelaysMs: [5.0, 7.0],
        feedback: 0.58,
        dampingFrequency: 5600,
        toneFrequency: 6200,
        allPassFeedback: 0.42,
      });
      concertWetGainRef.current = ctx.createGain();
      concertWetGainRef.current.gain.value = 0;

      concertSafetyAnalyserRef.current = ctx.createAnalyser();
      concertSafetyAnalyserRef.current.fftSize = 256;
    }

    if (!analyserNodeRef.current) {
      analyserNodeRef.current = ctx.createAnalyser();
      analyserNodeRef.current.fftSize = 4096;
      analyserNodeRef.current.smoothingTimeConstant = 0.65;
    }

    // Inicializar Epicenter Worklet
    if (!workletNodeRef.current) {
      try {
        const workletPath = new URL(
          "/epicenter-worklet.js",
          window.location.origin,
        ).href;
        await ctx.audioWorklet.addModule(workletPath);

        workletNodeRef.current = new AudioWorkletNode(
          ctx,
          "epicenter-processor",
          {
            numberOfInputs: 1,
            numberOfOutputs: 1,
            outputChannelCount: [2],
            parameterData: {
              sweepFreq: 45,
              width: 50,
              intensity: 0, // Comenzar con 0 (desactivado)
              balance: 100,
              volume: 100,
            },
          },
        );
      } catch (error) {
        console.error("Error loading AudioWorklet:", error);
        throw error;
      }
    }

    // Inicializar Ecualizador con split de bandas:
    // - <=100 Hz solo afectan ruta de bajos
    // - >100 Hz solo afectan ruta de medios/agudos
    if (eqFiltersRef.current.length === 0) {
      eqInputGainRef.current = ctx.createGain();
      eqOutputGainRef.current = ctx.createGain();
      eqLowSplitRef.current = ctx.createBiquadFilter();
      eqLowSplitRef.current.type = "lowpass";
      eqLowSplitRef.current.frequency.value = 120;
      eqLowSplitRef.current.Q.value = 0.707;

      eqHighSplitRef.current = ctx.createBiquadFilter();
      eqHighSplitRef.current.type = "highpass";
      eqHighSplitRef.current.frequency.value = 120;
      eqHighSplitRef.current.Q.value = 0.707;

      eqLowFiltersRef.current = [];
      eqHighFiltersRef.current = [];
      eqFiltersRef.current = eqBandsRef.current.map((band, index) => {
        const filter = ctx.createBiquadFilter();
        filter.type =
          index === 0
            ? "lowshelf"
            : index === DEFAULT_EQ_BANDS.length - 1
              ? "highshelf"
              : "peaking";
        filter.frequency.value = band.frequency;
        filter.Q.value = 1.0;
        filter.gain.value = band.gain;
        if (band.frequency <= 100) {
          eqLowFiltersRef.current.push(filter);
        } else {
          eqHighFiltersRef.current.push(filter);
        }
        return filter;
      });

      let lowNode: AudioNode = eqLowSplitRef.current;
      for (const filter of eqLowFiltersRef.current) {
        lowNode.connect(filter);
        lowNode = filter;
      }

      let highNode: AudioNode = eqHighSplitRef.current;
      for (const filter of eqHighFiltersRef.current) {
        highNode.connect(filter);
        highNode = filter;
      }

      eqInputGainRef.current.connect(eqLowSplitRef.current);
      eqInputGainRef.current.connect(eqHighSplitRef.current);
      lowNode.connect(eqOutputGainRef.current);
      highNode.connect(eqOutputGainRef.current);
    }

    // Conectar la parte fija de la cadena (ya no conectamos el source aquí)
    // Cadena base: Worklet → Equalizer → Spatial FX dry/wet → MasterGain → Destination
    if (
      !fixedChainConnectedRef.current &&
      workletNodeRef.current &&
      eqInputGainRef.current &&
      eqOutputGainRef.current &&
      effectsInputGainRef.current &&
      effectsDryGainRef.current &&
      reverbGraphRef.current &&
      reverbWetGainRef.current &&
      concertHallGraphRef.current &&
      concertWetGainRef.current &&
      masterGainRef.current
    ) {
      workletNodeRef.current.connect(eqInputGainRef.current);
      eqOutputGainRef.current.connect(effectsInputGainRef.current);
      effectsInputGainRef.current.connect(effectsDryGainRef.current);
      effectsDryGainRef.current.connect(masterGainRef.current);
      effectsInputGainRef.current.connect(reverbGraphRef.current.input);
      reverbGraphRef.current.output.connect(reverbWetGainRef.current);
      reverbWetGainRef.current.connect(masterGainRef.current);
      effectsInputGainRef.current.connect(concertHallGraphRef.current.input);
      concertHallGraphRef.current.output.connect(concertWetGainRef.current);
      if (concertSafetyAnalyserRef.current) {
        concertHallGraphRef.current.output.connect(
          concertSafetyAnalyserRef.current,
        );
      }
      concertWetGainRef.current.connect(masterGainRef.current);
      masterGainRef.current.connect(ctx.destination);
      fixedChainConnectedRef.current = true;
    }
  }, []);

  const applySpatialEffects = useCallback((config: SpatialEffectsConfig) => {
    const ctx = audioContextRef.current;
    if (
      !ctx ||
      !effectsDryGainRef.current ||
      !reverbWetGainRef.current ||
      !concertWetGainRef.current
    )
      return;

    const reverbAmount = clampEffectAmount(config.reverbAmount) / 100;
    const concertAmount = clampEffectAmount(config.concertHallAmount) / 100;
    const reverbWet = config.reverbEnabled ? reverbAmount * 0.34 : 0;
    const safetyMuted = ctx.currentTime < concertSafetyMuteUntilRef.current;
    const concertWet =
      config.concertHallEnabled && !safetyMuted ? concertAmount * 0.28 : 0;
    const dry = Math.max(0.86, 1 - reverbWet * 0.18 - concertWet * 0.24);
    const rampTime = ctx.currentTime + 0.06;

    setSchroederFeedback(
      reverbGraphRef.current,
      0.58 + reverbAmount * 0.16,
      ctx,
    );
    setSchroederFeedback(
      concertHallGraphRef.current,
      config.concertHallEnabled && !safetyMuted
        ? 0.58 + concertAmount * 0.1
        : 0,
      ctx,
    );

    effectsDryGainRef.current.gain.cancelScheduledValues(ctx.currentTime);
    reverbWetGainRef.current.gain.cancelScheduledValues(ctx.currentTime);
    concertWetGainRef.current.gain.cancelScheduledValues(ctx.currentTime);
    effectsDryGainRef.current.gain.linearRampToValueAtTime(dry, rampTime);
    reverbWetGainRef.current.gain.linearRampToValueAtTime(reverbWet, rampTime);
    concertWetGainRef.current.gain.linearRampToValueAtTime(
      concertWet,
      rampTime,
    );

    console.debug("[ConcertHallDiagnostics]", {
      concertHallWetPeak: null,
      concertHallFeedback:
        config.concertHallEnabled && !safetyMuted
          ? 0.58 + concertAmount * 0.1
          : 0,
      concertHallDelaySamples: concertHallGraphRef.current
        ? concertHallGraphRef.current.combs.map((comb) =>
            Math.round(comb.delay.delayTime.value * ctx.sampleRate),
          )
        : [],
      concertHallNaNDetected: false,
      concertHallSafetyMute: safetyMuted,
    });
  }, []);

  // Función para reconectar la cadena según el estado de los efectos
  const updateAudioRouting = useCallback(() => {
    if (!sourceNodeRef.current || !audioContextRef.current) return;

    const source = sourceNodeRef.current;

    // Desconectar todo primero
    try {
      source.disconnect();
    } catch (e) {
      // Ya estaba desconectado
    }

    const currentEffects = spatialEffectsRef.current;
    applySpatialEffects(currentEffects);

    // Determinar si necesitamos bypass completo. EQ encendido pero plano (0 dB)
    // no debe forzar la cadena pesada porque en Android puede causar microcortes.
    const eqHasAudibleChanges =
      eqEnabledRef.current &&
      (Math.abs(eqUserPreampDbRef.current) > 0.01 ||
        eqBandsRef.current.some((band) => Math.abs(band.gain) > 0.01));
    const needsBypass =
      !epicenterEnabledRef.current &&
      !eqHasAudibleChanges &&
      !currentEffects.reverbEnabled &&
      !currentEffects.concertHallEnabled;

    if (needsBypass && masterGainRef.current) {
      // BYPASS COMPLETO: Source → MasterGain → Destination
      // Audio 100% puro sin procesamiento
      source.connect(masterGainRef.current);
      if (analyserNodeRef.current) source.connect(analyserNodeRef.current);
      bypassConnectionRef.current = true;
      console.log(
        "🎵 AUDIO PURO: Bypass completo activado (sin procesamiento)",
      );
    } else if (workletNodeRef.current) {
      // Usar cadena de procesamiento normal
      // Source → Worklet → Equalizer → Spatial FX → MasterGain → Destination
      source.connect(workletNodeRef.current);
      if (analyserNodeRef.current) source.connect(analyserNodeRef.current);
      bypassConnectionRef.current = false;
      console.log("🎛️ AUDIO CON EFECTOS: Cadena de procesamiento activada");
    }
  }, [applySpatialEffects]);

  // Función para iniciar crossfade (fade out)
  const startCrossfadeOut = useCallback(() => {
    if (
      !masterGainRef.current ||
      !audioContextRef.current ||
      isCrossfadingRef.current
    )
      return;

    const ctx = audioContextRef.current;
    const duration = crossfadeConfigRef.current.duration;

    isCrossfadingRef.current = true;

    masterGainRef.current.gain.cancelScheduledValues(ctx.currentTime);
    masterGainRef.current.gain.setValueAtTime(
      masterGainRef.current.gain.value,
      ctx.currentTime,
    );
    masterGainRef.current.gain.linearRampToValueAtTime(
      0.0,
      ctx.currentTime + duration,
    );

    crossfadeTimeoutRef.current = setTimeout(() => {
      crossfadeTimeoutRef.current = null;
      if (onTrackEndedRef.current) {
        onTrackEndedRef.current();
      }
      isCrossfadingRef.current = false;
    }, duration * 1000);
  }, []);

  // Función para fade in al cargar nueva canción
  const startCrossfadeIn = useCallback(() => {
    if (!masterGainRef.current || !audioContextRef.current) return;

    const ctx = audioContextRef.current;
    const duration = crossfadeConfigRef.current.duration;

    masterGainRef.current.gain.cancelScheduledValues(ctx.currentTime);

    if (crossfadeConfigRef.current.enabled) {
      masterGainRef.current.gain.setValueAtTime(0.0, ctx.currentTime);
      masterGainRef.current.gain.linearRampToValueAtTime(
        1.0,
        ctx.currentTime + duration,
      );
    } else {
      masterGainRef.current.gain.setValueAtTime(1.0, ctx.currentTime);
    }
  }, []);

  const waitForAudioReady = useCallback(
    (
      audioElement: HTMLAudioElement,
      timeoutMs: number,
      isCurrentRequest: () => boolean,
      requestId?: number,
      loadStartMs = performance.now(),
    ): Promise<{ ready: boolean; event: string }> =>
      new Promise((resolve) => {
        let settled = false;
        let intervalId: number | null = null;
        const cleanup = () => {
          audioElement.removeEventListener("loadedmetadata", onReady);
          audioElement.removeEventListener("canplay", onReady);
          audioElement.removeEventListener("error", onError);
          if (intervalId !== null) window.clearInterval(intervalId);
          window.clearTimeout(timeoutId);
        };
        const finish = (ready: boolean, event: string) => {
          if (settled) return;
          settled = true;
          cleanup();
          console.info("[LOAD_FILE_READY]", {
            requestId,
            ready,
            event,
            loadDurationMs: performance.now() - loadStartMs,
            activeSrc: audioElement.currentSrc || audioElement.src,
          });
          resolve({ ready, event });
        };
        const onReady = (event: Event) => {
          finish(true, event.type);
        };
        const onError = () => {
          finish(false, "error");
        };
        const timeoutId = window.setTimeout(() => {
          finish(false, "timeout");
        }, timeoutMs);

        audioElement.addEventListener("loadedmetadata", onReady, { once: true });
        audioElement.addEventListener("canplay", onReady, { once: true });
        audioElement.addEventListener("error", onError, { once: true });
        intervalId = window.setInterval(() => {
          if (!isCurrentRequest()) {
            finish(false, "cancelled");
          }
        }, 100);

        if (audioElement.readyState >= HTMLMediaElement.HAVE_METADATA) {
          finish(true, "readyState");
        } else if (!isCurrentRequest()) {
          finish(false, "cancelled");
        }
      }),
    [],
  );

  const loadFile = useCallback(
    async (
      file: File | string,
      params: StreamingParams,
      requestGuard?: LoadFileRequestGuard,
    ): Promise<boolean> => {
      const requestId = requestGuard?.requestId;
      const isCurrentRequest = () => requestGuard?.isCurrentRequest?.() ?? true;
      const cleanupAudioElement = (audioElement?: HTMLAudioElement | null) => {
        if (!audioElement) return;
        try {
          audioElement.pause();
          audioElement.removeAttribute("src");
          audioElement.src = "";
          audioElement.load();
        } catch (error) {
          console.warn("[AudioResolve] Error cleaning audio element", error);
        }
      };
      const cleanupPendingAudio = (
        audioElement?: HTMLAudioElement | null,
        objectUrl?: string | null,
        sourceNode?: MediaElementAudioSourceNode | null,
      ) => {
        if (sourceNode) {
          try {
            sourceNode.disconnect();
          } catch (_error) {
            // no-op: node may already be disconnected
          }
        }
        cleanupAudioElement(audioElement);
        if (objectUrl) {
          URL.revokeObjectURL(objectUrl);
        }
      };
      const cancelIfStale = (
        audioElement?: HTMLAudioElement | null,
        objectUrl?: string | null,
        sourceNode?: MediaElementAudioSourceNode | null,
      ) => {
        if (isCurrentRequest()) {
          return false;
        }
        cleanupPendingAudio(audioElement, objectUrl, sourceNode);
        if (audioElement && audioElementRef.current === audioElement) {
          if (sourceNodeRef.current) {
            try {
              sourceNodeRef.current.disconnect();
            } catch (_error) {
              // no-op
            }
            sourceNodeRef.current = null;
          }
          if (objectUrlRef.current) {
            URL.revokeObjectURL(objectUrlRef.current);
            objectUrlRef.current = null;
          }
          audioElementRef.current = null;
          activeLoadRequestIdRef.current = undefined;
        }
        return true;
      };

      if (cancelIfStale()) return false;

      // Limpiar cualquier crossfade pendiente
      if (crossfadeTimeoutRef.current) {
        clearTimeout(crossfadeTimeoutRef.current);
        crossfadeTimeoutRef.current = null;
      }
      isCrossfadingRef.current = false;

      await initAudioChain();
      if (cancelIfStale()) return false;
      const ctx = audioContextRef.current!;

      const oldAudioElement = audioElementRef.current;
      const oldSourceNode = sourceNodeRef.current;
      const oldSrc = oldAudioElement?.currentSrc || oldAudioElement?.src || "";
      const hadOldAudio = !!oldAudioElement;
      const hadOldSourceNode = !!oldSourceNode;
      const newSourcePreview = typeof file === "string" ? file : file.name;

      console.info("[LOAD_FILE_SWAP]", {
        requestId,
        oldSrc,
        newSource: newSourcePreview,
        hadOldAudio,
        hadOldSourceNode,
      });

      if (cancelIfStale()) return false;

      if (oldSourceNode) {
        try {
          oldSourceNode.disconnect();
        } catch (_error) {
          // no-op: node may already be disconnected
        }
        if (sourceNodeRef.current === oldSourceNode) {
          sourceNodeRef.current = null;
        }
      }

      if (oldAudioElement) {
        cleanupAudioElement(oldAudioElement);
        if (audioElementRef.current === oldAudioElement) {
          audioElementRef.current = null;
        }
      }

      if (objectUrlRef.current) {
        URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = null;
      }
      activeLoadRequestIdRef.current = undefined;

      if (cancelIfStale()) return false;

      const audioElement = new Audio();
      const loadStartMs = performance.now();
      let pendingObjectUrl: string | null = null;
      let newSource = newSourcePreview;

      // Configuración para reproducción en background
      audioElement.crossOrigin = "anonymous";
      audioElement.preload = "auto";

      // Importante para que siga reproduciendo en background en móviles
      (audioElement as any).mozAudioChannelType = "content";

      if (cancelIfStale(audioElement, pendingObjectUrl)) return false;

      if (typeof file === "string") {
        newSource = file;
      } else {
        pendingObjectUrl = URL.createObjectURL(file);
        newSource = pendingObjectUrl;
      }

      setIsReady(false);
      setCurrentTime(0);
      setDuration(0);

      if (cancelIfStale(audioElement, pendingObjectUrl)) return false;
      audioElement.src = newSource;
      if (cancelIfStale(audioElement, pendingObjectUrl)) return false;
      try {
        audioElement.load();
      } catch (error) {
        console.warn("[AudioResolve] audioElement.load failed", error);
        cleanupPendingAudio(audioElement, pendingObjectUrl);
        return false;
      }
      const readyResult = await waitForAudioReady(
        audioElement,
        12000,
        isCurrentRequest,
        requestId,
        loadStartMs,
      );
      if (!readyResult.ready || cancelIfStale(audioElement, pendingObjectUrl)) {
        cleanupPendingAudio(audioElement, pendingObjectUrl);
        return false;
      }

      let sourceNode: MediaElementAudioSourceNode | null = null;
      try {
        sourceNode = ctx.createMediaElementSource(audioElement);
      } catch (error) {
        cleanupPendingAudio(audioElement, pendingObjectUrl, sourceNode);
        console.error("Error creating MediaElementAudioSourceNode:", error);
        throw error;
      }

      if (cancelIfStale(audioElement, pendingObjectUrl, sourceNode)) return false;

      sourceNodeRef.current = sourceNode;
      audioElementRef.current = audioElement;
      activeLoadRequestIdRef.current = requestId;
      if (pendingObjectUrl) {
        objectUrlRef.current = pendingObjectUrl;
        pendingObjectUrl = null;
      }

      console.info("[LOAD_FILE_ACTIVE]", {
        requestId,
        activeSrc: audioElement.currentSrc || audioElement.src,
        sourceNodeSet: !!sourceNodeRef.current,
      });
      console.log("[AudioResolve]", {
        requestId,
        previousAudioUrl: oldSrc,
        newAudioUrl: audioElement.src,
        audioElementSrc: audioElement.src,
      });
      setDuration(audioElement.duration || 0);
      setIsReady(true);
      pendingCrossfadeInRef.current = crossfadeConfigRef.current.enabled;
      if (
        !crossfadeConfigRef.current.enabled &&
        masterGainRef.current &&
        audioContextRef.current
      ) {
        masterGainRef.current.gain.setValueAtTime(
          1.0,
          audioContextRef.current.currentTime,
        );
      }

      // La conexión se hará dinámicamente según el estado de los efectos
      try {
        updateAudioRouting();
      } catch (error) {
        console.error("[PLAYBACK_ERROR] updateAudioRouting failed", {
          requestId,
          error,
          activeSrc: audioElement.currentSrc || audioElement.src,
          requestedTrackId: requestId,
        });
        cleanupPendingAudio(audioElement, pendingObjectUrl, sourceNode);
        if (sourceNodeRef.current === sourceNode) sourceNodeRef.current = null;
        if (audioElementRef.current === audioElement) audioElementRef.current = null;
        return false;
      }

      if (cancelIfStale(audioElement, pendingObjectUrl, sourceNode)) return false;

      // Guardar parámetros iniciales ya normalizados a los topes reales de UI.
      const clampedParams = clampStreamingParams(params);
      dspParamsRef.current = { ...clampedParams };

      // Establecer intensity a 0 si Epicenter está desactivado.
      const finalParams = {
        ...clampedParams,
        intensity: epicenterEnabled ? clampedParams.intensity : 0,
      };

      const paramEntries = Object.entries(finalParams) as [
        keyof StreamingParams,
        number,
      ][];
      for (const [key, value] of paramEntries) {
        const param = workletNodeRef.current!.parameters.get(key);
        if (param) {
          param.setValueAtTime(value, ctx.currentTime);
        }
      }

      const onLoadedMetadata = () => {
        if (audioElementRef.current !== audioElement || !isCurrentRequest()) return;
        setDuration(audioElement.duration);
        setIsReady(true);
        pendingCrossfadeInRef.current = crossfadeConfigRef.current.enabled;
        if (
          !crossfadeConfigRef.current.enabled &&
          masterGainRef.current &&
          audioContextRef.current
        ) {
          masterGainRef.current.gain.setValueAtTime(
            1.0,
            audioContextRef.current.currentTime,
          );
        }
      };

      const onTimeUpdate = () => {
        if (audioElementRef.current !== audioElement || !isCurrentRequest()) return;
        setCurrentTime(audioElement.currentTime);

        // Verificar si debemos iniciar crossfade
        if (crossfadeConfigRef.current.enabled && !isCrossfadingRef.current) {
          const timeRemaining =
            audioElement.duration - audioElement.currentTime;
          const crossfadeDuration = crossfadeConfigRef.current.duration;

          if (timeRemaining <= crossfadeDuration && timeRemaining > 0) {
            startCrossfadeOut();
          }
        }
      };

      const onEnded = () => {
        if (audioElementRef.current !== audioElement || !isCurrentRequest()) return;
        setIsPlaying(false);

        // Si NO estamos en crossfade, llamar al callback para siguiente canción
        if (!isCrossfadingRef.current && onTrackEndedRef.current) {
          // Reset del gain para la siguiente canción
          if (masterGainRef.current && audioContextRef.current) {
            masterGainRef.current.gain.setValueAtTime(
              1.0,
              audioContextRef.current.currentTime,
            );
          }
          onTrackEndedRef.current();
        }
      };

      const onError = () => {
        if (audioElementRef.current !== audioElement || !isCurrentRequest()) return;
        const mediaError = audioElement.error;
        const message = mediaError
          ? `Audio playback error (code ${mediaError.code})`
          : "Audio playback error";
        setIsPlaying(false);
        setIsReady(false);
        if (onTrackErrorRef.current) {
          onTrackErrorRef.current(new Error(message));
        }
      };

      if (cancelIfStale(audioElement, pendingObjectUrl, sourceNode)) return false;
      audioElement.addEventListener("loadedmetadata", onLoadedMetadata);
      audioElement.addEventListener("timeupdate", onTimeUpdate);
      audioElement.addEventListener("ended", onEnded);
      audioElement.addEventListener("error", onError);
      return true;
    },
    [
      initAudioChain,
      epicenterEnabled,
      startCrossfadeOut,
      updateAudioRouting,
      waitForAudioReady,
    ],
  );

  const play = useCallback((): boolean => {
    if (!audioElementRef.current || !audioContextRef.current) return false;
    const element = audioElementRef.current;
    console.info("[AUDIO_PLAY_CALL]", {
      requestId: activeLoadRequestIdRef.current,
      playingSrc: element.currentSrc || element.src,
    });
    if (audioContextRef.current.state === "closed") return false;
    if (audioContextRef.current.state === "suspended") {
      void audioContextRef.current.resume().catch((error) => {
        console.warn("[AUDIO_PLAY_CALL] audioContext resume failed", error);
      });
    }
    void element.play().catch((error) => {
      console.error("[PLAYBACK_ERROR] audioElement.play failed", {
        requestId: activeLoadRequestIdRef.current,
        error,
        activeSrc: element.currentSrc || element.src,
      });
      setIsPlaying(false);
      if (onTrackErrorRef.current) {
        onTrackErrorRef.current(
          error instanceof Error ? error : new Error("Audio playback failed"),
        );
      }
    });
    if (pendingCrossfadeInRef.current) {
      startCrossfadeIn();
      pendingCrossfadeInRef.current = false;
    }
    setIsPlaying(true);
    return true;
  }, [startCrossfadeIn]);

  const pause = useCallback(() => {
    if (!audioElementRef.current) return;
    audioElementRef.current.pause();
    setIsPlaying(false);
  }, []);

  const seek = useCallback((time: number) => {
    if (!audioElementRef.current) return;

    // Si estamos en crossfade y el usuario hace seek, cancelar el crossfade
    if (isCrossfadingRef.current) {
      if (crossfadeTimeoutRef.current) {
        clearTimeout(crossfadeTimeoutRef.current);
        crossfadeTimeoutRef.current = null;
      }
      isCrossfadingRef.current = false;

      // Restaurar volumen
      if (masterGainRef.current && audioContextRef.current) {
        masterGainRef.current.gain.cancelScheduledValues(
          audioContextRef.current.currentTime,
        );
        masterGainRef.current.gain.setValueAtTime(
          1.0,
          audioContextRef.current.currentTime,
        );
      }
    }

    audioElementRef.current.currentTime = time;
    setCurrentTime(time);
  }, []);

  const setDspParam = useCallback(
    (name: keyof StreamingParams, value: number) => {
      const node = workletNodeRef.current;
      const ctx = audioContextRef.current;
      if (!node || !ctx) return;

      const clampedValue = clampStreamingParam(name, value);

      // Guardar el parámetro
      dspParamsRef.current = { ...dspParamsRef.current, [name]: clampedValue };

      const param = node.parameters.get(name);
      if (!param) return;

      // Usar linearRampToValueAtTime para cambios suaves sin reinicio
      param.linearRampToValueAtTime(clampedValue, ctx.currentTime + 0.05);
    },
    [],
  );

  const applyEqOutputGain = useCallback((bandsSnapshot: EqualizerBand[]) => {
    if (!eqOutputGainRef.current || !audioContextRef.current) return;

    const maxPositiveGain = bandsSnapshot.reduce(
      (max, band) => Math.max(max, band.gain),
      0,
    );
    const clippingCompensationDb = -Math.max(0, maxPositiveGain - 3);
    const effectivePreampDb =
      eqUserPreampDbRef.current + clippingCompensationDb;
    const linear = Math.pow(10, effectivePreampDb / 20);
    eqOutputGainRef.current.gain.setValueAtTime(
      linear,
      audioContextRef.current.currentTime,
    );
  }, []);

  const setEqPreampDb = useCallback(
    (preampDb: number) => {
      eqUserPreampDbRef.current = preampDb;
      applyEqOutputGain(eqBandsRef.current);
      setTimeout(() => updateAudioRouting(), 0);
    },
    [applyEqOutputGain, updateAudioRouting],
  );

  const getAnalyserNode = useCallback(() => analyserNodeRef.current, []);

  const getCurrentDspParams = useCallback(
    () => ({ ...dspParamsRef.current }),
    [],
  );

  const setEqBandGain = useCallback(
    (index: number, gain: number) => {
      const clampedGain = Math.max(EQ_GAIN_MIN, Math.min(EQ_GAIN_MAX, gain));

      setEqBands((prev) => {
        const newBands = [...prev];
        newBands[index] = { ...newBands[index], gain: clampedGain };
        eqBandsRef.current = newBands;
        applyEqOutputGain(newBands);
        return newBands;
      });

      if (eqFiltersRef.current[index]) {
        eqFiltersRef.current[index].gain.value = eqEnabled ? clampedGain : 0;
      }
      setTimeout(() => updateAudioRouting(), 0);
    },
    [applyEqOutputGain, eqEnabled, updateAudioRouting],
  );

  const setEqEnabled = useCallback(
    (enabled: boolean) => {
      eqEnabledRef.current = enabled;
      setEqEnabledState(enabled);

      const snapshot = eqBandsRef.current;
      eqFiltersRef.current.forEach((filter, index) => {
        filter.gain.value = enabled ? snapshot[index].gain : 0;
      });

      if (enabled) {
        applyEqOutputGain(snapshot);
      } else if (eqOutputGainRef.current && audioContextRef.current) {
        eqOutputGainRef.current.gain.setValueAtTime(
          1,
          audioContextRef.current.currentTime,
        );
      }

      // Actualizar el enrutamiento de audio
      setTimeout(() => {
        updateAudioRouting();
        if (enabled) {
          const latest = eqBandsRef.current;
          eqFiltersRef.current.forEach((filter, index) => {
            filter.gain.value = latest[index].gain;
          });
        }
      }, 0);
    },
    [applyEqOutputGain, updateAudioRouting],
  );

  const setEpicenterEnabled = useCallback(
    (enabled: boolean) => {
      epicenterEnabledRef.current = enabled;
      setEpicenterEnabledState(enabled);

      const ctx = audioContextRef.current;
      const node = workletNodeRef.current;

      if (!ctx || !node) return;

      // Cambiar la intensidad del Epicenter
      const intensityParam = node.parameters.get("intensity");
      if (intensityParam) {
        const targetIntensity = enabled ? dspParamsRef.current.intensity : 0;
        intensityParam.linearRampToValueAtTime(
          targetIntensity,
          ctx.currentTime + 0.05,
        );
      }

      // Actualizar el enrutamiento de audio
      setTimeout(() => updateAudioRouting(), 0);
    },
    [updateAudioRouting],
  );

  const setOnTrackEnded = useCallback((callback: (() => void) | null) => {
    onTrackEndedRef.current = callback;
  }, []);

  const setOnTrackError = useCallback(
    (callback: ((error: Error) => void) | null) => {
      onTrackErrorRef.current = callback;
    },
    [],
  );

  const setCrossfadeConfig = useCallback((config: CrossfadeConfig) => {
    crossfadeConfigRef.current = config;
  }, []);

  const updateSpatialEffects = useCallback(
    (next: Partial<SpatialEffectsConfig>) => {
      setSpatialEffects((prev) => {
        const updated = {
          ...prev,
          ...next,
          reverbAmount:
            next.reverbAmount === undefined
              ? prev.reverbAmount
              : clampEffectAmount(next.reverbAmount),
          concertHallAmount:
            next.concertHallAmount === undefined
              ? prev.concertHallAmount
              : clampEffectAmount(next.concertHallAmount),
        };
        spatialEffectsRef.current = updated;
        applySpatialEffects(updated);
        setTimeout(() => updateAudioRouting(), 0);
        return updated;
      });
    },
    [applySpatialEffects, updateAudioRouting],
  );

  const setReverbEnabled = useCallback(
    (enabled: boolean) => {
      updateSpatialEffects({ reverbEnabled: enabled });
    },
    [updateSpatialEffects],
  );

  const setReverbAmount = useCallback(
    (amount: number) => {
      updateSpatialEffects({ reverbAmount: amount });
    },
    [updateSpatialEffects],
  );

  const setConcertHallEnabled = useCallback(
    (enabled: boolean) => {
      updateSpatialEffects({ concertHallEnabled: enabled });
    },
    [updateSpatialEffects],
  );

  const setConcertHallAmount = useCallback(
    (amount: number) => {
      updateSpatialEffects({ concertHallAmount: amount });
    },
    [updateSpatialEffects],
  );

  const resetAfterError = useCallback(() => {
    if (crossfadeTimeoutRef.current) {
      clearTimeout(crossfadeTimeoutRef.current);
      crossfadeTimeoutRef.current = null;
    }

    isCrossfadingRef.current = false;
    pendingCrossfadeInRef.current = false;

    if (audioElementRef.current) {
      audioElementRef.current.pause();
      audioElementRef.current.removeAttribute("src");
      audioElementRef.current.load();
    }

    if (sourceNodeRef.current) {
      try {
        sourceNodeRef.current.disconnect();
      } catch (_error) {
        // no-op
      }
      sourceNodeRef.current = null;
    }

    if (masterGainRef.current && audioContextRef.current) {
      masterGainRef.current.gain.setValueAtTime(
        1.0,
        audioContextRef.current.currentTime,
      );
    }

    setIsReady(false);
    setIsPlaying(false);
    setCurrentTime(0);
    setDuration(0);
  }, []);

  const getActiveSource = useCallback(
    () => audioElementRef.current?.currentSrc || audioElementRef.current?.src || "",
    [],
  );

  return {
    isReady,
    isPlaying,
    currentTime,
    duration,
    loadFile,
    play,
    getActiveSource,
    pause,
    seek,
    setDspParam,
    setEqBandGain,
    setEqEnabled,
    setEpicenterEnabled,
    setEqPreampDb,
    getAnalyserNode,
    getCurrentDspParams,
    setOnTrackEnded,
    setOnTrackError,
    setCrossfadeConfig,
    setReverbEnabled,
    setReverbAmount,
    setConcertHallEnabled,
    setConcertHallAmount,
    resetAfterError,
    eqBands,
    eqEnabled,
    epicenterEnabled,
    spatialEffects,
  };
}

export default useIntegratedAudioProcessor;
