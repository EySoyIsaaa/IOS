# iOS Heavy Audio Stability

## Problema

La ruta actual usa `AVAudioSourceNode` con un buffer PCM completo en memoria para que Epicenter procese in-place antes de EQ/FX. En archivos largos de alta resolución, decodificar toda la canción puede consumir demasiada RAM.

## Estrategia de esta estabilización

Esta fase mantiene la arquitectura actual y agrega guardas antes de decodificar completo:

1. Abrir `AVAudioFile` en Float32 non-interleaved.
2. Validar `sampleRate > 0`, `channelCount > 0` y `length > 0`.
3. Calcular memoria estimada:

```text
frames * channels * sizeof(Float32)
```

4. Rechazar de forma controlada si el buffer excede `512 MB` o supera `UInt32.max` frames para `AVAudioPCMBuffer`.
5. Registrar logs fuera del callback:

```text
[iOS Audio] file sampleRate=...
[iOS Audio] channels=...
[iOS Audio] estimatedMemoryMB=...
[iOS Audio] strategy=full-buffer
[iOS Audio] decode failed=...
```

## Errores controlados

`NativeAudioEngine.EngineError` expone códigos para que `NativePlaybackController` emita `playbackError` sin pantalla roja:

- `file_too_large`
- `unsupported_format`
- `decode_failed`
- `buffer_allocation_failed`
- `audio_format_error`
- `file_unavailable`
- `no_loaded_track`
- `no_playable_frames`

## Soporte Hi-Res

La ruta no asume 44.1/48 kHz. `EpicenterDSPCore.prepare(...)` recibe el `sampleRate` real del `AVAudioFile` decodificado. Se validan como soportados los sample rates comunes hasta 192 kHz: 44.1, 48, 88.2, 96, 176.4 y 192 kHz, siempre que el archivo quepa en el límite de memoria o se rechace con error controlado.

## Pendiente futuro

Para canciones muy largas/Hi-Res que excedan 512 MB decodificados, una fase posterior debería implementar streaming/chunked decode con ring buffer. Esta fase prioriza no crashear y mantener Epicenter/EQ/FX/background playback intactos.
