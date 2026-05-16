# EpicenterDSP iOS Audio Graph — diseño preliminar

Fecha: 2026-05-16

## 1. Estado de esta etapa

Esta etapa solo crea la base iOS y los stubs nativos. No existe todavía un grafo de audio funcional ni procesamiento DSP real. Este documento fija el grafo objetivo para las fases posteriores sin implementarlo todavía.

## 2. Regla crítica

La futura ruta iOS no usará:

- `HTMLAudioElement` como motor de reproducción iOS.
- Web Audio API como motor de audio iOS.
- `AudioWorklet` como procesador real iOS.

La UI React seguirá funcionando como capa visual/controladora, pero el audio iOS debe salir de AVFoundation/AVAudioEngine.

## 3. Grafo objetivo preliminar

Grafo objetivo reservado para Fases 4 a 8:

```txt
AVAudioPlayerNode
→ EpicenterDSPNode / AVAudioSourceNode-or-render-block backed by EpicenterDSPCore
→ EQ31BandNode
→ Reverb/ConcertHallNode
→ MasterLimiter/Headroom
→ MainMixer
→ Output
```

## 4. Módulos creados como stubs

### Playback / sesión / cola

```txt
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
```

Responsabilidad futura:

- Crear y mantener `AVAudioEngine`.
- Cargar `AVAudioFile`/buffers según estrategia final.
- Controlar `play`, `pause`, `seek`, `next`, `previous`.
- Evitar race conditions de carga.
- Mantener progreso y duración.
- Configurar `AVAudioSession` como `playback`.

### Background playback / controles del sistema

```txt
ios/App/App/NativeAudio/NowPlayingManager.swift
ios/App/App/NativeAudio/RemoteCommandManager.swift
```

Responsabilidad futura:

- `MPNowPlayingInfoCenter`.
- `MPRemoteCommandCenter`.
- Interrupciones y route changes.
- Sincronización de progreso en pantalla bloqueada.

### Biblioteca / importación

```txt
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
```

Responsabilidad futura:

- Import manual con `UIDocumentPickerViewController`.
- Persistencia local iOS.
- Upsert sin duplicados.
- No auto scanner.

### DSP / EQ / FX

```txt
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
ios/App/App/DSP/EpicenterDSPBridge.h
ios/App/App/DSP/EpicenterDSPBridge.mm
ios/App/App/DSP/EQ31BandProcessor.swift
ios/App/App/DSP/ReverbProcessor.swift
ios/App/App/DSP/AudioLimiter.swift
```

Responsabilidad futura:

- Port fiel de `client/src/worklets/epicenter-worklet.ts` tras completar `EPICENTER_DSP_PORT_MAP.md`.
- EQ de 31 bandas con headroom.
- Reverb / Concert Hall nativos.
- Protección contra clipping, NaN, Inf y denormals.
- Sin allocations/logs/bloqueos dentro del callback de audio.

## 5. Info.plist preliminar

Se agregó `UIBackgroundModes` con `audio` en:

```txt
ios/App/App/Info.plist
```

Esto solo prepara el entitlement/plist para reproducción en segundo plano. La implementación real de sesión, Now Playing y remote commands queda pendiente para Fase 5.

## 6. Decisiones pospuestas

Las siguientes decisiones no se cerraron en esta etapa porque requieren auditoría/implementación posterior:

1. Tipo exacto de nodo para Epicenter DSP:
   - `AVAudioSourceNode`, render block custom, `AVAudioUnit` custom o wrapper C++ invocado desde Swift/Objective-C++.
2. Orden definitivo EQ vs Epicenter:
   - El grafo sugerido mantiene Epicenter antes de EQ, pero debe validarse contra el sonido de la versión 7.0.
3. Reverb/Concert Hall:
   - `AVAudioUnitReverb` para primera versión o DSP custom si no iguala suficientemente.
4. Estrategia de importación:
   - Copiar al sandbox vs bookmark security-scoped. Se documentará en `IOS_IMPORT_STRATEGY.md`.
5. Persistencia local:
   - SQLite/GRDB/Core Data/SQLite directo. Se decidirá en Fase 2.

## 7. Criterios para avanzar a implementación real

Antes de implementar DSP o playback completo:

- Completar `EPICENTER_DSP_PORT_MAP.md`.
- Completar `IOS_IMPORT_STRATEGY.md`.
- Confirmar que `pnpm build` produce `dist/public`.
- Ejecutar `npx cap sync ios` en un entorno con dependencias instaladas.
- Abrir `ios/App/App.xcworkspace` en Xcode y resolver CocoaPods/signing.
