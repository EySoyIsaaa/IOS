# iOS Native Playback

## Estado de esta fase

La reproducción nativa sigue centralizada en `NativePlaybackController` y `NativeAudioEngine`. La fase Epicenter cambió la fuente interna del motor para poder procesar DSP nativo:

- antes: `AVAudioPlayerNode` programando `AVAudioFile` directo al mixer;
- ahora: `AVAudioSourceNode` leyendo un `AVAudioPCMBuffer` decodificado fuera del render y procesado por `EpicenterDSPCore` antes del `mainMixerNode`.

## Funciones preservadas

- Importación con `UIDocumentPicker` permanece en `NativeTrackImporter`.
- Biblioteca local/SQLite permanece fuera del hilo de audio.
- Queue, play/pause/seek/stop/next/previous permanecen en `NativePlaybackController`.
- Background playback y controles remotos permanecen en `NativeAudioSessionManager`, `NowPlayingManager` y `RemoteCommandManager`.

## Cómo probar en iPhone

1. Ejecutar `pnpm build`.
2. Ejecutar `npx cap sync ios`.
3. Abrir `ios/App/App.xcworkspace` en Xcode.
4. Compilar en iPhone físico.
5. Importar canciones con el picker nativo.
6. Reproducir una canción.
7. Activar Epicenter y mover `INTENSIDAD`, `SWEEP`, `WIDTH`, `BALANCE` y `VOLUME`.
8. Validar bypass limpio al desactivar Epicenter.
9. Bloquear pantalla y comprobar controles remotos/background playback.

## Limitaciones conocidas

El archivo completo se decodifica a memoria en `load(track:)` para mantener el render callback sin I/O de disco. Es aceptable para esta fase de fidelidad DSP; una fase posterior podría reemplazarlo por un lector circular prebufferizado siempre que no bloquee el hilo de audio.
