# EpicenterDSP iOS Plugin API — checkpoint v7

Fecha: 2026-05-16

## 1. Estado de esta etapa

Esta etapa mantiene la biblioteca/importación manual iOS del checkpoint anterior e implementa playback nativo básico con `AVFoundation`, `AVAudioSession`, `AVAudioEngine` y `AVAudioPlayerNode`.

Sigue sin implementar:

- Epicenter DSP nativo.
- EQ nativo real.
- Reverb/Concert Hall real.
- Auto scanner iOS.
- Ruta HTMLAudioElement/WebAudio/AudioWorklet para iOS.
- Rediseño de UI.
- Cambios Android.

## 2. Plugin nativo

Archivo principal:

```txt
ios/App/App/Plugins/EpicenterNativePlugin.swift
```

Clase nativa:

```swift
EpicenterNativePlugin
```

Nombre JavaScript:

```txt
EpicenterNative
```

Identificador nativo:

```txt
EpicenterNativePlugin
```

El plugin registra eventos de playback con `notifyListeners` para que el frontend pueda escuchar cambios de estado, track actual, progreso y errores.

## 3. Modelos y persistencia nativa

Archivos principales:

```txt
ios/App/App/NativeAudio/NativeAudioModels.swift
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
```

La DB local usa SQLite directo mediante `SQLite3`, sin dependencias externas. Archivo físico:

```txt
Application Support/NativeLibrary/tracks.sqlite
```

La estrategia de importación copia archivos seleccionados al sandbox:

```txt
Documents/AudioLibrary
```

Ver detalles en:

```txt
docs/migration/IOS_IMPORT_STRATEGY.md
```

## 4. Playback nativo

Archivos principales:

```txt
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
```

Ver detalles en:

```txt
docs/migration/IOS_NATIVE_PLAYBACK.md
```

La reproducción carga `NativeTrack.localFilePath`, abre el archivo con `AVAudioFile(forReading:)`, programa el audio con `AVAudioPlayerNode.scheduleSegment`, activa `AVAudioSession` como `.playback` y reproduce desde `AVAudioEngine`.

## 5. Modelo `IOSNativeTrack`

Respuesta JS/TS expuesta por el plugin:

```ts
interface IOSNativeTrack {
  id: string;
  stableId: string;
  title: string;
  artist?: string | null;
  album?: string | null;
  durationMs: number;
  fileName: string;
  fileExtension: string;
  sourceUri: string;
  bookmarkData?: string | null;
  localFilePath?: string | null;
  sourceType: 'manual-ios';
  addedAt: string;
  updatedAt: string;
  sizeBytes: number;
  sampleRate?: number | null;
  bitDepth?: number | null;
  bitrate?: number | null;
  channelCount?: number | null;
  albumArtUri?: string | null;
  isAvailable: boolean;
  playCount: number;
  lastPlayedAt?: string | null;
}
```

## 6. Métodos reales de biblioteca

### `importTracks()`

Estado: real.

Presenta `UIDocumentPickerViewController` con `UTType.audio` y `allowsMultipleSelection = true`. Copia al sandbox, lee metadatos con `AVAsset`, persiste en SQLite y devuelve tracks importados.

### `getLibraryPage({ offset, limit, search, sort })`

Estado: real.

- `offset` mínimo: `0`.
- `limit` mínimo: `1`.
- `limit` máximo: `500`.
- `search` busca en `title`, `artist`, `album` y `fileName`.
- `sort`: `title`, `artist`, `album`, `duration`, `addedAt`, `updatedAt`.

### `getTrack({ id })`

Estado: real.

Busca por `id` o `stableId`.

### `deleteTrack({ id })`

Estado: real.

Elimina la fila SQLite y luego intenta eliminar archivo sandboxed y artwork asociado.

## 7. Métodos reales de playback

### `setQueue({ trackIds, startIndex })`

Estado: real.

Configura una cola básica de ids. Los ids pueden ser `id` o `stableId` porque el repositorio resuelve ambos.

Respuesta:

```json
{
  "status": "ok",
  "queue": {
    "trackIds": [],
    "currentIndex": 0,
    "currentTrackId": null
  }
}
```

### `play({ trackId? })`

Estado: real.

- Si recibe `trackId`, lo selecciona como track actual.
- Si no recibe `trackId`, usa el track actual de la cola.
- Busca el track en SQLite.
- Carga `localFilePath` en `AVAudioEngine`.
- Activa `AVAudioSession` con category `.playback`.
- Reproduce con `AVAudioPlayerNode`.

Si el track no existe o el archivo no está disponible, devuelve `status: "error"` y emite `playbackError`.

### `pause()`

Estado: real.

Pausa `AVAudioPlayerNode` y conserva el frame actual para poder reanudar.

### `seek({ seconds })`

Estado: real.

Convierte segundos a frame usando `AVAudioFile.processingFormat.sampleRate`, detiene el nodo, reprograma el segmento desde el frame solicitado y reanuda si estaba reproduciendo.

### `stop()`

Estado: real.

Detiene el player node, pausa el engine, desactiva la sesión si es posible y conserva la cola.

### `next()`

Estado: real.

Avanza en la cola y reproduce el siguiente track si existe.

### `previous()`

Estado: real.

Retrocede en la cola si existe un track anterior. Si ya está al inicio, intenta volver al segundo `0` del track actual.

### `getPlaybackState()`

Estado: real.

Respuesta:

```json
{
  "status": "ok",
  "isPlaying": false,
  "currentTime": 0,
  "duration": 0,
  "durationMs": 0,
  "currentTrackId": null,
  "stableId": null,
  "currentTrack": null,
  "queue": {
    "trackIds": [],
    "currentIndex": 0,
    "currentTrackId": null
  }
}
```

`currentTime` se calcula desde `AVAudioPlayerNode.lastRenderTime`, `playerTime(forNodeTime:)`, `scheduledStartFrame` y el sample rate del archivo.

## 8. Eventos implementados

- `playbackStateChanged`
- `currentTrackChanged`
- `progressChanged`
- `playbackError`

Evento adicional disponible:

- `audioRouteChanged`

## 9. Métodos DSP/EQ/FX que siguen stub

### `setEpicenterEnabled({ enabled })`

Estado: stub sin DSP real.

```json
{
  "status": "not_implemented",
  "method": "setEpicenterEnabled",
  "enabled": false
}
```

### `setEqBands({ gains })`

Estado: stub. Normaliza la respuesta a 31 valores para reservar contrato, pero no altera audio todavía.

```json
{
  "status": "not_implemented",
  "bands": [0, 0, 0]
}
```

### `setReverbEnabled({ enabled })`

Estado: stub sin `AVAudioUnitReverb` todavía.

```json
{
  "status": "not_implemented",
  "enabled": false
}
```

## 10. Wrapper JS/TS

Archivo:

```txt
client/src/native/iosNativeAudio.ts
```

Expone tipos TS para biblioteca, cola, playback state y métodos Capacitor registrados como:

```ts
export const EpicenterNative = registerPlugin<EpicenterNativePlugin>('EpicenterNative');
```

## 11. Reglas cumplidas en esta etapa

- No se rediseñó UI.
- No se tocó Android.
- No se implementó auto scanner.
- No se usó HTMLAudioElement/WebAudio/AudioWorklet para iOS.
- No se implementó Epicenter DSP, EQ ni Concert Hall.
- Playback básico y DSP quedan separados.
