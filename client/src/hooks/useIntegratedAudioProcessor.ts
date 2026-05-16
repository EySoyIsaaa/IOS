/**
 * Deprecated iOS-only bridge.
 *
 * The old browser audio implementation was removed from the active route.
 * Existing imports are forwarded to the native iOS facade.
 */
export { useIosNativeAudioProcessor as useIntegratedAudioProcessor } from './useIosNativeAudioProcessor';
export type { StreamingParams, EqBand as EqualizerBand, SpatialEffectsConfig } from './useIosNativeAudioProcessor';
export const EQ_GAIN_MIN = -12;
export const EQ_GAIN_MAX = 12;
