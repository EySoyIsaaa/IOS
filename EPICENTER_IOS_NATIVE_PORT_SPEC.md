# Especificación de migración: EpicenterDSP iOS 1.0 nativo

## 1. Objetivo general

Este repositorio contiene un archivo `.zip` con la base actual de **EpicenterDSP Player 7.0**. Esa base es una app híbrida React/Vite/Capacitor con una interfaz visual ya lograda, procesamiento DSP en Web Audio Worklet y parte de la lógica Android nativa.

El objetivo es usar esa versión 7.0 como base para construir la **versión 1.0 de iOS**, conservando la interfaz actual, pero migrando a iOS nativo todo lo relacionado con audio, reproducción, base de datos local y procesamiento DSP.

La app final para iPhone debe:

- Verse igual o casi igual que la versión 7.0.
- Mantener las mismas pantallas, controles y flujo visual.
- Usar una base de datos local nativa en iOS.
- Importar canciones manualmente.
- Reproducir audio con motor 100% nativo.
- Permitir reproducción en segundo plano.
- Procesar Epicenter, EQ y efectos de forma nativa.
- Mantener sincronizada la interfaz React con el backend nativo de iOS.

La prioridad no es rediseñar la app. La prioridad es **conservar la UI actual y reemplazar el backend de audio por uno nativo real para iPhone**.

---

## 2. Contexto técnico actual

La versión 7.0 usa principalmente:

- React
- Vite
- Capacitor
- Web Audio API
- AudioWorklet para Epicenter
- Hooks frontend para audio, biblioteca, cola y estado
- Android nativo con Room/SQLite como referencia conceptual

La interfaz ya está dividida en componentes como:

- `HomePlayerView`
- `HomeDspView`
- `HomeEqView`
- `HomeFxView`
- `HomeLibraryView`
- `HomeSettingsView`

La versión iOS debe conservar esa estructura visual siempre que sea posible.

---

## 3. Primera tarea obligatoria

Antes de implementar cambios grandes:

1. Localizar el archivo `.zip` dentro del repositorio.
2. Descomprimirlo en una carpeta limpia.
3. No trabajar directamente sobre el `.zip`.
4. Crear una estructura ordenada, por ejemplo:

```txt
/source-7.0-unpacked
/ios-native-port
/docs/migration
```

5. Instalar dependencias.
6. Verificar si la base compila.
7. Corregir errores obvios de build si existen.
8. Analizar exhaustivamente la estructura antes de modificar audio o arquitectura.

Crear el archivo:

```txt
docs/migration/IOS_NATIVE_PORT_ANALYSIS.md
```

Ese reporte debe incluir:

- Estructura actual del proyecto.
- Qué partes se conservan.
- Qué partes se reemplazan.
- Qué partes se portan a Swift.
- Qué partes se portan a C++/Objective-C++ si conviene.
- Riesgos técnicos.
- Plan por fases.
- Lista de archivos que serán tocados.
- Lista de APIs nuevas que se expondrán al frontend.

No empezar una reescritura masiva sin dejar documentado el plan.

---

## 4. Objetivo de arquitectura

La arquitectura deseada es una app híbrida-controlada:

### Frontend

React/Vite/Capacitor conserva la interfaz visual.

La UI seguirá mandando comandos como:

- `play`
- `pause`
- `seek`
- `next`
- `previous`
- `setEpicenterEnabled`
- `setEpicenterIntensity`
- `setEpicenterSweep`
- `setEpicenterWidth`
- `setEQBand`
- `setEQPreset`
- `setReverbEnabled`
- `setReverbAmount`
- `setConcertHallEnabled`
- `setConcertHallAmount`
- `importTracks`
- `getLibraryPage`
- `getTrackById`
- `getPlaybackState`

### Backend iOS nativo

iOS debe encargarse de:

- Cargar archivos de audio.
- Reproducir.
- Pausar.
- Hacer seek.
- Administrar cola.
- Avanzar y retroceder canciones.
- Controlar duración y tiempo actual.
- Reproducción en segundo plano.
- Interrupciones de audio.
- Cambios de ruta de audio.
- Controles del sistema.
- Procesamiento Epicenter.
- EQ.
- Reverb / Concert Hall.
- Persistencia local.

### Bridge

Crear un plugin Capacitor iOS, por ejemplo:

- `EpicenterNativePlugin`
- `IosAudioEnginePlugin`
- `IosPlaybackPlugin`

Puede ser unificado o dividido, pero debe tener una API limpia para que el frontend no quede lleno de llamadas nativas dispersas.

---

## 5. Base de datos local iOS

Implementar una base de datos local nativa para iOS.

Opciones aceptables:

- SQLite con GRDB.swift.
- SQLite.swift.
- Core Data.
- SQLite directo.

La DB debe ser local, persistente y propia de iOS. No debe depender de IndexedDB.

### Modelo Track

Crear una entidad `Track` con campos equivalentes a Android/Room y frontend:

```txt
id: String
stableId: String
title: String
artist: String?
album: String?
durationMs: Int64
fileName: String?
fileExtension: String?
sourceUri: String
bookmarkData: Data? o String base64
localFilePath: String?
sourceType: String = "manual-ios"
addedAt: Int64
updatedAt: Int64
sizeBytes: Int64?
sampleRate: Int?
bitDepth: Int?
bitrate: Int?
channelCount: Int?
albumArtUri: String?
isAvailable: Bool
playCount: Int
lastPlayedAt: Int64?
```

### Índices requeridos

- `stableId` único.
- `sourceUri` único si aplica.
- Índices de búsqueda por `title` y `artist`.
- Índice por `addedAt`.

### Funciones mínimas

- `insertOrUpdateTrack(track)`
- `getTrackById(id)`
- `getTrackByStableId(stableId)`
- `getLibraryPage(offset, limit, search, sort)`
- `countLibrary(search)`
- `deleteTrack(id)`
- `updateTrackAvailability(id, isAvailable)`
- `updatePlaybackMetadata(id, playCount, lastPlayedAt)`

### Reglas

- No implementar auto scanner.
- No escanear toda la biblioteca del sistema.
- No borrar canciones automáticamente.
- No marcar canciones como unavailable agresivamente.
- La fuente de verdad de iOS debe ser la DB local.
- La importación manual debe hacer upsert sin duplicar canciones.

---

## 6. Importación manual de canciones

En iOS no se necesita auto scanner. Las canciones se añaden manualmente.

Implementar importación manual con `UIDocumentPickerViewController`.

### Requisitos

- Permitir seleccionar uno o múltiples archivos.
- Usar `UTType.audio`.
- Soportar inicialmente:
  - MP3
  - M4A
  - AAC
  - WAV
  - FLAC si AVFoundation lo soporta en el target real
  - ALAC/CAF si aplica

### Flujo de importación

Al seleccionar archivos:

1. Obtener URL.
2. Iniciar `startAccessingSecurityScopedResource()` si aplica.
3. Leer metadatos con `AVAsset`.
4. Obtener duración.
5. Obtener title/artist/album si existen.
6. Obtener sample rate, canales y bit depth cuando sea posible.
7. Crear `stableId`.
8. Guardar bookmark o copiar archivo al sandbox.
9. Guardar track en DB.
10. Devolver lista de tracks al frontend.

### Estrategia recomendada

Evaluar dos opciones:

A. Mantener bookmark security-scoped hacia el archivo original.  
B. Copiar el archivo al sandbox de la app.

Para máxima estabilidad en background playback, se prefiere copiar al sandbox si el tamaño no causa problemas excesivos.

Documentar la decisión en:

```txt
docs/migration/IOS_IMPORT_STRATEGY.md
```

---

## 7. Reproductor nativo iOS

Implementar un motor nativo con AVFoundation.

### Reglas críticas

- No usar `HTMLAudioElement` para iOS.
- No usar Web Audio API para iOS.
- No usar AudioWorklet para iOS.
- El WebView solo controla la UI.
- El audio debe salir de AVFoundation / AVAudioEngine.

### Motor sugerido

- `AVAudioEngine`
- `AVAudioPlayerNode`
- `AVAudioFile`
- `AVAudioPCMBuffer` si aplica
- `AVAudioUnitEQ`
- `AVAudioUnitReverb` si sirve
- Nodo DSP custom para Epicenter

### Funciones requeridas

- `play(trackId)`
- `pause()`
- `resume()`
- `stop()`
- `seek(seconds)`
- `next()`
- `previous()`
- `setQueue(trackIds, startIndex)`
- `getCurrentTime()`
- `getDuration()`
- `getPlaybackState()`

### Robustez

El reproductor debe:

- Evitar race conditions.
- Cancelar cargas obsoletas.
- Evitar que el título cambie pero siga sonando la canción anterior.
- Manejar fin de canción y pasar a la siguiente.
- Mantener progreso correcto.
- Mandar eventos al frontend.

### Eventos al frontend

- `playbackStateChanged`
- `progressChanged`
- `trackChanged`
- `queueChanged`
- `error`
- `libraryChanged`
- `audioRouteChanged`
- `interruptionBegan`
- `interruptionEnded`

---

## 8. Background playback iOS

Configurar iOS correctamente para reproducción en segundo plano.

### Requisitos

1. Activar Background Modes:
   - Audio, AirPlay, and Picture in Picture si aplica.

2. Configurar `Info.plist`:

```txt
UIBackgroundModes = audio
```

3. Configurar `AVAudioSession`:

```txt
category: playback
mode: default
```

4. Manejar:
   - llamadas
   - Siri
   - audífonos Bluetooth
   - cambios de salida
   - interrupciones del sistema

5. Integrar `MPNowPlayingInfoCenter`:
   - título
   - artista
   - álbum
   - duración
   - tiempo actual
   - artwork si existe

6. Integrar `MPRemoteCommandCenter`:
   - play
   - pause
   - toggle play/pause
   - next
   - previous
   - seek desde pantalla bloqueada

### Criterios de aceptación

- Al bloquear el iPhone, la música sigue sonando.
- Desde pantalla bloqueada se puede pausar/reanudar.
- Con audífonos se puede pausar/reanudar.
- Al terminar una canción pasa a la siguiente.
- El progreso es correcto al volver a abrir la app.

---

## 9. Port del Epicenter DSP a nativo

Este es el punto más importante.

El algoritmo actual está en:

```txt
client/src/worklets/epicenter-worklet.ts
```

La tarea es portarlo a iOS nativo con la mayor fidelidad posible.

### Reglas

- No sustituirlo por un bass boost genérico.
- No reemplazarlo con solo EQ en graves.
- No reimaginar el algoritmo.
- Portar el comportamiento actual del Worklet.
- Priorizar parecido sonoro sobre facilidad.

### Análisis obligatorio

Leer `epicenter-worklet.ts` completo e identificar:

- parámetros
- filtros
- generación subarmónica
- envelope tracking
- sweep
- width
- intensidad
- wet/dry
- gates
- soft clipping
- subsonic protection
- DC blocker
- limitadores
- constantes de headroom

Crear:

```txt
docs/migration/EPICENTER_DSP_PORT_MAP.md
```

Ese documento debe mapear:

- función TS original
- variable TS original
- equivalente Swift/C++ nativo
- precisión esperada
- notas de implementación

### Implementación recomendada

Preferentemente crear core DSP en C++ para rendimiento y precisión:

```txt
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
```

Exponer a Swift mediante Objective-C++ wrapper:

```txt
EpicenterDSPBridge.h
EpicenterDSPBridge.mm
```

También se puede implementar en Swift si el rendimiento es suficiente, pero la prioridad es estabilidad en tiempo real.

### Requisitos DSP

- Procesamiento estéreo frame por frame o buffer por buffer.
- Sample rate adaptable: 44.1k, 48k, 96k si se puede.
- No generar NaN.
- No generar Inf.
- No hacer allocations dentro del callback de audio.
- No usar logs dentro del callback de audio.
- No bloquear el hilo de audio.
- No acceder a DB dentro del callback de audio.
- Parámetros thread-safe.

### Parámetros expuestos

- `epicenterEnabled`
- `intensity`
- `sweep`
- `width`
- `volume/output` si existe
- `dryWet/mix` si existe
- `safeHeadroom` si aplica

---

## 10. EQ nativo de 31 bandas

Portar el EQ a nativo.

### Bandas requeridas

```txt
20 Hz
25 Hz
31.5 Hz
40 Hz
50 Hz
63 Hz
80 Hz
100 Hz
125 Hz
160 Hz
200 Hz
250 Hz
315 Hz
400 Hz
500 Hz
630 Hz
800 Hz
1 kHz
1.25 kHz
1.6 kHz
2 kHz
2.5 kHz
3.15 kHz
4 kHz
5 kHz
6.3 kHz
8 kHz
10 kHz
12.5 kHz
16 kHz
20 kHz
```

### Requisitos

- Ganancia equivalente a la app actual, preferentemente -8 dB a +8 dB.
- Headroom automático cuando haya boosts positivos.
- Evitar clipping.
- Evitar distorsión al subir varias bandas.
- Presets deben seguir funcionando desde la UI.

### Opciones

- `AVAudioUnitEQ` con 31 bandas.
- DSP propio con biquads si se necesita más control.

---

## 11. Concert Hall / Reverb nativo

Portar los efectos actuales a nativo.

### Funciones

- Reverb
- Concert Hall
- Amount/mix
- Enable/disable
- Damping si aplica
- Wet/dry seguro
- Protección contra feedback excesivo

### Opciones

- `AVAudioUnitReverb` para primera versión si suena bien.
- DSP custom si se requiere igualar más la versión WebAudio.

Si se usa `AVAudioUnitReverb`, documentar diferencias sonoras frente a la 7.0.

---

## 12. Orden del grafo de audio

Definir y documentar el grafo final en:

```txt
docs/migration/IOS_AUDIO_GRAPH.md
```

Grafo sugerido:

```txt
AVAudioPlayerNode
→ EpicenterDSPNode
→ EQ31BandNode
→ Reverb/ConcertHallNode
→ MasterLimiter/Headroom
→ MainMixer
→ Output
```

Evaluar si conviene:

- EQ antes o después de Epicenter.
- FX antes o después de EQ.
- Limitador final.

Prioridades:

1. Estabilidad.
2. Cero clipping evidente.
3. Sonido parecido al WebAudio actual.
4. Baja latencia.
5. Background playback estable.

---

## 13. Frontend / UI

La UI actual debe conservarse.

### Reglas

- No rehacer visualmente la app.
- No romper componentes actuales.
- No llenar `Home.tsx` de llamadas nativas dispersas.
- Centralizar el bridge.

### Tareas

Crear una capa de abstracción como:

```txt
client/src/native/iosNativeAudio.ts
client/src/hooks/useIosNativeAudioProcessor.ts
client/src/hooks/useAudioProcessorFacade.ts
```

Cuando `platform === ios`, usar plugin nativo.  
Cuando no sea iOS, conservar lógica existente si aplica.

### Estado compatible con la UI

Mantener nombres de estado similares:

- `isPlaying`
- `currentTime`
- `duration`
- `currentTrack`
- `epicenterEnabled`
- `eqBands`
- `reverbEnabled`
- `concertHallEnabled`

---

## 14. Funciones que deben mantenerse

### Biblioteca

- Agregar canciones manualmente.
- Mostrar lista.
- Buscar canciones.
- Mostrar título/artista.
- Reproducir desde biblioteca.
- Cola básica.
- Eliminar canción si ya existe esa función.

### Reproductor

- Play/pause.
- Siguiente/anterior.
- Barra de progreso.
- Seek.
- Portada si se puede obtener.
- Duración.
- Tiempo actual.
- Estado visual correcto.
- Background playback.

### DSP

- Epicenter on/off.
- Controles Epicenter actuales.
- Intensidad/sweep/width.
- Medidores/espectro visual si la UI los muestra.

### EQ

- 31 bandas.
- Presets.
- Reset.
- Enable/disable si existe.

### FX

- Reverb.
- Concert Hall.
- Amount.
- On/off.

### Settings

- Conservar settings existentes cuando sea posible.
- Persistir configuración localmente en iOS.

---

## 15. Persistencia de settings

Guardar settings locales en iOS.

Opciones:

- `UserDefaults` para settings simples.
- DB para presets complejos.

Persistir:

- Último track.
- Posición opcional.
- EQ actual.
- Preset actual.
- Epicenter enabled.
- Parámetros de Epicenter.
- Reverb/Concert Hall settings.
- Orden de biblioteca si aplica.

---

## 16. Robustez y manejo de errores

Implementar errores claros:

- archivo no accesible
- bookmark inválido
- formato no soportado
- no se pudo abrir AVAudioFile
- error al cargar buffer
- error de audio session
- error de DB
- pista no encontrada

No crashear si:

- el usuario borra el archivo fuera de la app
- el bookmark expira
- el archivo es muy grande
- el formato no es soportado
- cambia la salida Bluetooth
- entra una llamada
- se bloquea pantalla
- se mata y relanza app

El frontend debe recibir errores legibles y mostrarlos con toast/modal existente si ya existe.

---

## 17. Cuidado con Apple Music / DRM

No intentar procesar canciones protegidas de Apple Music.

No prometer acceso a la biblioteca completa.

No usar APIs privadas.

No hacer inyección de audio del sistema.

No procesar audio de otras apps.

Solo reproducir archivos importados manualmente por el usuario.

Esto es importante para cumplimiento de App Store.

---

## 18. Limpieza de la base 7.0

Antes de portar, revisar y corregir duplicados conocidos.

### Posibles duplicados

En `HomeFxView.tsx` puede existir:

```tsx
const meter = [...]
```

Si está duplicado o no usado, eliminarlo.

En `HomePlayerView.tsx` puede existir duplicado:

```tsx
const track = queue.currentTrack;
```

Debe quedar solo una declaración válida.

Si `HomePlayerView` usa `useMemo`, asegurar el import:

```tsx
import { useEffect, useMemo, useRef, useState } from "react";
```

Ejecutar:

```bash
pnpm install
pnpm build
pnpm check
```

La base web debe compilar antes de integrar cambios grandes.

---

## 19. Estructura iOS sugerida

Crear estructura parecida a:

```txt
ios/App/App/NativeAudio/
  NativeAudioEngine.swift
  NativePlaybackController.swift
  NativeQueueManager.swift
  NativeAudioSessionManager.swift
  NowPlayingManager.swift
  RemoteCommandManager.swift
  NativeLibraryDatabase.swift
  NativeTrackImporter.swift
  NativeTrackRepository.swift
  NativeAudioModels.swift

ios/App/App/DSP/
  EpicenterDSPCore.hpp
  EpicenterDSPCore.cpp
  EpicenterDSPBridge.h
  EpicenterDSPBridge.mm
  EQ31BandProcessor.swift
  ReverbProcessor.swift
  AudioLimiter.swift

ios/App/App/Plugins/
  EpicenterNativePlugin.swift

docs/migration/
  IOS_NATIVE_PORT_ANALYSIS.md
  IOS_IMPORT_STRATEGY.md
  EPICENTER_DSP_PORT_MAP.md
  IOS_AUDIO_GRAPH.md
  IOS_PLUGIN_API.md
  IOS_TEST_PLAN.md
```

---

## 20. Plugin API propuesta

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

Documentar el contrato final en:

```txt
docs/migration/IOS_PLUGIN_API.md
```

---

## 21. Plan de trabajo por fases

### Fase 0 - Preparación

- Descomprimir ZIP.
- Instalar dependencias.
- Corregir errores obvios de build.
- Documentar estructura.
- Crear branch: `ios-native-1.0-port`

### Fase 1 - Auditoría

- Analizar Worklet.
- Analizar `useIntegratedAudioProcessor`.
- Analizar componentes Home.
- Analizar biblioteca Android Room como referencia.
- Documentar mapa de migración.

### Fase 2 - DB local iOS

- Crear DB.
- Crear modelo `Track`.
- Crear repositorio.
- Crear import manual.
- Probar persistencia.

### Fase 3 - Plugin bridge mínimo

- Crear plugin Capacitor iOS.
- Exponer `importTracks`.
- Exponer `getLibraryPage`.
- Conectar UI de biblioteca.

### Fase 4 - Reproductor nativo básico

- `AVAudioSession`.
- `AVAudioEngine`.
- `AVAudioPlayerNode`.
- Play/pause/seek.
- Progreso.
- Cola.
- Eventos al frontend.

### Fase 5 - Background playback

- `Info.plist`.
- Background mode.
- Now Playing.
- Remote Command Center.
- Interrupciones.

### Fase 6 - DSP Epicenter

- Portar Worklet a C++/Swift.
- Integrar nodo DSP.
- Exponer parámetros.
- Validar sonido.
- Documentar diferencias.

### Fase 7 - EQ

- Implementar 31 bandas.
- Conectar UI.
- Presets.
- Headroom.

### Fase 8 - FX

- Reverb.
- Concert Hall.
- Amount.
- Seguridad.

### Fase 9 - Integración final

- Unificar estados.
- Arreglar UI.
- Pruebas.
- Limpieza.
- Documentación.

### Fase 10 - Release iOS 1.0

- Revisar permisos.
- Revisar `Info.plist`.
- Revisar signing.
- Revisar cumplimiento App Store.
- Generar build firmable.

---

## 22. Criterios de aceptación

La tarea se considera correcta si:

1. El proyecto compila.
2. La app iOS abre en iPhone real.
3. Se puede importar una canción manualmente.
4. La canción queda guardada en DB local.
5. Al cerrar y abrir la app, la canción sigue en biblioteca.
6. Se puede reproducir.
7. Se puede pausar/reanudar.
8. Se puede hacer seek.
9. Se puede ir a siguiente/anterior.
10. Al bloquear el iPhone, la música sigue sonando.
11. Los controles de pantalla bloqueada funcionan.
12. El Epicenter se puede activar/desactivar.
13. Cambiar intensidad/sweep/width modifica el sonido en tiempo real.
14. El EQ de 31 bandas modifica el sonido en tiempo real.
15. Reverb/Concert Hall modifican el sonido en tiempo real.
16. No hay crasheos al cambiar de canción.
17. No hay audio viejo sonando con título nuevo.
18. No hay clipping extremo al subir EQ.
19. No hay NaN/Inf en DSP.
20. No hay logs pesados dentro del callback de audio.
21. El frontend conserva el diseño actual.

---

## 23. Reglas importantes

- No eliminar la UI actual.
- No rediseñar sin necesidad.
- No sustituir Epicenter por bass boost simple.
- No depender de WebAudio en iOS.
- No depender de HTMLAudioElement en iOS.
- No implementar auto scanner en iOS.
- No usar APIs privadas.
- No intentar procesar audio de otras apps.
- No prometer soporte para Apple Music DRM.
- No hacer cambios masivos sin documentarlos.
- Mantener commits lógicos por fase.
- Si algo no se puede completar, documentar exactamente qué falta y por qué.

---

## 24. Criterio especial de sonido

El EpicenterDSP no debe perder identidad sonora.

La versión iOS debe intentar igualar el comportamiento de la versión WebAudio 7.0, especialmente:

- golpe subarmónico
- sensación de restauración de bajos
- control por sweep
- control por width
- intensidad progresiva
- protección contra distorsión
- respuesta en canciones reales
- comportamiento en instrumentales
- estabilidad con audífonos, Bluetooth y salida por cable/adaptador

Si se debe elegir entre “más fácil de implementar” y “más parecido al sonido actual”, priorizar parecido sonoro.

Documentar cualquier diferencia audible.

---

## 25. Regla de seguridad del repo

Antes de cada cambio grande:

- Crear commit o checkpoint.
- Documentar intención.
- Modificar pocos archivos.
- Compilar.
- Probar.
- Continuar.

No hacer una reescritura gigante sin checkpoints.

Se prefiere avance gradual, verificable y reversible.

---

## 26. Comandos esperados

Después de descomprimir:

```bash
pnpm install
pnpm build
npx cap sync ios
```

Luego abrir:

```txt
ios/App/App.xcworkspace
```

Compilar en Xcode y probar en iPhone real.

---

## 27. Primer output esperado

Antes de escribir mucho código, generar:

```txt
docs/migration/IOS_NATIVE_PORT_ANALYSIS.md
```

Y responder con:

1. Resumen de la estructura encontrada.
2. Riesgos principales.
3. Plan de implementación.
4. Módulos que se van a crear.
5. Archivos que se modificarán primero.

Después continuar con implementación fase por fase.
