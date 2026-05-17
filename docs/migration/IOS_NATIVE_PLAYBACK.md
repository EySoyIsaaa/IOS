# iOS Native Playback

## Estado de esta fase

La reproducción nativa sigue centralizada en `NativePlaybackController` y `NativeAudioEngine`. La fase actual conserva importación, biblioteca, reproducción, background playback y controles remotos, y añade EQ/FX dentro del grafo AVAudioEngine.

## Grafo

```text
AVAudioFile local
→ AVAudioSourceNode
→ etapa Epicenter nativa existente
→ AVAudioUnitEQ 31 bandas
→ AVAudioUnitReverb Reverb
→ AVAudioUnitReverb Concert Hall
→ mainMixerNode
```

## Funciones preservadas

- Importación con `UIDocumentPicker` permanece en `NativeTrackImporter`.
- Biblioteca local/SQLite permanece fuera del hilo de audio.
- Queue, play/pause/seek/stop/next/previous permanecen en `NativePlaybackController`.
- Background playback y controles remotos permanecen en `NativeAudioSessionManager`, `NowPlayingManager` y `RemoteCommandManager`.
- El mini-player y la bottom navigation son frontend; no afectan sesión ni Now Playing.

## EQ y FX durante reproducción

Los métodos del plugin llaman a `NativePlaybackController`, que serializa operaciones en su queue interna y actualiza unidades ya adjuntas al motor. No se detiene ni se recrea el grafo al mover sliders o knobs.

## Cómo probar en iPhone

1. Ejecutar `pnpm build`.
2. Ejecutar `npx cap sync ios`.
3. Abrir `ios/App/App.xcworkspace` en Xcode.
4. Compilar en iPhone físico.
5. Importar canciones con el picker nativo.
6. Reproducir una canción.
7. Validar play/pause/seek/next/previous.
8. Bloquear pantalla y comprobar controles remotos/background playback.
9. Activar Epicenter, EQ, Reverb y Concert Hall; mover parámetros en tiempo real.
10. Hacer seek y cambio de canción con EQ/FX activos.

## Limitaciones conocidas

La fidelidad de Reverb/Concert Hall depende de presets AVFoundation. Para un carácter exacto de hardware externo se requeriría portar DSP propio en una fase posterior.
