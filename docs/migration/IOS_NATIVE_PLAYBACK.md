# Reproductor nativo iOS básico — checkpoint v8

Fecha: 2026-05-16

## Alcance de esta fase

Esta fase implementa reproducción nativa básica para tracks importados manualmente. La salida de audio usa `AVFoundation`, `AVAudioSession`, `AVAudioEngine` y `AVAudioPlayerNode`.

No se implementa todavía:

- Epicenter DSP nativo.
- EQ nativo real.
- Concert Hall/Reverb real.
- HTMLAudioElement, WebAudio o AudioWorklet para la ruta iOS.
- Rediseño de UI.
- Cambios Android.

## Componentes nativos

### `NativeAudioSessionManager`

Responsabilidades:

- Configura `AVAudioSession` con category `.playback`.
- Activa la sesión al reproducir.
- Desactiva la sesión de forma segura al detener.
- Observa interrupciones básicas de iOS.
- Observa cambios básicos de ruta de audio.
- Mantiene la sesión activa mientras hay playback o cola/track activo para favorecer background playback.

### `NativeAudioEngine`

Responsabilidades:

- Mantiene un `AVAudioEngine` y un `AVAudioPlayerNode`.
- Carga el archivo desde `NativeTrack.localFilePath`.
- Valida que el archivo exista antes de reproducir.
- Programa el archivo con `AVAudioPlayerNode.scheduleSegment`.
- Reproduce, pausa, detiene y hace seek.
- Calcula duración desde `AVAudioFile.length / sampleRate`.
- Calcula `currentTime` desde `AVAudioPlayerNode.lastRenderTime` + `playerTime(forNodeTime:)`.
- Detecta fin de canción con el completion handler `.dataPlayedBack` del segmento programado.

### `NowPlayingManager`

Responsabilidades:

- Publica metadata en `MPNowPlayingInfoCenter.default()`.
- Incluye título, artista, álbum, duración, elapsed time, playback rate y artwork local cuando existe.
- Actualiza elapsed/rate en play, pause, seek, stop y cambio de canción.
- Throttlea actualizaciones no forzadas para no escribir Now Playing demasiadas veces por segundo.

### `RemoteCommandManager`

Responsabilidades:

- Usa `MPRemoteCommandCenter.shared()`.
- Registra una sola vez handlers para play, pause, toggle, next, previous y seek.
- Reenvía comandos de pantalla bloqueada/control center hacia `NativePlaybackController`.

### `NativeQueueManager`

Responsabilidades:

- Mantiene `trackIds`.
- Mantiene `currentIndex`.
- Resuelve `currentTrackId`.
- Avanza con `next()` y retrocede con `previous()`.

### `NativePlaybackController`

Responsabilidades:

- Conecta repositorio, sesión, engine y cola.
- Resuelve tracks desde SQLite usando `NativeTrackRepository.findTrack(id:)`.
- Carga `localFilePath` en el engine.
- Emite eventos Capacitor a través de `EpicenterNativePlugin`.
- Devuelve errores controlados si el track no existe, el archivo no está disponible o no quedan frames reproducibles desde la posición solicitada.

## Métodos reales de playback

- `setQueue({ trackIds, startIndex })`
- `play({ trackId? })`
- `pause()`
- `seek({ seconds })`
- `stop()`
- `next()`
- `previous()`
- `getPlaybackState()`

## Background playback y controles remotos

Ver detalles de la fase MediaPlayer en:

```txt
docs/migration/IOS_BACKGROUND_PLAYBACK.md
```

## Eventos implementados

- `playbackStateChanged`
- `currentTrackChanged`
- `progressChanged`
- `playbackError`

También se emite `audioRouteChanged` cuando iOS notifica cambios de ruta. El wrapper TypeScript expone overloads de `addListener` para estos eventos y `removeAllListeners()` para limpieza.

## Cómo se carga un archivo

1. El frontend llama `play({ trackId })` o configura una cola con `setQueue` y luego llama `play()`.
2. `NativePlaybackController` busca el track en SQLite mediante `NativeTrackRepository.findTrack(id:)`.
3. El track debe tener `localFilePath`, generado durante la importación manual.
4. `NativeAudioEngine` valida que el archivo exista en el sandbox.
5. Se abre el archivo con `AVAudioFile(forReading:)`.
6. Se programa el audio en `AVAudioPlayerNode`.
7. Se activa `AVAudioSession` y se inicia `AVAudioEngine`.

## Cómo se calcula `currentTime`

- Si el player está pausado, se usa el frame pausado (`pausedFrame`).
- Si está reproduciendo, se obtiene `lastRenderTime` del `AVAudioPlayerNode`.
- Ese tiempo se convierte con `playerTime(forNodeTime:)`.
- El frame actual es `scheduledStartFrame + playerTime.sampleTime`.
- El resultado se convierte a segundos dividiendo por `AVAudioFile.processingFormat.sampleRate`.

Esta aproximación permite que `seek()` reprograme desde un frame específico y que `currentTime` continúe desde el punto programado.

## Respuesta de estado

`getPlaybackState()` devuelve, como mínimo:

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

## Separación con DSP/EQ/FX

Los métodos siguientes siguen siendo stubs y no alteran el audio:

- `setEpicenterEnabled({ enabled })`
- `setEqBands({ gains })`
- `setReverbEnabled({ enabled })`

La ruta actual no inserta nodos DSP entre `AVAudioPlayerNode` y `mainMixerNode`.

## Limitaciones conocidas

- No se pudo compilar con Xcode en este contenedor porque `xcodebuild` no está disponible.
- La detección de fin depende del completion handler del segmento programado por `AVAudioPlayerNode`.
- `currentTime` es aproximado y está basado en frame position del player node.
- No hay persistencia de cola entre sesiones todavía.
- No se actualiza `playCount` ni `lastPlayedAt` en esta fase.
- La pantalla bloqueada/control center no se puede validar en este contenedor sin simulador/dispositivo iOS.
