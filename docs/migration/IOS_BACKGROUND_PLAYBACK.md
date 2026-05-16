# Background playback iOS — Now Playing y controles remotos

Fecha: 2026-05-16

## Alcance

Esta fase agrega integración real con `MediaPlayer` para que la ruta nativa iOS pueda continuar en background y exponerse en pantalla bloqueada. La reproducción sigue usando `AVFoundation`, `AVAudioSession`, `AVAudioEngine` y `AVAudioPlayerNode`.

No se implementa todavía:

- Epicenter DSP nativo.
- EQ nativo real.
- Concert Hall/Reverb real.
- HTMLAudioElement, WebAudio o AudioWorklet para iOS.
- Cambios Android o rediseño UI.

## `NowPlayingManager`

Archivo:

```txt
ios/App/App/NativeAudio/NowPlayingManager.swift
```

Responsabilidades:

- Usa `MPNowPlayingInfoCenter.default()`.
- Publica título, artista, álbum, duración, elapsed time y `playbackRate`.
- Publica artwork cuando `NativeTrack.albumArtUri` apunta a una imagen local válida.
- Actualiza metadata cuando cambia el track actual.
- Actualiza elapsed time y rate en play, pause, seek, stop y cambio de canción.
- Aplica throttling de 1 segundo para updates no forzados, evitando escribir Now Playing demasiadas veces por segundo.

## `RemoteCommandManager`

Archivo:

```txt
ios/App/App/NativeAudio/RemoteCommandManager.swift
```

Responsabilidades:

- Usa `MPRemoteCommandCenter.shared()`.
- Es singleton para evitar registrar handlers duplicados si el plugin/controlador se inicializa más de una vez.
- Permite actualizar closures de handlers sin volver a registrar targets.
- Convierte resultados del controlador a `MPRemoteCommandHandlerStatus`.

Comandos soportados:

- `playCommand`
- `pauseCommand`
- `togglePlayPauseCommand`
- `nextTrackCommand`
- `previousTrackCommand`
- `changePlaybackPositionCommand`

## Integración en `NativePlaybackController`

`NativePlaybackController` ahora coordina:

1. `NativeTrackRepository` para resolver tracks desde SQLite.
2. `NativeAudioSessionManager` para activar `.playback` antes de reproducir.
3. `NativeAudioEngine` para cargar `localFilePath` y reproducir.
4. `NowPlayingManager` para publicar metadata y estado de reproducción.
5. `RemoteCommandManager` para que pantalla bloqueada/control center ejecuten `play`, `pause`, `next`, `previous` y `seek`.

Actualizaciones principales:

- Al cargar un track, se publica metadata con `playbackRate = 0`.
- Al reproducir, se actualiza `playbackRate = 1`.
- Al pausar, seek o stop, se actualiza elapsed time y `playbackRate`.
- Al hacer `next`/`previous`, la carga del nuevo track actualiza metadata y luego estado de reproducción.
- Al terminar una canción sin siguiente track, se marca Now Playing como detenido.

## Interrupciones de audio

`NativeAudioSessionManager` observa `AVAudioSession.interruptionNotification`.

- `began`: `NativePlaybackController` guarda si estaba reproduciendo, pausa `AVAudioPlayerNode`, detiene el timer de progreso, actualiza Now Playing a rate `0` y emite `playbackStateChanged`.
- `ended`: no reanuda agresivamente; limpia el flag de interrupción, mantiene estado pausado y emite `playbackStateChanged`.

## Route changes

`NativeAudioSessionManager` observa `AVAudioSession.routeChangeNotification` y reporta el reason como string.

- Siempre emite `audioRouteChanged`.
- Si el reason es `oldDeviceUnavailable` y el engine estaba reproduciendo, `NativePlaybackController` pausa, actualiza Now Playing a rate `0` y emite `playbackStateChanged`.
- Otros route changes solo notifican estado sin crashear.

## Sesión de audio y background

La sesión se configura con `AVAudioSession.Category.playback` antes de reproducir. La sesión se mantiene activa mientras hay track/cola activa para preservar comportamiento de playback/background; al detener sin cola activa puede desactivarse con `.notifyOthersOnDeactivation`.

`Info.plist` ya declara `UIBackgroundModes` con `audio`; esta fase no cambia esa configuración.

## Separación DSP/EQ/FX

Los métodos `setEpicenterEnabled`, `setEqBands` y `setReverbEnabled` siguen siendo stubs y no insertan nodos ni unidades de audio en la ruta de `AVAudioEngine`.

## Limitaciones

- No se pudo validar pantalla bloqueada/control center en este contenedor porque no hay simulador/dispositivo ni `xcodebuild`.
- `MPNowPlayingInfoCenter` y `MPRemoteCommandCenter` requieren ejecución en iOS real/simulador para validación funcional.
- La persistencia de cola entre sesiones sigue fuera de alcance.
