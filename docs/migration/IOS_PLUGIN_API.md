# iOS Plugin API

## Epicenter native API

Plugin: `EpicenterNative` (`EpicenterNativePlugin`).

Métodos conectados en esta fase:

- `setEpicenterEnabled({ enabled: boolean })`
  - Actualiza el bypass nativo del core C++.
  - Devuelve `{ status: "ok", epicenter: { enabled, intensity, sweepFreq, width, balance, volume } }`.
- `setEpicenterParams({ intensity?, sweepFreq?, sweep?, width?, balance?, volume?, output? })`
  - Actualiza parámetros en tiempo real.
  - `sweep` es alias de `sweepFreq` y `output` es alias de `volume` para compatibilidad.
- `getPlaybackState()`
  - Incluye `epicenter` con el estado actual del DSP.

## Rango de parámetros

| Parámetro | Rango | Default | Mapeo Worklet |
|---|---:|---:|---|
| `enabled` | boolean | `false` | Switch nativo de bypass. |
| `intensity` | 0–100 | 100 | `parameterDescriptors.intensity`. |
| `sweepFreq` | 27–63 Hz | 45 | `parameterDescriptors.sweepFreq`. |
| `width` | 0–100 | 50 | `parameterDescriptors.width`. |
| `balance` | 0–100 | 100 | `parameterDescriptors.balance`. |
| `volume` / `output` | 0–100 | 100 | `parameterDescriptors.volume`. |

## Frontend iOS

`client/src/hooks/useIosNativeAudioProcessor.ts` reemplaza el stub `setDspParam` y ahora llama `EpicenterNative.setEpicenterParams({ [key]: value })`. La UI no cambió; los knobs existentes de `Home.tsx` siguen mandando `sweepFreq`, `width`, `intensity`, `balance` y `volume`.
