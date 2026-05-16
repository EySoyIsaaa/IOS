# EpicenterDSP iOS Native Port — análisis inicial

Fecha: 2026-05-16

## 1. Alcance de este checkpoint

Este documento corresponde al primer output exigido por `EPICENTER_IOS_NATIVE_PORT_SPEC.md`. El alcance aplicado en este checkpoint fue deliberadamente limitado a:

1. Localizar el ZIP de EpicenterDSP Player 7.0.
2. Descomprimirlo en una carpeta temporal limpia.
3. Mover el contenido real del proyecto a la raíz del repositorio para que la raíz sea el proyecto principal.
4. Intentar instalar dependencias.
5. Intentar verificar build/check de la base web.
6. Corregir únicamente errores obvios de build detectables sin cambiar arquitectura.
7. Analizar la estructura movida a raíz y dejar el plan de migración antes de iniciar cambios grandes.

No se inició todavía la implementación de fases iOS nativas, bridge, DB, AVFoundation ni DSP nativo.

## 2. ZIP localizado y movimiento a raíz

- ZIP localizado: `fx-main (13).zip`.
- Carpeta raíz interna detectada al descomprimir: `fx-main/`.
- Acción realizada: se descomprimió el ZIP en una carpeta temporal generada con `mktemp -d` y se copió el contenido de `fx-main/` a la raíz del repo con `rsync -a`.
- Resultado: la raíz del repositorio quedó como proyecto principal, con `package.json`, `pnpm-lock.yaml`, `client/`, `server/`, `shared/`, `android/`, `capacitor.config.ts`, `vite.config.ts` y documentación base en el nivel superior.

## 3. Estructura actual del proyecto

### 3.1 Raíz

Archivos y carpetas principales detectados:

```txt
EPICENTER_IOS_NATIVE_PORT_SPEC.md
fx-main (13).zip
package.json
pnpm-lock.yaml
capacitor.config.ts
vite.config.ts
vitest.config.ts
tsconfig.json
tsconfig.node.json
tsconfig.test.json
build-worklet.mjs
build.sh
client/
server/
shared/
android/
patches/
docs/migration/
basura_para_borrar_manual/
```

### 3.2 Frontend React/Vite/Capacitor

Ubicación principal: `client/`.

Componentes relevantes encontrados:

```txt
client/src/pages/Home.tsx
client/src/components/home/HomePlayerView.tsx
client/src/components/home/HomeDspView.tsx
client/src/components/home/HomeEqView.tsx
client/src/components/home/HomeFxView.tsx
client/src/components/home/HomeLibraryView.tsx
client/src/components/home/HomeSettingsView.tsx
client/src/components/home/HomeSearchView.tsx
client/src/components/home/HomeOverlays.tsx
client/src/components/home/HomeImportProgressOverlay.tsx
client/src/components/PremiumMiniPlayer.tsx
client/src/components/BottomNavigation.tsx
client/src/components/AudioSpectrumMeter.tsx
client/src/components/TrackArtwork.tsx
```

Hooks y lógica de audio/biblioteca relevantes:

```txt
client/src/hooks/useIntegratedAudioProcessor.ts
client/src/hooks/useStreamingEpicenter.ts
client/src/hooks/useEqualizer.ts
client/src/hooks/useAudioQueue.ts
client/src/hooks/useAndroidMusicLibrary.ts
client/src/hooks/useLibraryPersistence.ts
client/src/hooks/useLastTrack.ts
client/src/hooks/usePresetPersistence.ts
client/src/hooks/useMediaSession.ts
client/src/hooks/useMediaNotification.ts
client/src/hooks/useMetadataExtractor.ts
client/src/lib/musicLibraryDB.ts
```

Worklet Epicenter actual:

```txt
client/src/worklets/epicenter-worklet.ts
client/public/epicenter-worklet.js
```

### 3.3 Backend/servidor web actual

Ubicación principal: `server/`.

Archivos relevantes:

```txt
server/index.ts
server/routers.ts
server/storage.ts
server/db.ts
server/*.test.ts
```

Este backend forma parte de la base híbrida 7.0. Para la versión iOS 1.0, no debe convertirse en fuente de verdad de audio local iOS. La fuente de verdad de biblioteca iOS debe ser una DB local nativa.

### 3.4 Código compartido

Ubicación principal: `shared/`.

Archivos relevantes:

```txt
shared/schema.ts
shared/types.ts
shared/audioQuality.ts
shared/const.ts
```

Debe revisarse si los tipos compartidos pueden reutilizarse en la capa frontend/facade, pero la persistencia iOS real será nativa.

### 3.5 Android nativo existente como referencia conceptual

Ubicación principal: `android/app/src/main/java/com/epicenter/hifi/`.

Archivos relevantes:

```txt
android/app/src/main/java/com/epicenter/hifi/MainActivity.java
android/app/src/main/java/com/epicenter/hifi/MusicScannerPlugin.java
android/app/src/main/java/com/epicenter/hifi/AppDatabase.java
android/app/src/main/java/com/epicenter/hifi/TrackEntity.java
android/app/src/main/java/com/epicenter/hifi/TrackDao.java
```

El Android actual contiene referencias útiles para el modelo de datos y Room/SQLite, pero no debe copiarse literalmente a iOS. Además, la especificación prohíbe implementar auto scanner en iOS.

### 3.6 Proyecto iOS

No se detectó todavía una carpeta `ios/` ya existente en la base movida. Por lo tanto, cuando comience la siguiente fase técnica, el proyecto iOS deberá generarse/sincronizarse con Capacitor mediante `npx cap add ios` o `npx cap sync ios` según el estado real posterior a dependencias instaladas. La especificación espera terminar usando `ios/App/App.xcworkspace`.

## 4. Estado de instalación y build

### 4.1 Instalación de dependencias

Comando intentado:

```bash
pnpm install
```

Resultado: falló antes de instalar porque Corepack intentó descargar `pnpm@10.4.1` desde `registry.npmjs.org` y el proxy devolvió `403` en el túnel HTTP.

Mitigación intentada para usar el pnpm disponible en el entorno:

```bash
COREPACK_ENABLE_PROJECT_SPEC=0 pnpm install
```

Resultado: pnpm local arrancó, leyó el lockfile, pero falló descargando paquetes desde `registry.npmjs.org` con `ERR_PNPM_FETCH_403`, por ejemplo al obtener `@aws-sdk/client-s3`.

Conclusión: la instalación no pudo completarse por una restricción de red/registro del entorno, no por un error de código del proyecto.

### 4.2 Build web

Comando intentado:

```bash
COREPACK_ENABLE_PROJECT_SPEC=0 pnpm build
```

Resultado: falló porque `esbuild` no está disponible en `node_modules` tras fallar la instalación.

Error principal:

```txt
sh: 1: esbuild: not found
```

### 4.3 Capacitor sync iOS

Comando intentado:

```bash
COREPACK_ENABLE_PROJECT_SPEC=0 pnpm exec cap sync ios
```

Resultado: falló porque `@capacitor/cli` no está instalado en `node_modules` al no haberse completado `pnpm install`.

Error principal:

```txt
Command "cap" not found
```

### 4.4 Typecheck

Comando intentado:

```bash
COREPACK_ENABLE_PROJECT_SPEC=0 pnpm check
```

Resultado: falló por dependencias/tipos faltantes y un aviso/error de configuración TypeScript 5.9:

- `Cannot find type definition file for 'node'`.
- `Cannot find type definition file for 'vite/client'`.
- `Option 'baseUrl' is deprecated ... Specify compilerOption 'ignoreDeprecations': '6.0'`.

Se corrigió únicamente el error obvio de configuración agregando `ignoreDeprecations: "6.0"` en `tsconfig.json`. Los errores de tipos faltantes dependen de completar `pnpm install`.

## 5. Correcciones mínimas realizadas antes de migrar arquitectura

La especificación menciona duplicados posibles en componentes Home. Se verificaron y corrigieron errores obvios que impedirían compilar:

1. `client/src/components/home/HomeFxView.tsx`
   - Se eliminaron declaraciones duplicadas de `const meter = [...]`.
   - Se eliminó un `useEffect` duplicado idéntico.
   - El medidor visible ya usa la constante `SIGNAL_METER_BARS`, por lo que no se alteró la UI.

2. `client/src/components/home/HomePlayerView.tsx`
   - Se agregó `useMemo` al import de React porque el componente lo usa para `qualityChips`.
   - Se eliminó la segunda declaración duplicada de `const track = queue.currentTrack` dentro del mismo scope.
   - No se modificó el flujo visual ni los controles.

3. `tsconfig.json`
   - Se agregó `ignoreDeprecations: "6.0"` para silenciar el error de `baseUrl` bajo TypeScript 5.9/6.0.

Estas correcciones son preparatorias y no cambian la arquitectura de audio.

## 6. Qué partes se conservan

Se deben conservar, salvo ajustes de integración:

- UI React actual y estructura visual Home.
- Componentes `HomePlayerView`, `HomeDspView`, `HomeEqView`, `HomeFxView`, `HomeLibraryView`, `HomeSettingsView`, `HomeSearchView`.
- Navegación visual inferior y mini player.
- Estado visual esperado por la UI: `isPlaying`, `currentTime`, `duration`, `currentTrack`, `epicenterEnabled`, `eqBands`, `reverbEnabled`, `concertHallEnabled`.
- Presets y controles existentes siempre que puedan mapearse al backend nativo.
- WebAudio/AudioWorklet en plataformas no iOS si se mantiene como fallback web/Android, siempre que iOS use el plugin nativo.

## 7. Qué partes se reemplazan en iOS

En iOS deben reemplazarse por implementación nativa:

- Reproducción basada en `HTMLAudioElement`.
- Grafo Web Audio para salida iOS.
- AudioWorklet como procesador real iOS.
- Persistencia de biblioteca basada en IndexedDB/localStorage para la fuente de verdad iOS.
- Scanner Android/MediaStore. En iOS solo habrá importación manual.
- Media Session web como fuente principal de controles iOS; iOS debe usar `MPNowPlayingInfoCenter` y `MPRemoteCommandCenter`.

## 8. Qué partes se portan a Swift

Módulos Swift previstos según la especificación:

```txt
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
ios/App/App/NativeAudio/NowPlayingManager.swift
ios/App/App/NativeAudio/RemoteCommandManager.swift
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
ios/App/App/NativeAudio/NativeAudioModels.swift
ios/App/App/DSP/EQ31BandProcessor.swift
ios/App/App/DSP/ReverbProcessor.swift
ios/App/App/DSP/AudioLimiter.swift
ios/App/App/Plugins/EpicenterNativePlugin.swift
```

Responsabilidades Swift:

- Plugin Capacitor.
- Orquestación de AVAudioSession.
- Reproductor AVFoundation.
- Cola y estado de reproducción.
- Importación manual con `UIDocumentPickerViewController`.
- Persistencia local SQLite/Core Data según decisión técnica.
- Now Playing y Remote Commands.
- Eventos hacia el frontend.
- Persistencia de settings simples con `UserDefaults` si aplica.

## 9. Qué partes se portan a C++/Objective-C++ si conviene

Módulos sugeridos para DSP de baja latencia:

```txt
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
ios/App/App/DSP/EpicenterDSPBridge.h
ios/App/App/DSP/EpicenterDSPBridge.mm
```

Motivo:

- El Worklet actual procesa frame/buffer con filtros, envelope tracking, generación subarmónica, soft clipping, limitadores y protección contra denormals.
- La especificación prioriza fidelidad sonora sobre facilidad.
- C++ facilita evitar allocations/logs en callback de audio y mantener parámetros thread-safe con estructuras simples/atómicas.

## 10. Riesgos técnicos principales

1. **Dependencias no instaladas por red**
   - Bloquea build local real hasta resolver acceso al registry o cache de paquetes.

2. **No existe aún proyecto iOS en la base movida**
   - Habrá que generar/sincronizar iOS con Capacitor cuando dependencias estén disponibles.

3. **Fidelidad del Epicenter DSP**
   - El Worklet es la fuente de verdad sonora. El port no puede ser un bass boost genérico.
   - Será necesario crear `EPICENTER_DSP_PORT_MAP.md` antes de implementar el core.

4. **Nodo DSP custom en AVAudioEngine**
   - Integrar procesamiento C++/Objective-C++ en un grafo AVFoundation requiere cuidado para no bloquear el hilo de audio.

5. **Persistencia de archivos importados**
   - Bookmarks security-scoped pueden ser frágiles para background playback. La especificación recomienda evaluar copiar al sandbox.

6. **Background playback real**
   - Requiere `UIBackgroundModes=audio`, sesión correcta, Now Playing, Remote Command Center e interrupciones.

7. **Sin auto scanner iOS**
   - La UI debe adaptarse a import manual sin arrastrar semántica de MediaStore Android.

8. **Sin romper la UI actual**
   - La integración debe hacerse mediante facade/bridge, no dispersando llamadas nativas por componentes Home.

## 11. Plan por fases

### Fase 0 — Preparación (en curso)

- [x] Descomprimir ZIP.
- [x] Mover contenido del proyecto a raíz.
- [x] Intentar instalar dependencias.
- [x] Intentar build/check.
- [x] Corregir errores obvios detectables.
- [x] Generar este análisis inicial.
- [ ] Reintentar `pnpm install`, `pnpm build`, `pnpm check` cuando el registry sea accesible.
- [ ] Ejecutar `npx cap sync ios` cuando exista plataforma iOS/dependencias.

### Fase 1 — Auditoría

- Leer completo `client/src/worklets/epicenter-worklet.ts`.
- Analizar `client/src/hooks/useIntegratedAudioProcessor.ts`.
- Analizar hooks de biblioteca, cola y persistencia.
- Analizar Android Room como referencia conceptual.
- Crear `docs/migration/EPICENTER_DSP_PORT_MAP.md`.
- Crear `docs/migration/IOS_PLUGIN_API.md` inicial.

### Fase 2 — DB local iOS

- Decidir SQLite/Core Data.
- Crear modelo `Track` iOS con campos requeridos.
- Implementar repositorio y funciones mínimas.
- Documentar decisión de importación en `IOS_IMPORT_STRATEGY.md`.

### Fase 3 — Plugin bridge mínimo

- Crear plugin Capacitor iOS centralizado.
- Exponer `importTracks`, `getLibraryPage`, `getTrack`, `deleteTrack`.
- Crear facade frontend iOS sin tocar visualmente la UI.

### Fase 4 — Reproductor nativo básico

- Crear `AVAudioSession`, `AVAudioEngine`, `AVAudioPlayerNode`.
- Implementar play/pause/resume/stop/seek/queue/progress.
- Emitir eventos al frontend.

### Fase 5 — Background playback

- Configurar `Info.plist` y capabilities.
- Implementar Now Playing y Remote Command Center.
- Manejar interrupciones y route changes.

### Fase 6 — DSP Epicenter

- Portar Worklet a C++/Objective-C++ o Swift si se justifica.
- Integrar nodo DSP real.
- Exponer parámetros y validar estabilidad NaN/Inf.

### Fase 7 — EQ nativo

- Implementar 31 bandas con `AVAudioUnitEQ` o biquads.
- Conectar presets y headroom.

### Fase 8 — FX nativo

- Implementar Reverb/Concert Hall.
- Documentar diferencias si se usa `AVAudioUnitReverb`.

### Fase 9 — Integración final

- Unificar estados, errores y eventos.
- Pruebas en dispositivo real.
- Documentación final y limpieza.

### Fase 10 — Release iOS 1.0

- Revisar permisos, signing, App Store compliance y build firmable.

## 12. Lista inicial de archivos que serán tocados

### Ya tocados en este checkpoint

```txt
client/src/components/home/HomeFxView.tsx
client/src/components/home/HomePlayerView.tsx
tsconfig.json
docs/migration/IOS_NATIVE_PORT_ANALYSIS.md
```

### Primeros archivos previstos para próximas fases

```txt
docs/migration/EPICENTER_DSP_PORT_MAP.md
docs/migration/IOS_IMPORT_STRATEGY.md
docs/migration/IOS_AUDIO_GRAPH.md
docs/migration/IOS_PLUGIN_API.md
docs/migration/IOS_TEST_PLAN.md
client/src/native/iosNativeAudio.ts
client/src/hooks/useIosNativeAudioProcessor.ts
client/src/hooks/useAudioProcessorFacade.ts
capacitor.config.ts
ios/App/App/Plugins/EpicenterNativePlugin.swift
ios/App/App/NativeAudio/NativeAudioModels.swift
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
ios/App/App/NativeAudio/NowPlayingManager.swift
ios/App/App/NativeAudio/RemoteCommandManager.swift
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
ios/App/App/DSP/EpicenterDSPBridge.h
ios/App/App/DSP/EpicenterDSPBridge.mm
ios/App/App/DSP/EQ31BandProcessor.swift
ios/App/App/DSP/ReverbProcessor.swift
ios/App/App/DSP/AudioLimiter.swift
```

## 13. APIs nuevas previstas para el frontend

El contrato final se documentará en `docs/migration/IOS_PLUGIN_API.md`. API inicial prevista:

### Library

- `importTracks()`
- `getLibraryPage({ offset, limit, search, sort })`
- `getTrack({ id })`
- `deleteTrack({ id })`
- `refreshLibrary()`

### Playback

- `setQueue({ trackIds, startIndex })`
- `play({ trackId? })`
- `pause()`
- `resume()`
- `stop()`
- `seek({ seconds })`
- `next()`
- `previous()`
- `getPlaybackState()`

### DSP

- `setEpicenterEnabled({ enabled })`
- `setEpicenterParams({ intensity, sweep, width, output })`
- `setEqEnabled({ enabled })`
- `setEqBand({ index, gain })`
- `setEqBands({ gains })`
- `setEqPreset({ name, gains })`
- `setReverbEnabled({ enabled })`
- `setReverbAmount({ amount })`
- `setConcertHallEnabled({ enabled })`
- `setConcertHallAmount({ amount })`

### Settings

- `saveSettings({ ... })`
- `loadSettings()`

### Events

- `playbackStateChanged`
- `progressChanged`
- `currentTrackChanged`
- `libraryChanged`
- `dspStateChanged`
- `error`
- `audioRouteChanged`
- `interruptionBegan`
- `interruptionEnded`

## 14. Decisiones importantes documentadas

1. **La raíz del repo queda como proyecto principal**
   - Se movió el contenido real de `fx-main/` a la raíz para evitar trabajar dentro del ZIP o una subcarpeta innecesaria.

2. **No se inicia arquitectura iOS hasta tener análisis**
   - Este documento precede cualquier cambio grande en audio, DB o bridge.

3. **Correcciones mínimas de build solamente**
   - Se tocaron duplicados/imports/config TypeScript evidentes, sin alterar UI ni lógica sonora.

4. **iOS usará backend nativo para audio**
   - WebAudio/HTMLAudioElement no se usarán como salida de audio iOS.

5. **iOS no tendrá auto scanner**
   - La biblioteca iOS se poblará por importación manual y DB local.

## 15. Pendientes y bloqueos

- Reintentar instalación cuando el entorno tenga acceso a `registry.npmjs.org` o a un mirror/cache autorizado.
- Reejecutar `pnpm build` y `pnpm check` después de dependencias.
- Generar/sincronizar plataforma iOS (`npx cap add ios`/`npx cap sync ios`) cuando Capacitor esté disponible.
- Crear los documentos de fase 1 antes de implementar DSP/DB/bridge.
