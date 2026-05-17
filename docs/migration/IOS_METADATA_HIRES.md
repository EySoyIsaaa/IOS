# iOS Metadata + Hi-Res

## Objetivo

La biblioteca iOS normaliza los metadatos técnicos importados para que player, mini-player, biblioteca, badges y Now Playing trabajen con el mismo `NativeTrack`.

## Extracción nativa robusta

`NativeTrackImporter` lee los metadatos después de copiar el archivo al sandbox de la app:

- título, artista, álbum y artwork desde `asset.commonMetadata`, `asset.metadata` y todos los `asset.availableMetadataFormats` disponibles (ID3, iTunes, QuickTime, ISO user data u otros formatos que AVFoundation exponga);
- fallback de título desde el nombre original seleccionado por el usuario, sin el UUID del sandbox;
- duración desde `asset.duration`;
- sample rate, bit depth, channel count y codec primero desde `AVAudioFile.fileFormat.streamDescription` y luego desde `AVAssetTrack.formatDescriptions` como fallback;
- bitrate estimado como `sizeBytes * 8 / durationSeconds` cuando la duración es válida.

La lectura de `formatDescriptions` evita `as?`/`as!` problemáticos: valida `CFGetTypeID(...) == CMAudioFormatDescriptionGetTypeID()`, usa `unsafeBitCast` solo después de esa validación y verifica `kCMMediaType_Audio` antes de pedir el `AudioStreamBasicDescription`.

## Artwork

El artwork embebido se valida antes de guardarse:

- `Data` no vacía;
- `UIImage(data:)` debe decodificar correctamente;
- se guarda como `.png` si la firma PNG coincide, o como `.jpg` vía `jpegData(compressionQuality:)`;
- si no decodifica, se omite sin crashear.

`nativeTrackToAppTrack` sigue convirtiendo `albumArtUri` con `Capacitor.convertFileSrc(...)` para que el WebView pueda mostrar carátulas locales.

## Logs temporales fuera del callback de audio

```text
[iOS Metadata] title resolved=...
[iOS Metadata] artist resolved=...
[iOS Metadata] album resolved=...
[iOS Metadata] artwork found=...
[iOS Metadata] artwork bytes=...
[iOS Metadata] sampleRate=...
[iOS Metadata] bitDepth=...
[iOS Metadata] bitrate=...
[iOS Metadata] codec=...
[iOS Metadata] isHiRes=...
```

## Criterios Hi-Res finales

Una pista se marca como Hi-Res solo si cumple uno de estos casos:

1. `bitDepth >= 24` y `sampleRate >= 48000`.
2. `bitDepth` desconocido, `sampleRate >= 88200` y formato lossless real (`lpcm`, `alac`, `flac`, `wav`, `aiff`, `caf`).
3. `bitDepth >= 32`, `sampleRate >= 48000` y formato lossless/LPCM se clasifica como `studio` y también cuenta como material Hi-Res para badges de alta resolución.

No se marca como Hi-Res:

- 16-bit / 44.1 kHz;
- 16-bit / 48 kHz;
- MP3/AAC/M4A común solo por bitrate alto;
- tracks sin bitDepth real salvo que tengan sample rate claramente Hi-Res y formato lossless.

## Quality class

`qualityClass` se persiste desde nativo y el frontend también puede recalcular tiers:

- `studio`: 32-bit/float o superior, sample rate >= 48 kHz y formato lossless/LPCM;
- `hi-res`: 24-bit o superior a >= 48 kHz, o fallback lossless >= 88.2 kHz sin bit depth;
- `cd`: 16-bit / 44.1 kHz;
- `lossless`: formato lossless que no llega a Hi-Res/CD;
- `lossy`: MP3/AAC/formatos comprimidos o bitrate estimado sin bit depth;
- `standard`: metadatos válidos que no entran en los grupos anteriores;
- `unknown`: sin datos técnicos confiables.

## Persistencia

La tabla SQLite agrega `codec TEXT` y `quality_class TEXT`. En bases existentes se ejecutan migraciones `ALTER TABLE`; si la columna ya existe se ignora el error de duplicado.

## Limitaciones

AVAsset no siempre expone bit depth en formatos comprimidos o algunos contenedores. Por seguridad, esos casos no se promueven a Hi-Res a menos que el sample rate sea >= 88.2 kHz y el formato lossless esté identificado.
