# iOS Metadata + Hi-Res

## Objetivo

La biblioteca iOS normaliza los metadatos técnicos importados para que player, mini-player, biblioteca, badges y Now Playing trabajen con el mismo `NativeTrack`.

## Extracción nativa

`NativeTrackImporter` lee los metadatos con `AVURLAsset` después de copiar el archivo al sandbox de la app:

- título, artista, álbum y artwork desde `commonMetadata`;
- duración desde `asset.duration`;
- sample rate, bit depth, channel count y codec desde `CMAudioFormatDescriptionGetStreamBasicDescription`;
- bitrate estimado como `sizeBytes * 8 / durationSeconds` cuando la duración es válida.

La importación registra logs temporales fuera del callback de audio:

```text
[iOS Metadata] title=...
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

No se marca como Hi-Res:

- 16-bit / 44.1 kHz;
- 16-bit / 48 kHz;
- MP3/AAC/M4A común solo por bitrate alto;
- tracks sin bitDepth real salvo que tengan sample rate claramente Hi-Res y formato lossless.

## Separación visual

`shared/audioQuality.ts` separa:

- `hi-res`: muestra logo/badge Hi-Res cuando está disponible;
- `cd`: 16-bit / 44.1 kHz;
- `lossy`: MP3/AAC/formatos comprimidos o bitrate estimado sin bit depth;
- `standard`: metadatos válidos que no entran en los grupos anteriores;
- `unknown`: sin datos técnicos confiables.

## Persistencia

La tabla SQLite agrega `codec TEXT`. En bases existentes se ejecuta `ALTER TABLE tracks ADD COLUMN codec TEXT`; si la columna ya existe se ignora el error de duplicado.

## Limitaciones

AVAsset no siempre expone bit depth para formatos comprimidos o algunos contenedores. Por seguridad, esos casos no se promueven a Hi-Res a menos que el sample rate sea >= 88.2 kHz y el formato sea lossless identificado.
