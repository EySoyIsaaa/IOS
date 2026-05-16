# EpicenterDSP iOS Plugin API — checkpoint v6

Fecha: 2026-05-16

## 1. Estado de esta etapa

Esta etapa reemplaza los stubs de biblioteca por implementación real de importación manual iOS y base de datos local. Sigue sin implementar:

- Reproductor nativo.
- Epicenter DSP nativo.
- EQ nativo real.
- Reverb/Concert Hall real.
- Auto scanner iOS.
- Ruta WebAudio futura para iOS.
- Rediseño de UI.

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

Registro:

```txt
ios/App/App/ViewController.swift
```

El plugin se registra con `bridge?.registerPluginInstance(EpicenterNativePlugin())` dentro de `capacitorDidLoad()`.

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

## 4. Modelo `NativeTrack`

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

## 5. Métodos reales de biblioteca

### `importTracks()`

Estado: real.

Presenta `UIDocumentPickerViewController` con `UTType.audio` y `allowsMultipleSelection = true`.

Flujo resumido:

1. Obtiene URLs seleccionadas.
2. Usa security-scoped resource si aplica.
3. Copia cada audio a `Documents/AudioLibrary`.
4. Lee duración y metadatos con `AVAsset`.
5. Calcula tamaño, extensión, `stableId` y propiedades de audio disponibles.
6. Guarda/upsert en SQLite.
7. Devuelve los tracks importados al frontend.

Respuesta:

```json
{
  "status": "ok",
  "tracks": []
}
```

Cancelación del picker:

```json
{
  "status": "ok",
  "tracks": []
}
```

### `getLibraryPage({ offset, limit, search, sort })`

Estado: real.

Parámetros:

```ts
{
  offset?: number;
  limit?: number;
  search?: string;
  sort?: 'title' | 'artist' | 'album' | 'duration' | 'addedAt' | 'updatedAt';
}
```

Comportamiento:

- `offset` mínimo: `0`.
- `limit` mínimo: `1`.
- `limit` máximo: `500`.
- `search` busca en `title`, `artist`, `album` y `fileName`.
- `sort` permitido:
  - `title`
  - `artist`
  - `album`
  - `duration`
  - `addedAt`
  - `updatedAt`
- Orden por defecto: `addedAt` descendente.

Respuesta:

```json
{
  "status": "ok",
  "tracks": [],
  "offset": 0,
  "limit": 50,
  "total": 0
}
```

### `getTrack({ id })`

Estado: real.

Busca por `id` o `stableId`.

Respuesta encontrada:

```json
{
  "status": "ok",
  "track": {}
}
```

Respuesta no encontrada:

```json
{
  "status": "not_found",
  "track": null
}
```

### `deleteTrack({ id })`

Estado: real.

Elimina la fila de SQLite y luego intenta eliminar el archivo sandboxed y artwork asociado. Si el archivo ya no existe, la eliminación de DB sigue siendo válida.

Respuesta encontrada:

```json
{
  "status": "ok",
  "deleted": true,
  "track": {}
}
```

Respuesta no encontrada:

```json
{
  "status": "not_found",
  "deleted": false
}
```

## 6. Métodos de playback que siguen stub

### `getPlaybackState()`

Estado: stub.

```json
{
  "status": "not_implemented",
  "isPlaying": false,
  "currentTime": 0,
  "duration": 0,
  "currentTrackId": null
}
```

### `play({ trackId? })`

Estado: stub.

```json
{
  "status": "not_implemented",
  "method": "play"
}
```

### `pause()`

Estado: stub.

```json
{
  "status": "not_implemented",
  "method": "pause"
}
```

### `seek({ seconds })`

Estado: stub.

```json
{
  "status": "not_implemented",
  "method": "seek",
  "seconds": 0
}
```

## 7. Métodos DSP/EQ/FX que siguen stub

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

Estado: stub. Normaliza la respuesta a 31 valores para reservar contrato.

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

## 8. Wrapper JS/TS

Archivo agregado:

```txt
client/src/native/iosNativeAudio.ts
```

Expone tipos TS para `IOSNativeTrack`, respuestas de biblioteca, estado de playback stub y el plugin Capacitor registrado como:

```ts
export const EpicenterNative = registerPlugin<EpicenterNativePlugin>('EpicenterNative');
```

## 9. Eventos reservados para fases siguientes

Todavía no se emiten eventos reales desde esta etapa. Contrato reservado:

- `playbackStateChanged`
- `progressChanged`
- `currentTrackChanged`
- `queueChanged`
- `libraryChanged`
- `dspStateChanged`
- `error`
- `audioRouteChanged`
- `interruptionBegan`
- `interruptionEnded`

## 10. Reglas cumplidas en esta etapa

- No se rediseñó UI.
- No se tocó Android.
- No se implementó auto scanner.
- No se usó WebAudio para iOS.
- No se implementó reproductor nativo ni DSP.
- La biblioteca local iOS queda lista para importación manual y consultas paginadas.
