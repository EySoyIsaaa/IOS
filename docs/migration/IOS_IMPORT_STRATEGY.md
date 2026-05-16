# Estrategia de importación manual iOS — checkpoint v6

Fecha: 2026-05-16

## Alcance de esta etapa

Esta etapa implementa solo la biblioteca local iOS y la importación manual de canciones. No incluye reproductor nativo, Epicenter DSP, EQ, Concert Hall, auto scanner ni ruta WebAudio para iOS.

## Decisión principal: copiar al sandbox

La importación manual usa `UIDocumentPickerViewController` con `UTType.audio` y selección múltiple. Aunque iOS puede entregar URLs con security-scoped resources, la estrategia estable para la biblioteca es copiar cada archivo seleccionado al sandbox de la app:

```txt
Documents/AudioLibrary
```

Motivos:

- Evita depender de permisos security-scoped a largo plazo para reproducir archivos importados en sesiones futuras.
- Hace que la disponibilidad del track sea predecible mientras el usuario no elimine la app o borre el track desde la biblioteca.
- Simplifica la futura ruta de playback nativo porque el reproductor podrá abrir rutas locales propias de la app.
- Reduce errores con archivos movidos, proveedores externos de documentos o ubicaciones en iCloud no disponibles.

Se guarda también un bookmark del archivo copiado cuando iOS lo permite, pero la ruta preferida de acceso futuro es `localFilePath`.

## Flujo implementado

1. `EpicenterNative.importTracks()` presenta el picker nativo desde el plugin Capacitor.
2. El picker permite seleccionar múltiples documentos de audio con `UTType.audio`.
3. Por cada URL seleccionada:
   - Se abre security-scoped resource con `startAccessingSecurityScopedResource()` si aplica.
   - Se copia el archivo a `Documents/AudioLibrary` usando un nombre único.
   - Se crea un `AVURLAsset` apuntando a la copia sandboxed.
   - Se leen metadatos comunes con `AVAsset`/`AVMetadataItem`:
     - título
     - artista
     - álbum
     - artwork embebido, si existe
   - Se calcula duración en milisegundos.
   - Se obtiene tamaño de archivo y extensión.
   - Se intenta extraer sample rate, bit depth y channel count desde el formato de audio.
   - Se estima bitrate como `sizeBytes * 8 / durationSeconds` cuando la duración es válida.
   - Se crea `stableId` determinístico a partir de `manual-ios`, nombre original, tamaño y duración.
   - Se guarda artwork embebido en `Documents/AudioLibrary/Artwork` cuando existe.
   - Se persiste/upsert el track en la DB local.
4. El plugin resuelve la promesa con los tracks importados.

## Base de datos local

Se usa SQLite directo mediante `SQLite3`, sin dependencias externas. La DB vive en:

```txt
Application Support/NativeLibrary/tracks.sqlite
```

La tabla `tracks` contiene los campos mínimos solicitados por la etapa y prepara índices básicos para búsqueda y ordenamiento.

## Campos persistidos

- `id`
- `stable_id`
- `title`
- `artist`
- `album`
- `duration_ms`
- `file_name`
- `file_extension`
- `source_uri`
- `bookmark_data`
- `local_file_path`
- `source_type` = `manual-ios`
- `added_at`
- `updated_at`
- `size_bytes`
- `sample_rate`
- `bit_depth`
- `bitrate`
- `channel_count`
- `album_art_uri`
- `is_available`
- `play_count`
- `last_played_at`

## API real en esta etapa

Ya son reales:

- `importTracks()`
- `getLibraryPage({ offset, limit, search, sort })`
- `getTrack({ id })`
- `deleteTrack({ id })`

Siguen como stub:

- `getPlaybackState()`
- `play({ trackId? })`
- `pause()`
- `seek({ seconds })`
- `setEpicenterEnabled({ enabled })`
- `setEqBands({ gains })`
- `setReverbEnabled({ enabled })`

## Limitaciones conocidas

- La lectura de metadatos depende de lo que `AVAsset` pueda exponer para cada formato/proveedor.
- `bitDepth` no siempre está disponible para formatos comprimidos.
- `bitrate` se estima por tamaño/duración cuando no se expone directamente.
- La importación continúa con los archivos restantes si un archivo individual falla; los fallos se registran con `NSLog`.
- No hay UI nueva ni rediseño: el contrato nativo queda listo para que la UI existente lo consuma en fases posteriores.
