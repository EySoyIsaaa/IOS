# iOS Plugin API

Plugin Capacitor: `EpicenterNative` (`EpicenterNativePlugin`).

## Playback y biblioteca

La API existente se mantiene:

- `importTracks()`
- `getLibraryPage({ offset?, limit?, search?, sort? })`
- `getTrack({ id })`
- `deleteTrack({ id })`
- `setQueue({ trackIds, startIndex? })`
- `play({ trackId? })`
- `pause()`
- `seek({ seconds })`
- `stop()`
- `next()`
- `previous()`
- `getPlaybackState()`

## Epicenter

- `setEpicenterEnabled({ enabled })`
- `setEpicenterParams({ intensity?, sweepFreq?, sweep?, width?, balance?, volume?, output? })`

Esta fase no modifica el carácter ni algoritmo Epicenter; solo mantiene la ruta iOS compatible con los nuevos módulos EQ/FX.

## EQ nativo

- `setEqEnabled({ enabled })`
- `setEqBand({ index, gain })`
- `setEqBands({ gains })`
- `setEqPreset({ name, gains })`
- `resetEq()`

Parámetros:

| Campo | Tipo | Detalle |
|---|---|---|
| `enabled` | boolean | Activa/bypassea el EQ nativo. |
| `index` | number | Índice de banda `0–30`. |
| `gain` | number | dB clamp a `-12…+12`. |
| `gains` | number[] | Lista de hasta 31 gains; faltantes se rellenan con `0`. |
| `name` | string opcional | Nombre de preset para trazabilidad de respuesta. |

Respuesta EQ incluye `status`, `enabled`, `bands`, `frequencies` y `headroomDb`.

## FX nativos

- `setReverbEnabled({ enabled })`
- `setReverbAmount({ amount })`
- `setConcertHallEnabled({ enabled })`
- `setConcertHallAmount({ amount })`

`amount` es `0–100` desde frontend y se convierte en nativo a wet/dry limitado. La respuesta FX incluye estado de ambos efectos, wet/dry efectivo, modo combinado y `outputVolume`.

## Estado de reproducción

`getPlaybackState()` agrega:

- `eq`: estado del ecualizador nativo.
- `fx`: estado de Reverb/Concert Hall.

Esto permite que `useIosNativeAudioProcessor` hidrate la UI tras abrir la app o volver desde background.
