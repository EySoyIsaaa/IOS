# EpicenterDSP iOS Plugin API — checkpoint v5

Fecha: 2026-05-16

## 1. Estado de esta etapa

Esta etapa crea la base iOS y un plugin Capacitor mínimo para poder abrir el proyecto en Xcode y reservar el contrato nativo que usará la UI React. No implementa todavía:

- Reproductor nativo completo.
- Importación real con `UIDocumentPickerViewController`.
- Base de datos SQLite/Core Data.
- DSP Epicenter nativo.
- EQ nativo real.
- Reverb/Concert Hall real.

Los métodos actuales son stubs controlados que devuelven `status: "not_implemented"` y datos seguros para que una llamada temprana desde el frontend no provoque crash nativo.

## 2. Configuración Capacitor confirmada

La configuración principal sigue en `capacitor.config.ts`:

```txt
appId: com.epicenter.hifi
appName: EpicenterDSP Player
webDir: dist/public
ios.scheme: EpicenterDSP
```

Se agregó `@capacitor/ios` a `package.json` como dependencia directa de Capacitor 6 para que `npx cap add ios`/`npx cap sync ios` puedan resolverse cuando el entorno permita instalar dependencias. La plataforma iOS creada manualmente en esta etapa conserva estos valores en `ios/App/App/capacitor.config.json` para que Xcode tenga una base consistente mientras `npx cap sync ios` no puede ejecutarse en este entorno por falta de dependencias instaladas.

## 3. Plugin nativo creado

Archivo principal:

```txt
ios/App/App/Plugins/EpicenterNativePlugin.swift
```

Clase nativa:

```swift
EpicenterNativePlugin
```

Nombre JavaScript reservado:

```txt
EpicenterNative
```

Identificador nativo:

```txt
EpicenterNativePlugin
```

Registro preliminar:

```txt
ios/App/App/ViewController.swift
```

El registro usa `bridge?.registerPluginInstance(EpicenterNativePlugin())` dentro de `capacitorDidLoad()` para mantener el plugin centralizado.

## 4. Métodos stub disponibles

### 4.1 Library

#### `importTracks()`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "tracks": []
}
```

Implementación futura:

- Presentar `UIDocumentPickerViewController`.
- Filtrar por `UTType.audio`.
- Leer metadatos con `AVAsset`.
- Copiar al sandbox o guardar bookmark según `IOS_IMPORT_STRATEGY.md`.
- Persistir/upsert en DB iOS local.
- Emitir `libraryChanged`.

#### `getLibraryPage({ offset, limit, search, sort })`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "tracks": [],
  "offset": 0,
  "limit": 50,
  "total": 0
}
```

Implementación futura:

- Consultar DB local nativa.
- Soportar búsqueda por `title`, `artist`, `album` si aplica.
- Respetar paginación y orden.

### 4.2 Playback

#### `getPlaybackState()`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "isPlaying": false,
  "currentTime": 0,
  "duration": 0,
  "currentTrackId": null
}
```

#### `play({ trackId? })`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "method": "play"
}
```

#### `pause()`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "method": "pause"
}
```

#### `seek({ seconds })`

Estado actual: stub.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "method": "seek",
  "seconds": 0
}
```

Implementación futura de playback:

- `AVAudioSession` con categoría `playback`.
- `AVAudioEngine` + `AVAudioPlayerNode`.
- Cola nativa.
- Eventos `playbackStateChanged`, `progressChanged`, `currentTrackChanged`, `queueChanged`, `error`.

### 4.3 DSP / EQ / FX

#### `setEpicenterEnabled({ enabled })`

Estado actual: stub sin DSP real.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "method": "setEpicenterEnabled",
  "enabled": false
}
```

#### `setEqBands({ gains })`

Estado actual: stub. Normaliza la respuesta a 31 valores para reservar el contrato de EQ.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "bands": [0, 0, 0]
}
```

Nota: internamente se recorta o rellena a 31 bandas.

#### `setReverbEnabled({ enabled })`

Estado actual: stub sin `AVAudioUnitReverb` todavía.

Respuesta actual:

```json
{
  "status": "not_implemented",
  "enabled": false
}
```

## 5. Eventos reservados para fases siguientes

Todavía no se emiten eventos reales desde los stubs. El contrato reservado es:

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

## 6. Estructura nativa relacionada

```txt
ios/App/App/NativeAudio/NativeAudioModels.swift
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
ios/App/App/NativeAudio/NowPlayingManager.swift
ios/App/App/NativeAudio/RemoteCommandManager.swift
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
ios/App/App/DSP/EQ31BandProcessor.swift
ios/App/App/DSP/ReverbProcessor.swift
ios/App/App/DSP/AudioLimiter.swift
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
ios/App/App/DSP/EpicenterDSPBridge.h
ios/App/App/DSP/EpicenterDSPBridge.mm
ios/App/App/Plugins/EpicenterNativePlugin.swift
```

## 7. Reglas cumplidas en esta etapa

- No se cambió la UI.
- No se tocó Android.
- No se implementó auto scanner iOS.
- No se implementó ruta de audio WebAudio para iOS.
- No se implementó DSP nativo completo.
- No se sustituyó Epicenter por bass boost genérico.
- Los métodos stub devuelven respuestas controladas y no deberían crashear si son llamados.
