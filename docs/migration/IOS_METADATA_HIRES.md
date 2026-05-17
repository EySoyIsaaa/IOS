# iOS Metadata Hi-Res

## Objetivo

La app iOS normaliza metadatos técnicos desde la importación nativa para que biblioteca, player, mini-player, badges y `currentTrack` usen los mismos datos de calidad que llegan desde el plugin nativo.

## Extracción nativa

`NativeTrackImporter` copia el archivo al sandbox y extrae:

- `sampleRate`
- `bitDepth`
- `bitrate`
- `channelCount`
- `durationMs`
- `fileExtension`
- título/artista/álbum/artwork desde `AVAsset.commonMetadata`

La lectura técnica ahora usa dos rutas:

1. `AVAudioFile.fileFormat.streamDescription` como fuente preferida para formatos PCM/lossless.
2. `AVAssetTrack.formatDescriptions` como fallback.

El bitrate se estima con tamaño/duración cuando AVFoundation no lo expone de forma directa.

## Logs temporales de importación

Durante importación se emiten logs fuera del callback de audio:

```text
[iOS Metadata] title=...
[iOS Metadata] sampleRate=...
[iOS Metadata] bitDepth=...
[iOS Metadata] bitrate=...
[iOS Metadata] channelCount=...
[iOS Metadata] isHiRes=...
```

## Criterios Hi-Res finales

Una pista es Hi-Res si:

- `bitDepth >= 24` y `sampleRate >= 48000`; o
- `bitDepth` es desconocido, `sampleRate >= 88200` y el contenedor es claramente lossless (`wav`, `wave`, `aif`, `aiff`, `flac`, `alac`, `caf`).

No se marca como Hi-Res si:

- es `16-bit / 44.1 kHz`;
- es `16-bit / 48 kHz`;
- es MP3/AAC/M4A común aunque tenga bitrate alto;
- falta `bitDepth` y el contenedor no es lossless conocido.

## Clases visuales

El frontend clasifica como:

- `hi-res`: muestra logo/badge Hi-Res.
- `cd`: `16-bit / 44.1 kHz`.
- `lossless`: contenedor lossless con datos técnicos, pero sin cumplir Hi-Res.
- `lossy`: MP3/AAC/M4A/OGG/Opus.
- `standard`: datos parciales no Hi-Res.
- `unknown`: sin datos técnicos confiables.

## Artwork y nombres

`nativeTrackToAppTrack` sigue limpiando el sufijo UUID de copias del sandbox para títulos de fallback y convierte artwork local con `Capacitor.convertFileSrc`, por lo que la WebView puede mostrar carátulas locales.

## Limitaciones

AVFoundation no siempre entrega `bitDepth` para formatos comprimidos o algunos contenedores. En esos casos no se inventa bit depth. El fallback por sample rate alto solo aplica a contenedores lossless conocidos para evitar falsos positivos en MP3/AAC.
