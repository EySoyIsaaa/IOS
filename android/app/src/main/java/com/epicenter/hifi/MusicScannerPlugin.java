package com.epicenter.hifi;

import android.Manifest;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.ContentUris;
import android.database.Cursor;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.MediaStore;
import android.util.Base64;
import androidx.core.content.ContextCompat;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.File;
import java.io.FileOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.json.JSONArray;
import org.json.JSONObject;

@CapacitorPlugin(
  name = "MusicScanner",
  permissions = {
    @Permission(alias = "audio33", strings = { Manifest.permission.READ_MEDIA_AUDIO }),
    @Permission(alias = "audioLegacy", strings = { Manifest.permission.READ_EXTERNAL_STORAGE })
  }
)
public class MusicScannerPlugin extends Plugin {
  private static final String LIBRARY_PREFS = "epicenter_library";
  private static final String LIBRARY_KEY = "tracks_v1";

  private volatile String cachedLibraryRaw = null;
  private volatile JSArray cachedLibrary = null;
  private static final String ROOM_MIGRATED_KEY = "room_migrated_v1";
  private static final String LAST_FULL_SCAN_COUNT_KEY = "last_full_scan_count_v1";
  private static final int AUDIO_BUFFER_SIZE = 512 * 1024;

  private final ExecutorService audioExecutor = Executors.newSingleThreadExecutor();
  private final ExecutorService dbExecutor = Executors.newSingleThreadExecutor();
  private volatile ServerSocket audioServerSocket;
  private volatile int audioServerPort = -1;
  private final String audioSessionToken = UUID.randomUUID().toString();
  private PowerManager.WakeLock playbackWakeLock;

  private static class AudioFormatInfo {
    Integer bitDepth;
    Integer sampleRate;
    Integer bitrate;
    Integer channels;
  }

  private AudioFormatInfo getAudioFormatInfo(Uri contentUri) {
    AudioFormatInfo info = new AudioFormatInfo();
    MediaMetadataRetriever retriever = new MediaMetadataRetriever();
    MediaExtractor extractor = new MediaExtractor();

    try {
      retriever.setDataSource(getContext(), contentUri);
      String bitrateValue = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE);
      if (bitrateValue != null && !bitrateValue.isEmpty()) {
        info.bitrate = Integer.parseInt(bitrateValue);
      }
    } catch (Exception ignored) {
    }

    try {
      extractor.setDataSource(getContext(), contentUri, null);
      for (int i = 0; i < extractor.getTrackCount(); i++) {
        MediaFormat format = extractor.getTrackFormat(i);
        String mime = format.getString(MediaFormat.KEY_MIME);
        if (mime == null || !mime.startsWith("audio/")) {
          continue;
        }

        if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
          info.sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
        }

        if (info.bitrate == null && format.containsKey(MediaFormat.KEY_BIT_RATE)) {
          info.bitrate = format.getInteger(MediaFormat.KEY_BIT_RATE);
        }
        if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
          info.channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
        }

        if (format.containsKey("bits-per-sample")) {
          info.bitDepth = format.getInteger("bits-per-sample");
        }
        break;
      }
    } catch (Exception ignored) {
    } finally {
      try {
        retriever.release();
      } catch (Exception ignored) {
      }
      try {
        extractor.release();
      } catch (Exception ignored) {
      }
    }

    return info;
  }

  // Directorio de caché para archivos de audio temporales
  private File getAudioCacheDir() {
    File cacheDir = new File(getContext().getFilesDir(), "audio_cache");
    if (!cacheDir.exists()) {
      cacheDir.mkdirs();
    }
    return cacheDir;
  }

  private String getAudioAlias() {
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ? "audio33" : "audioLegacy";
  }

  private boolean hasAudioPermission() {
    String alias = getAudioAlias();
    PermissionState capacitorState = getPermissionState(alias);
    
    int androidState;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        androidState = ContextCompat.checkSelfPermission(getContext(), Manifest.permission.READ_MEDIA_AUDIO);
    } else {
        androidState = ContextCompat.checkSelfPermission(getContext(), Manifest.permission.READ_EXTERNAL_STORAGE);
    }
    boolean androidGranted = androidState == android.content.pm.PackageManager.PERMISSION_GRANTED;
    
    return androidGranted || capacitorState == PermissionState.GRANTED;
  }

  @PluginMethod
  public void requestAudioPermissions(PluginCall call) {
    String alias = getAudioAlias();
    android.util.Log.d("MusicScanner", "Solicitando permisos para alias: " + alias);
    
    if (hasAudioPermission()) {
      android.util.Log.d("MusicScanner", "✅ Permiso ya concedido");
      JSObject result = new JSObject();
      result.put("granted", true);
      call.resolve(result);
    } else {
      android.util.Log.d("MusicScanner", "Solicitando permiso al usuario...");
      requestPermissionForAlias(alias, call, "permissionsCallback");
    }
  }

  @PermissionCallback
  public void permissionsCallback(PluginCall call) {
    boolean granted = hasAudioPermission();
    android.util.Log.d("MusicScanner", "Callback de permisos. Granted: " + granted);
    JSObject result = new JSObject();
    result.put("granted", granted);
    call.resolve(result);
  }

  @PluginMethod
  public void checkPermissions(PluginCall call) {
    boolean granted = hasAudioPermission();
    JSObject result = new JSObject();
    result.put("granted", granted);
    call.resolve(result);
  }

  @PluginMethod
  public void scanMusic(PluginCall call) {
    android.util.Log.d("MusicScanner", "==========================================");
    android.util.Log.d("MusicScanner", "scanMusic() llamado!");
    android.util.Log.d("MusicScanner", "==========================================");
    
    if (!hasAudioPermission()) {
      android.util.Log.e("MusicScanner", "❌ Permiso NO concedido");
      call.reject("Permission not granted");
      return;
    }

    android.util.Log.d("MusicScanner", "✅ Permiso concedido, iniciando escaneo...");

    try {
      JSArray musicFiles = scanMusicFromMediaStore();
      android.util.Log.d("MusicScanner", "✅ Escaneo completado. Archivos encontrados: " + musicFiles.length());
      
      JSObject result = new JSObject();
      result.put("files", musicFiles);
      result.put("count", musicFiles.length());
      call.resolve(result);
    } catch (Exception e) {
      android.util.Log.e("MusicScanner", "❌ Error en escaneo: " + e.getMessage());
      e.printStackTrace();
      call.reject("Error scanning music: " + e.getMessage(), e);
    }
  }

  @PluginMethod
  public void importAutomaticLibrary(PluginCall call) {
    if (!hasAudioPermission()) {
      call.reject("Permission not granted");
      return;
    }

    try {
      migrateSharedPrefsToRoomIfNeeded();
      long now = System.currentTimeMillis() / 1000L;
      android.util.Log.i("MusicScanner", "scanStarted");
      JSArray scanned = scanMusicFromMediaStore();
      int scannedCount = scanned.length();
      android.util.Log.i("MusicScanner", "scanFinished scannedCount=" + scannedCount);

      List<TrackEntity> existing = dao().getAll();
      int existingCount = existing.size();
      android.content.SharedPreferences prefs = getContext().getSharedPreferences(LIBRARY_PREFS, android.content.Context.MODE_PRIVATE);
      int lastFullScanCount = prefs.getInt(LAST_FULL_SCAN_COUNT_KEY, -1);
      String scanCompleteness = "complete";
      String completenessReason = "ok";
      if (existingCount > 0) {
        if (scannedCount == 0) {
          scanCompleteness = "partial";
          completenessReason = "empty_scan";
        } else if (scannedCount < Math.ceil(existingCount * 0.5d)) {
          scanCompleteness = "partial";
          completenessReason = "low_vs_existing";
        }
      } else {
        scanCompleteness = "complete";
        completenessReason = "first_scan";
      }
      if ("complete".equals(scanCompleteness) && lastFullScanCount > 0 && scannedCount < Math.ceil(lastFullScanCount * 0.5d)) {
        scanCompleteness = "partial";
        completenessReason = "low_vs_baseline";
      }
      if (scannedCount < 0) {
        scanCompleteness = "partial";
        completenessReason = "inconsistent_scan";
      }
      final String finalScanCompleteness = scanCompleteness;
      Map<String, TrackEntity> byStable = new HashMap<>();
      for (TrackEntity e : existing) byStable.put(e.stableId, e);

      Set<String> seen = new HashSet<>();
      Set<Long> consumedExistingIds = new HashSet<>();
      AtomicInteger added = new AtomicInteger(0), updated = new AtomicInteger(0), preserved = new AtomicInteger(0), missingCandidates = new AtomicInteger(0), unavailableMarked = new AtomicInteger(0);

      AppDatabase.get(getContext()).runInTransaction(() -> {
        for (int i = 0; i < scanned.length(); i++) {
          JSObject scannedObj;
          try {
            scannedObj = new JSObject(scanned.getJSONObject(i).toString());
          } catch (Exception parseErr) {
            continue;
          }
          TrackEntity incoming = toEntity(scannedObj, now);
          TrackEntity old = byStable.get(incoming.stableId);
          if (old == null) {
            for (TrackEntity candidate : existing) {
              if (consumedExistingIds.contains(candidate.id)) continue;
              if (candidate.duration == incoming.duration &&
                candidate.size == incoming.size &&
                incoming.dateModified > 0 &&
                candidate.dateModified == incoming.dateModified &&
                safeEq(candidate.title, incoming.title) &&
                safeEq(candidate.album, incoming.album) &&
                safeEq(candidate.artist, incoming.artist)) {
                old = candidate;
                break;
              }
            }
          }
          if (old != null) {
            incoming.id = old.id;
            incoming.createdAt = old.createdAt;
            consumedExistingIds.add(old.id);
            updated.incrementAndGet();
          } else {
            incoming.createdAt = now;
            added.incrementAndGet();
          }
          incoming.updatedAt = now;
          incoming.lastSeenAt = now;
          incoming.missingCount = 0;
          incoming.missingSince = null;
          incoming.unavailable = false;
          incoming.unavailableReason = null;
          incoming.scanCompleteness = finalScanCompleteness;
          dao().upsert(incoming);
          seen.add(incoming.stableId);
        }

        for (TrackEntity e : existing) {
          if (!seen.contains(e.stableId)) preserved.incrementAndGet();
        }
      });
      if ("complete".equals(scanCompleteness)) {
        prefs.edit().putInt(LAST_FULL_SCAN_COUNT_KEY, scannedCount).apply();
      }

      int count = dao().countAll();
      android.util.Log.i("MusicScanner", "scanStats scannedCount=" + scannedCount + " existingCount=" + existingCount + " lastFullScanCount=" + lastFullScanCount + " syncAdded=" + added.get() + " syncUpdated=" + updated.get() + " syncPreserved=" + preserved.get() + " scanCompleteness=" + scanCompleteness + " reason=" + completenessReason);
      JSObject result = new JSObject();
      result.put("count", count);
      result.put("added", added.get());
      result.put("updated", updated.get());
      result.put("preserved", preserved.get());
      result.put("missingCandidates", missingCandidates.get());
      result.put("unavailableMarked", unavailableMarked.get());
      result.put("scanCompleteness", scanCompleteness);
      result.put("scanCompletenessReason", completenessReason);
      result.put("success", true);
      call.resolve(result);
    } catch (Exception e) {
      android.util.Log.e("MusicScanner", "scanFailed reason=exception, forcing partial", e);
      JSObject result = new JSObject();
      result.put("count", dao().countAll());
      result.put("added", 0);
      result.put("updated", 0);
      result.put("preserved", 0);
      result.put("missingCandidates", 0);
      result.put("unavailableMarked", 0);
      result.put("scanCompleteness", "partial");
      result.put("scanCompletenessReason", "exception");
      result.put("success", false);
      result.put("error", e.getMessage());
      call.resolve(result);
    }
  }


  @PluginMethod
  public void pickManualAudioTracks(PluginCall call) {
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("audio/*");
    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
    startActivityForResult(call, intent, "pickManualAudioTracksResult");
  }

  @ActivityCallback
  private void pickManualAudioTracksResult(PluginCall call, androidx.activity.result.ActivityResult result) {
    if (call == null) return;
    if (result.getResultCode() != android.app.Activity.RESULT_OK || result.getData() == null) {
      dbExecutor.execute(() -> {
        try {
          JSObject out = new JSObject();
          out.put("count", dao().countAll());
          out.put("changed", 0);
          out.put("records", new JSArray());
          out.put("success", true);
          call.resolve(out);
        } catch (Exception e) {
          call.reject("Error finishing manual picker: " + e.getMessage(), e);
        }
      });
      return;
    }

    Intent data = result.getData();
    List<Uri> uris = new ArrayList<>();
    if (data.getClipData() != null) {
      for (int i = 0; i < data.getClipData().getItemCount(); i++) {
        uris.add(data.getClipData().getItemAt(i).getUri());
      }
    } else if (data.getData() != null) {
      uris.add(data.getData());
    }

    int persistableFlags = data.getFlags() & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
    if ((persistableFlags & Intent.FLAG_GRANT_READ_URI_PERMISSION) == 0) {
      persistableFlags |= Intent.FLAG_GRANT_READ_URI_PERMISSION;
    }
    final int finalPersistableFlags = persistableFlags;
    dbExecutor.execute(() -> {
      try {
        JSArray imported = importManualUris(uris, finalPersistableFlags);
        JSObject out = new JSObject();
        out.put("count", dao().countAll());
        out.put("changed", imported.length());
        out.put("records", imported);
        out.put("success", true);
        call.resolve(out);
      } catch (Exception e) {
        android.util.Log.e("MusicScanner", "manualImportFailed", e);
        call.reject("Error importing picked tracks: " + e.getMessage(), e);
      }
    });
  }

  @PluginMethod
  public void importManualTracks(PluginCall call) {
    JSArray items = call.getArray("items");
    if (items == null || items.length() == 0) {
      call.reject("items is required");
      return;
    }

    dbExecutor.execute(() -> {
      try {
        migrateSharedPrefsToRoomIfNeeded();
        List<Uri> uris = new ArrayList<>();
        for (int i = 0; i < items.length(); i++) {
          JSONObject obj;
          try {
            obj = items.getJSONObject(i);
          } catch (Exception parseErr) {
            continue;
          }
          String contentUri = obj.optString("contentUri", "");
          if (contentUri != null && !contentUri.isEmpty()) uris.add(Uri.parse(contentUri));
        }
        JSArray imported = importManualUris(uris, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        JSObject result = new JSObject();
        result.put("count", dao().countAll());
        result.put("changed", imported.length());
        result.put("records", imported);
        result.put("success", true);
        call.resolve(result);
      } catch (Exception e) {
        android.util.Log.e("MusicScanner", "manualImportFailed", e);
        call.reject("Error importing manual tracks: " + e.getMessage(), e);
      }
    });
  }




  private JSArray importManualUris(List<Uri> uris, int persistableFlags) throws Exception {
    migrateSharedPrefsToRoomIfNeeded();
    long now = System.currentTimeMillis() / 1000L;
    JSArray imported = new JSArray();
    AppDatabase.get(getContext()).runInTransaction(() -> {
      for (Uri uri : uris) {
        if (uri == null) continue;
        if ("content".equalsIgnoreCase(uri.getScheme())) {
          try {
            getContext().getContentResolver().takePersistableUriPermission(uri, persistableFlags);
            android.util.Log.i("MusicScanner", "manualImportPersistedUriPermission uri=" + uri + " flags=" + persistableFlags);
          } catch (Exception permissionError) {
            android.util.Log.w("MusicScanner", "persistUriPermissionFailed uri=" + uri + " flags=" + persistableFlags + " reason=" + permissionError.getMessage());
            if ((persistableFlags & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0 && persistableFlags != Intent.FLAG_GRANT_READ_URI_PERMISSION) {
              try {
                getContext().getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                android.util.Log.i("MusicScanner", "manualImportPersistedUriPermissionReadOnly uri=" + uri);
              } catch (Exception readOnlyPermissionError) {
                android.util.Log.w("MusicScanner", "persistUriPermissionReadOnlyFailed uri=" + uri + " reason=" + readOnlyPermissionError.getMessage());
              }
            }
          }
        }

        JSObject track = buildTrackFromUri(uri);
        if (track == null) continue;
        TrackEntity e = toEntity(track, now);
        e.sourceType = "manual-uri";
        e.mediaStoreId = null;
        e.scanCompleteness = "complete";
        e.createdAt = now;
        e.updatedAt = now;
        e.lastSeenAt = now;
        dao().upsert(e);
        android.util.Log.i("MusicScanner", "manualImportRoomUpsert stableId=" + e.stableId + " sourceType=" + e.sourceType + " sourceUri=" + e.sourceUri + " title=" + e.title);
        imported.put(toJs(e));
      }
    });
    return imported;
  }

  @PluginMethod
  public void deleteTrackById(PluginCall call) {
    String id = call.getString("id");
    if (id == null || id.isEmpty()) {
      call.reject("id is required");
      return;
    }

    try {
      migrateSharedPrefsToRoomIfNeeded();
      TrackEntity found = dao().findByAnyId(id);
      if (found != null) dao().deleteByStableId(found.stableId);
      JSObject result = new JSObject();
      result.put("success", true);
      result.put("count", dao().countAll());
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error deleting track: " + e.getMessage(), e);
    }
  }

  @PluginMethod
  public void clearNativeLibrary(PluginCall call) {
    try {
      migrateSharedPrefsToRoomIfNeeded();
      dao().clearAll();
      JSObject result = new JSObject();
      result.put("success", true);
      result.put("count", 0);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error clearing native library: " + e.getMessage(), e);
    }
  }

  @PluginMethod
  public void getLibraryPage(PluginCall call) {
    int page = call.getInt("page", 1);
    int pageSize = call.getInt("pageSize", 100);
    String search = call.getString("search", "");
    String sortBy = call.getString("sortBy", "title");
    String sortDir = call.getString("sortDir", "asc");

    try {
      migrateSharedPrefsToRoomIfNeeded();
      long queryStart = System.currentTimeMillis();
      int safePage = Math.max(1, page);
      int safePageSize = Math.max(1, Math.min(100, pageSize));
      int offset = (safePage - 1) * safePageSize;
      String normalizedSearch = search == null ? "" : search.trim().toLowerCase();
      boolean desc = "desc".equalsIgnoreCase(sortDir);
      List<TrackEntity> pageRecords = desc
        ? dao().getPageDesc(normalizedSearch, sortBy, safePageSize, offset)
        : dao().getPageAsc(normalizedSearch, sortBy, safePageSize, offset);

      JSArray records = new JSArray();
      for (TrackEntity e : pageRecords) records.put(toJs(e));

      JSObject result = new JSObject();
      result.put("page", safePage);
      result.put("pageSize", safePageSize);
      result.put("total", dao().countFiltered(normalizedSearch));
      result.put("records", records);
      result.put("queryTimeMs", System.currentTimeMillis() - queryStart);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error querying native library: " + e.getMessage(), e);
    }
  }

  @PluginMethod
  public void getTrackById(PluginCall call) {
    String id = call.getString("id");
    if (id == null || id.isEmpty()) {
      call.reject("id is required");
      return;
    }
    try {
      JSObject track = findPersistedTrackById(id);
      if (track == null) {
        call.reject("Track not found");
        return;
      }
      JSObject result = new JSObject();
      result.put("track", track);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error getting track: " + e.getMessage(), e);
    }
  }


  @PluginMethod
  public void acquirePlaybackWakeLock(PluginCall call) {
    String trackId = call.getString("trackId", "unknown");
    try {
      if (playbackWakeLock == null) {
        PowerManager powerManager = (PowerManager) getContext().getSystemService(android.content.Context.POWER_SERVICE);
        playbackWakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "EpicenterHiFi:Playback");
        playbackWakeLock.setReferenceCounted(false);
      }
      boolean wasHeld = playbackWakeLock.isHeld();
      if (!wasHeld) {
        playbackWakeLock.acquire(6 * 60 * 60 * 1000L);
      }
      boolean isHeld = playbackWakeLock.isHeld();
      android.util.Log.i("MusicScanner", "playbackWakeLockAcquire trackId=" + trackId + " wasHeld=" + wasHeld + " isHeld=" + isHeld);
      JSObject result = new JSObject();
      result.put("held", isHeld);
      result.put("wasHeld", wasHeld);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error acquiring playback wake lock: " + e.getMessage(), e);
    }
  }

  @PluginMethod
  public void releasePlaybackWakeLock(PluginCall call) {
    String reason = call.getString("reason", "unknown");
    String trackId = call.getString("trackId", "unknown");
    try {
      boolean wasHeld = releasePlaybackWakeLockInternal(reason, trackId);
      JSObject result = new JSObject();
      result.put("held", playbackWakeLock != null && playbackWakeLock.isHeld());
      result.put("wasHeld", wasHeld);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error releasing playback wake lock: " + e.getMessage(), e);
    }
  }

  private boolean releasePlaybackWakeLockInternal(String reason, String trackId) {
    boolean wasHeld = playbackWakeLock != null && playbackWakeLock.isHeld();
    if (wasHeld) {
      playbackWakeLock.release();
    }
    android.util.Log.i("MusicScanner", "playbackWakeLockRelease reason=" + reason + " trackId=" + trackId + " wasHeld=" + wasHeld + " isHeld=" + (playbackWakeLock != null && playbackWakeLock.isHeld()));
    return wasHeld;
  }

  @Override
  protected void handleOnDestroy() {
    releasePlaybackWakeLockInternal("plugin-destroy", "unknown");
    shutdownAudioServer();
    super.handleOnDestroy();
  }

  private void shutdownAudioServer() {
    try {
      if (audioServerSocket != null && !audioServerSocket.isClosed()) {
        audioServerSocket.close();
      }
    } catch (Exception e) {
      android.util.Log.w("MusicScanner", "audioServerCloseFailed " + e.getMessage());
    } finally {
      audioServerSocket = null;
      audioServerPort = -1;
    }

    try {
      audioExecutor.shutdownNow();
    } catch (Exception e) {
      android.util.Log.w("MusicScanner", "audioExecutorShutdownFailed " + e.getMessage());
    }

    try {
      dbExecutor.shutdownNow();
    } catch (Exception e) {
      android.util.Log.w("MusicScanner", "dbExecutorShutdownFailed " + e.getMessage());
    }
  }

  @PluginMethod
  public void getAudioFileUrlById(PluginCall call) {
    String id = call.getString("id");
    if (id == null || id.isEmpty()) {
      call.reject("id is required");
      return;
    }
    try {
      JSObject track = findPersistedTrackById(id);
      if (track == null) {
        call.reject("Track not found");
        return;
      }
      String contentUri = track.optString("contentUri", null);
      if (contentUri == null || contentUri.isEmpty()) {
        call.reject("Track has no contentUri");
        return;
      }

      JSObject result = getAudioFileUrlInternal(
        contentUri,
        id,
        track.optString("sourceVersionKey", id),
        track.has("size") ? track.optLong("size") : null,
        false
      );
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error getting audio by id: " + e.getMessage(), e);
    }
  }

  /**
   * Copia el archivo de audio a la caché y devuelve una URL accesible
   * Este método es más eficiente para archivos grandes (FLAC, WAV, etc.)
   */
  @PluginMethod
  public void getAudioFileUrl(PluginCall call) {
    String contentUri = call.getString("contentUri");
    String trackId = call.getString("trackId");
    String sourceVersionKey = call.getString("sourceVersionKey");
    Long expectedSize = call.getLong("expectedSize");
    Boolean allowStreamingOpt = call.getBoolean("allowStreaming");
    boolean allowStreaming = false;
    if (Boolean.TRUE.equals(allowStreamingOpt)) {
      android.util.Log.i("MusicScanner", "streamingOptionIgnored allowStreamingRequested=true forced=false");
    }
    
    if (contentUri == null || contentUri.isEmpty()) {
      call.reject("contentUri is required");
      return;
    }
    
    if (trackId == null || trackId.isEmpty()) {
      trackId = String.valueOf(System.currentTimeMillis());
    }

    android.util.Log.d("MusicScanner", "getAudioFileUrl para: " + contentUri);

    try {
      long t0 = System.currentTimeMillis();
      JSObject result = getAudioFileUrlInternal(contentUri, trackId, sourceVersionKey, expectedSize, allowStreaming);
      result.put("audioResolveTimeMs", System.currentTimeMillis() - t0);
      call.resolve(result);
    } catch (Exception e) {
      android.util.Log.e("MusicScanner", "❌ Error obteniendo audio: " + e.getMessage());
      e.printStackTrace();
      call.reject("Error getting audio: " + e.getMessage(), e);
    }
  }

  private JSObject getAudioFileUrlInternal(
    String contentUri,
    String trackId,
    String sourceVersionKey,
    Long expectedSize,
    boolean allowStreaming
  ) throws Exception {
      Uri uri = Uri.parse(contentUri);
      ContentResolver resolver = getContext().getContentResolver();
      
      // Obtener el tipo MIME
      String mimeType = resolver.getType(uri);
      if (mimeType == null) {
        mimeType = "audio/mpeg";
      }
      
      // Determinar la extensión del archivo
      String extension = ".mp3";
      if (mimeType.contains("flac")) {
        extension = ".flac";
      } else if (mimeType.contains("wav")) {
        extension = ".wav";
      } else if (mimeType.contains("aiff")) {
        extension = ".aiff";
      } else if (mimeType.contains("m4a") || mimeType.contains("mp4")) {
        extension = ".m4a";
      } else if (mimeType.contains("ogg")) {
        extension = ".ogg";
      }
      
      long resolveStart = System.currentTimeMillis();
      TrackEntity linked = dao().getByStableId(trackId);
      if (linked == null) linked = dao().getByMediaStoreId(trackId);
      if (linked == null) linked = dao().findBySourceUri(contentUri);
      boolean hasValidSourceUri = contentUri != null && !contentUri.trim().isEmpty();
      String sourceUriScheme = uri.getScheme() != null ? uri.getScheme() : "unknown";
      boolean linkedMatchesRequested =
        linked != null &&
        hasValidSourceUri &&
        linked.sourceUri != null &&
        linked.sourceUri.equals(contentUri);
      boolean linkedIdMatchesRequested =
        linked != null &&
        trackId != null &&
        (trackId.equals(linked.stableId) || trackId.equals(linked.mediaStoreId));
      if (linked != null && !linkedMatchesRequested && linked.cachedFilePath != null && !linked.cachedFilePath.isEmpty()) {
        android.util.Log.w("MusicScanner", "linkedCacheRejected sourceUri mismatch requested=" + contentUri + " linked=" + linked.sourceUri + " linkedStableId=" + linked.stableId);
      }
      if (linkedMatchesRequested && linked.cachedFilePath != null && !linked.cachedFilePath.isEmpty()) {
        File linkedCache = new File(linked.cachedFilePath);
        String rejectReason = null;
        if (!linkedCache.exists()) rejectReason = "missing";
        else if (linkedCache.length() <= 0) rejectReason = "empty";
        else if (expectedSize != null && expectedSize > 0 && linkedCache.length() != expectedSize) rejectReason = "size_mismatch";
        if (rejectReason == null) {
          JSObject fast = new JSObject();
          fast.put("filePath", linkedCache.getAbsolutePath());
          fast.put("resolvedUrl", linkedCache.getAbsolutePath() + "?v=" + (linked.sourceVersionKey != null && !linked.sourceVersionKey.isEmpty() ? sha1(linked.sourceVersionKey) : sha1(linkedCache.getAbsolutePath() + ":" + linkedCache.length())));
          fast.put("mimeType", mimeType);
          fast.put("cached", true);
          fast.put("cacheKey", "linked-fast-path");
          fast.put("resolvedStableId", linked.stableId);
          fast.put("playbackSource", "cache-local-linked");
          fast.put("sourceUriScheme", sourceUriScheme);
          fast.put("playbackResolveTimeMs", System.currentTimeMillis() - resolveStart);
          fast.put("cacheHit", true);
          fast.put("fastPath", true);
          fast.put("copyTimeMs", 0);
          fast.put("copiedBytes", 0);
          fast.put("bufferSize", AUDIO_BUFFER_SIZE);
          fast.put("rejectReason", "");
          android.util.Log.i("MusicScanner", "playbackSource=cache-local-linked sourceUriScheme=" + sourceUriScheme + " playbackResolvedUrl=" + linkedCache.getAbsolutePath() + " playbackResolveTimeMs=" + (System.currentTimeMillis() - resolveStart) + " cacheHit=true copyTimeMs=0 copiedBytes=0 bufferSize=" + AUDIO_BUFFER_SIZE + " fastPath=true rejectReason=");
          return fast;
        }
        android.util.Log.w("MusicScanner", "linkedCacheRejected rejectReason=" + rejectReason + " requested=" + contentUri + " linked=" + linked.sourceUri + " linkedStableId=" + linked.stableId);
      }
      if (linked != null && (sourceVersionKey == null || sourceVersionKey.isEmpty())) {
        sourceVersionKey = linked.sourceVersionKey;
      }
      String stableForCache = linkedMatchesRequested && linked != null ? linked.stableId : sha1(trackId + "|" + contentUri);
      String cacheIdentity = stableForCache + "|" + contentUri + "|" + (sourceVersionKey != null ? sourceVersionKey : trackId);
      String cacheHash = sha1(cacheIdentity);
      android.util.Log.i("MusicScanner", "playbackTrackId=" + trackId + " stableId=" + stableForCache + " sourceUri=" + contentUri + " sourceVersionKey=" + sourceVersionKey + " cacheKey=" + cacheHash + " linkedCachedFilePath=" + (linked != null ? linked.cachedFilePath : ""));

      // Crear archivo en caché
      File cacheDir = getAudioCacheDir();
      File outputFile = new File(cacheDir, "track_" + cacheHash + extension);
      File tempFile = new File(cacheDir, "track_" + cacheHash + extension + ".tmp");
      
      // Si el archivo ya existe en caché, devolverlo directamente
      if (outputFile.exists()) {
        if (linkedMatchesRequested && linked != null && linked.cachedFilePath != null && !linked.cachedFilePath.isEmpty() && !outputFile.getAbsolutePath().equals(linked.cachedFilePath)) {
          android.util.Log.w("MusicScanner", "audioCacheMismatch stableId=" + linked.stableId + " expected=" + outputFile.getAbsolutePath() + " linked=" + linked.cachedFilePath);
          outputFile.delete();
        }
        if (outputFile.length() == 0 || (expectedSize != null && expectedSize > 0 && outputFile.length() != expectedSize)) {
          outputFile.delete();
        } else {
        android.util.Log.d("MusicScanner", "✅ Archivo ya en caché: " + outputFile.getAbsolutePath());
        JSObject result = new JSObject();
        result.put("filePath", outputFile.getAbsolutePath());
        result.put("resolvedUrl", outputFile.getAbsolutePath() + "?v=" + cacheHash);
        result.put("mimeType", mimeType);
        result.put("cached", true);
        result.put("cacheKey", cacheHash);
        result.put("resolvedStableId", stableForCache);
        result.put("playbackSource", "cache-local");
        result.put("sourceUriScheme", sourceUriScheme);
        if (linkedMatchesRequested && linked != null) {
          dao().updateCachePaths(linked.stableId, outputFile.getAbsolutePath(), contentUri, System.currentTimeMillis() / 1000L);
        }
        result.put("playbackResolveTimeMs", System.currentTimeMillis() - resolveStart);
        result.put("cacheHit", true);
        result.put("fastPath", true);
        result.put("copyTimeMs", 0);
        result.put("copiedBytes", 0);
        result.put("bufferSize", AUDIO_BUFFER_SIZE);
        result.put("rejectReason", "");
        android.util.Log.i("MusicScanner", "playbackSource=cache-local sourceUriScheme=" + sourceUriScheme + " playbackResolvedUrl=" + outputFile.getAbsolutePath() + " playbackResolveTimeMs=" + (System.currentTimeMillis() - resolveStart) + " cacheHit=true copyTimeMs=0 copiedBytes=0 bufferSize=" + AUDIO_BUFFER_SIZE + " fastPath=true rejectReason=");
        return result;
        }
      }

      if (allowStreaming && linkedMatchesRequested && linkedIdMatchesRequested && linked != null) {
        ensureAudioServerStarted();
        if (audioServerSocket != null && !audioServerSocket.isClosed() && audioServerPort > 0) {
          String streamUrl = "http://127.0.0.1:" + audioServerPort + "/audio/" + URLEncoder.encode(linked.stableId, "UTF-8") + "?token=" + URLEncoder.encode(audioSessionToken, "UTF-8") + "&sourceUri=" + URLEncoder.encode(contentUri, "UTF-8") + "&v=" + cacheHash;
          JSObject stream = new JSObject();
          stream.put("streamUrl", streamUrl);
          stream.put("resolvedUrl", streamUrl);
          stream.put("mimeType", mimeType);
          stream.put("cached", false);
          stream.put("cacheKey", cacheHash);
          stream.put("resolvedStableId", linked.stableId);
          stream.put("playbackSource", "localhost-stream");
          stream.put("sourceUriScheme", sourceUriScheme);
          stream.put("playbackResolveTimeMs", System.currentTimeMillis() - resolveStart);
          stream.put("cacheHit", false);
          stream.put("fastPath", true);
          stream.put("copyTimeMs", 0);
          stream.put("copiedBytes", 0);
          stream.put("bufferSize", AUDIO_BUFFER_SIZE);
          stream.put("sourceUriMatches", true);
          stream.put("stableIdMatches", true);
          stream.put("audioServerPort", audioServerPort);
          stream.put("rejectReason", "streaming_no_cache");
          android.util.Log.i("MusicScanner", "playbackSource=localhost-stream sourceUriScheme=" + sourceUriScheme + " playbackResolvedUrl=" + streamUrl + " playbackResolveTimeMs=" + (System.currentTimeMillis() - resolveStart) + " cacheHit=false copyTimeMs=0 copiedBytes=0 bufferSize=" + AUDIO_BUFFER_SIZE + " fastPath=true rejectReason=streaming_no_cache sourceUriMatches=true stableIdMatches=true audioServerPort=" + audioServerPort);
          return stream;
        }
        android.util.Log.w("MusicScanner", "streamingRejected reason=audio_server_not_active stableId=" + linked.stableId + " sourceUri=" + contentUri);
      } else if (allowStreaming) {
        android.util.Log.w("MusicScanner", "streamingRejected reason=guards_failed hasValidSourceUri=" + hasValidSourceUri + " sourceUriMatches=" + linkedMatchesRequested + " stableIdMatches=" + linkedIdMatchesRequested + " trackId=" + trackId + " linkedStableId=" + (linked != null ? linked.stableId : ""));
      } else {
        android.util.Log.i("MusicScanner", "streamingDisabled allowStreaming=false trackId=" + trackId + " sourceUriScheme=" + sourceUriScheme + " playbackWillUse=cache-local");
      }
      
      // Copiar archivo desde content:// a caché (1 retry simple)
      InputStream inputStream = resolver.openInputStream(uri);
      if (inputStream == null) {
        outputFile.delete();
        tempFile.delete();
        inputStream = resolver.openInputStream(uri);
      }
      if (inputStream == null) {
        if (linkedMatchesRequested && linked != null) dao().markPlaybackError(linked.stableId, true, true, "open_input_stream_failed", System.currentTimeMillis() / 1000L);
        android.util.Log.e("MusicScanner", "playbackErrorReason=open_input_stream_failed stableId=" + stableForCache);
        throw new Exception("Could not open audio file");
      }

      if (tempFile.exists()) {
        tempFile.delete();
      }

      long copyStart = System.currentTimeMillis();
      InputStream rawInput = inputStream;
      InputStream bufferedInput = new BufferedInputStream(rawInput, AUDIO_BUFFER_SIZE);
      OutputStream outputStream = new BufferedOutputStream(new FileOutputStream(tempFile), AUDIO_BUFFER_SIZE);
      byte[] buffer = new byte[AUDIO_BUFFER_SIZE];
      int bytesRead;
      long totalBytes = 0;
      
      while ((bytesRead = bufferedInput.read(buffer)) != -1) {
        outputStream.write(buffer, 0, bytesRead);
        totalBytes += bytesRead;
      }
      
      bufferedInput.close();
      outputStream.close();
      long copyTimeMs = System.currentTimeMillis() - copyStart;

      if (totalBytes <= 0) {
        tempFile.delete();
        throw new Exception("Copied file is empty");
      }

      if (expectedSize != null && expectedSize > 0 && totalBytes != expectedSize) {
        tempFile.delete();
        throw new Exception("Copied file size mismatch");
      }

      if (outputFile.exists()) {
        outputFile.delete();
      }

      if (!tempFile.renameTo(outputFile)) {
        tempFile.delete();
        throw new Exception("Could not finalize cached file");
      }

      android.util.Log.d("MusicScanner", "✅ Archivo copiado a caché: " + outputFile.getAbsolutePath() + " (" + totalBytes + " bytes)");

      JSObject result = new JSObject();
      result.put("filePath", outputFile.getAbsolutePath());
      result.put("resolvedUrl", outputFile.getAbsolutePath() + "?v=" + cacheHash);
      result.put("mimeType", mimeType);
      result.put("size", totalBytes);
      result.put("cached", false);
      result.put("cacheKey", cacheHash);
      result.put("resolvedStableId", stableForCache);
      result.put("playbackSource", "cache-local-copy");
      result.put("sourceUriScheme", sourceUriScheme);
      if (linkedMatchesRequested && linked != null) {
        dao().updateCachePaths(linked.stableId, outputFile.getAbsolutePath(), contentUri, System.currentTimeMillis() / 1000L);
      }
      if (linkedMatchesRequested && linked != null) dao().markPlaybackError(linked.stableId, false, false, null, System.currentTimeMillis() / 1000L);
      result.put("playbackResolveTimeMs", System.currentTimeMillis() - resolveStart);
      result.put("cacheHit", false);
      result.put("fastPath", false);
      result.put("copyTimeMs", copyTimeMs);
      result.put("copiedBytes", totalBytes);
      result.put("bufferSize", AUDIO_BUFFER_SIZE);
      result.put("rejectReason", "copied_to_cache");
      android.util.Log.i("MusicScanner", "playbackSource=cache-local-copy sourceUriScheme=" + sourceUriScheme + " playbackResolvedUrl=" + outputFile.getAbsolutePath() + " playbackResolveTimeMs=" + (System.currentTimeMillis() - resolveStart) + " cacheHit=false copyTimeMs=" + copyTimeMs + " copiedBytes=" + totalBytes + " bufferSize=" + AUDIO_BUFFER_SIZE + " fastPath=false rejectReason=copied_to_cache");
      return result;
  }


  @PluginMethod
  public void prepareAudioFileUrl(PluginCall call) {
    String contentUri = call.getString("contentUri");
    String trackId = call.getString("trackId");
    String sourceVersionKey = call.getString("sourceVersionKey");
    Long expectedSize = call.getLong("expectedSize");

    if (contentUri == null || contentUri.isEmpty()) {
      call.reject("contentUri is required");
      return;
    }
    if (trackId == null || trackId.isEmpty()) {
      call.reject("trackId is required");
      return;
    }

    JSObject queued = new JSObject();
    queued.put("queued", true);
    call.resolve(queued);
    audioExecutor.execute(() -> {
      try {
        long t0 = System.currentTimeMillis();
        JSObject result = getAudioFileUrlInternal(contentUri, trackId, sourceVersionKey, expectedSize, false);
        String filePath = result.getString("filePath");
        if (filePath != null && !filePath.isEmpty()) {
          getContext().getSharedPreferences(LIBRARY_PREFS, android.content.Context.MODE_PRIVATE)
            .edit()
            .putString("next_cached_file_path", filePath)
            .apply();
        }
        android.util.Log.i("MusicScanner", "prepareAudioFileUrlDone trackId=" + trackId + " elapsedMs=" + (System.currentTimeMillis() - t0) + " filePath=" + filePath);
      } catch (Exception e) {
        android.util.Log.w("MusicScanner", "prepareAudioFileUrlFailed trackId=" + trackId + " reason=" + e.getMessage());
      }
    });
  }

  private synchronized void ensureAudioServerStarted() throws Exception {
    if (audioServerSocket != null && !audioServerSocket.isClosed() && audioServerPort > 0) return;
    audioServerSocket = new ServerSocket(0, 16, java.net.InetAddress.getByName("127.0.0.1"));
    audioServerPort = audioServerSocket.getLocalPort();
    Thread serverThread = new Thread(() -> {
      while (audioServerSocket != null && !audioServerSocket.isClosed()) {
        try {
          Socket socket = audioServerSocket.accept();
          new Thread(() -> handleAudioHttpClient(socket), "EpicenterAudioClient").start();
        } catch (Exception e) {
          if (audioServerSocket != null && !audioServerSocket.isClosed()) {
            android.util.Log.w("MusicScanner", "audioServerAcceptFailed " + e.getMessage());
          }
        }
      }
    }, "EpicenterAudioServer");
    serverThread.setDaemon(true);
    serverThread.start();
    android.util.Log.i("MusicScanner", "audioServerStarted port=" + audioServerPort);
  }

  private void handleAudioHttpClient(Socket socket) {
    try {
      socket.setSoTimeout(30000);
      BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream()));
      String requestLine = reader.readLine();
      if (requestLine == null) {
        writeHttpError(socket, 400, "Bad Request");
        return;
      }
      if (requestLine.startsWith("OPTIONS ")) {
        writeHttpOptions(socket);
        return;
      }
      if (!requestLine.startsWith("GET ")) {
        writeHttpError(socket, 405, "Method Not Allowed");
        return;
      }
      String[] requestParts = requestLine.split(" ");
      if (requestParts.length < 2) {
        writeHttpError(socket, 400, "Bad Request");
        return;
      }
      String target = requestParts[1];
      String rangeHeader = null;
      String line;
      while ((line = reader.readLine()) != null && line.length() > 0) {
        int colon = line.indexOf(':');
        if (colon > 0 && line.substring(0, colon).trim().equalsIgnoreCase("Range")) {
          rangeHeader = line.substring(colon + 1).trim();
        }
      }

      int q = target.indexOf('?');
      String path = q >= 0 ? target.substring(0, q) : target;
      Map<String, String> query = parseQuery(q >= 0 ? target.substring(q + 1) : "");
      if (!audioSessionToken.equals(query.get("token"))) {
        writeHttpError(socket, 403, "Forbidden");
        return;
      }
      if (!path.startsWith("/audio/")) {
        writeHttpError(socket, 404, "Not Found");
        return;
      }
      String stableId = URLDecoder.decode(path.substring("/audio/".length()), "UTF-8");
      String requestedSourceUri = query.get("sourceUri");
      TrackEntity entity = dao().getByStableId(stableId);
      if (entity == null || entity.sourceUri == null || requestedSourceUri == null || !entity.sourceUri.equals(requestedSourceUri)) {
        writeHttpError(socket, 404, "Not Found");
        return;
      }

      Uri uri = Uri.parse(entity.sourceUri);
      ContentResolver resolver = getContext().getContentResolver();
      String mimeType = resolver.getType(uri);
      if (mimeType == null || mimeType.isEmpty()) mimeType = entity.mimeType != null ? entity.mimeType : "audio/mpeg";
      long size = entity.size > 0 ? entity.size : -1;
      HttpRange range;
      try {
        range = parseRange(rangeHeader, size);
      } catch (IllegalArgumentException rangeError) {
        writeRangeNotSatisfiable(socket, size);
        return;
      }
      long contentLength = range.contentLength;

      InputStream input = resolver.openInputStream(uri);
      if (input == null) {
        writeHttpError(socket, 404, "Not Found");
        return;
      }
      input = new BufferedInputStream(input, AUDIO_BUFFER_SIZE);
      skipFully(input, range.start);
      PrintWriter writer = new PrintWriter(socket.getOutputStream(), false);
      writer.print("HTTP/1.1 " + (range.partial ? "206 Partial Content" : "200 OK") + "\r\n");
      writer.print("Content-Type: " + mimeType + "\r\n");
      writeCorsHeaders(writer);
      writer.print("Accept-Ranges: bytes\r\n");
      if (contentLength >= 0) writer.print("Content-Length: " + contentLength + "\r\n");
      if (range.partial && size > 0) writer.print("Content-Range: bytes " + range.start + "-" + range.end + "/" + size + "\r\n");
      writer.print("Connection: close\r\n\r\n");
      writer.flush();

      byte[] buffer = new byte[AUDIO_BUFFER_SIZE];
      long remaining = contentLength;
      int read;
      OutputStream out = socket.getOutputStream();
      while ((contentLength < 0 || remaining > 0) && (read = input.read(buffer, 0, contentLength < 0 ? buffer.length : (int)Math.min(buffer.length, remaining))) != -1) {
        out.write(buffer, 0, read);
        if (contentLength >= 0) remaining -= read;
      }
      out.flush();
      input.close();
    } catch (Exception e) {
      android.util.Log.w("MusicScanner", "audioServerClientFailed " + e.getMessage());
    } finally {
      try { socket.close(); } catch (Exception ignored) {}
    }
  }

  private static class HttpRange {
    long start;
    long end;
    long contentLength;
    boolean partial;
  }

  private HttpRange parseRange(String rangeHeader, long size) {
    HttpRange range = new HttpRange();
    range.start = 0;
    range.end = size > 0 ? size - 1 : -1;
    range.contentLength = size > 0 ? size : -1;
    range.partial = false;

    if (rangeHeader == null || rangeHeader.trim().isEmpty()) {
      return range;
    }

    String trimmed = rangeHeader.trim();
    if (!trimmed.startsWith("bytes=") || trimmed.indexOf(',') >= 0 || size <= 0) {
      throw new IllegalArgumentException("invalid_range");
    }

    String spec = trimmed.substring("bytes=".length()).trim();
    int dash = spec.indexOf('-');
    if (dash < 0 || spec.indexOf('-', dash + 1) >= 0) {
      throw new IllegalArgumentException("invalid_range");
    }

    String startPart = spec.substring(0, dash).trim();
    String endPart = spec.substring(dash + 1).trim();
    if (startPart.isEmpty() && endPart.isEmpty()) {
      throw new IllegalArgumentException("invalid_range");
    }

    try {
      if (startPart.isEmpty()) {
        long suffixLength = Long.parseLong(endPart);
        if (suffixLength <= 0) throw new IllegalArgumentException("invalid_range");
        range.start = suffixLength >= size ? 0 : size - suffixLength;
        range.end = size - 1;
      } else {
        range.start = Long.parseLong(startPart);
        if (range.start < 0 || range.start >= size) throw new IllegalArgumentException("invalid_range");
        range.end = endPart.isEmpty() ? size - 1 : Long.parseLong(endPart);
        if (range.end < range.start) throw new IllegalArgumentException("invalid_range");
        if (range.end >= size) range.end = size - 1;
      }
    } catch (NumberFormatException e) {
      throw new IllegalArgumentException("invalid_range", e);
    }

    range.contentLength = range.end - range.start + 1;
    if (range.contentLength <= 0) {
      throw new IllegalArgumentException("invalid_range");
    }
    range.partial = true;
    return range;
  }

  private Map<String, String> parseQuery(String query) throws Exception {
    Map<String, String> params = new HashMap<>();
    if (query == null || query.isEmpty()) return params;
    for (String part : query.split("&")) {
      int eq = part.indexOf('=');
      String key = eq >= 0 ? part.substring(0, eq) : part;
      String value = eq >= 0 ? part.substring(eq + 1) : "";
      params.put(URLDecoder.decode(key, "UTF-8"), URLDecoder.decode(value, "UTF-8"));
    }
    return params;
  }

  private void skipFully(InputStream input, long bytes) throws Exception {
    long remaining = bytes;
    while (remaining > 0) {
      long skipped = input.skip(remaining);
      if (skipped <= 0) {
        if (input.read() == -1) throw new Exception("Unable to skip range");
        skipped = 1;
      }
      remaining -= skipped;
    }
  }

  private void writeRangeNotSatisfiable(Socket socket, long size) throws Exception {
    PrintWriter writer = new PrintWriter(socket.getOutputStream(), false);
    writer.print("HTTP/1.1 416 Range Not Satisfiable\r\n");
    writeCorsHeaders(writer);
    writer.print("Accept-Ranges: bytes\r\n");
    writer.print("Content-Range: bytes */" + (size > 0 ? String.valueOf(size) : "*") + "\r\n");
    writer.print("Content-Length: 0\r\n");
    writer.print("Connection: close\r\n\r\n");
    writer.flush();
  }

  private void writeHttpOptions(Socket socket) throws Exception {
    PrintWriter writer = new PrintWriter(socket.getOutputStream(), false);
    writer.print("HTTP/1.1 204 No Content\r\n");
    writeCorsHeaders(writer);
    writer.print("Content-Length: 0\r\n");
    writer.print("Connection: close\r\n\r\n");
    writer.flush();
  }

  private void writeCorsHeaders(PrintWriter writer) {
    writer.print("Access-Control-Allow-Origin: *\r\n");
    writer.print("Access-Control-Allow-Methods: GET, OPTIONS\r\n");
    writer.print("Access-Control-Allow-Headers: Range, Origin, Accept, Content-Type\r\n");
    writer.print("Access-Control-Expose-Headers: Accept-Ranges, Content-Length, Content-Range, Content-Type\r\n");
  }

  private void writeHttpError(Socket socket, int code, String message) throws Exception {
    PrintWriter writer = new PrintWriter(socket.getOutputStream(), false);
    writer.print("HTTP/1.1 " + code + " " + message + "\r\n");
    writeCorsHeaders(writer);
    writer.print("Content-Type: text/plain\r\n");
    writer.print("Content-Length: 0\r\n");
    writer.print("Connection: close\r\n\r\n");
    writer.flush();
  }

  private String sha1(String value) {
    try {
      MessageDigest md = MessageDigest.getInstance("SHA-1");
      byte[] digest = md.digest(value.getBytes());
      StringBuilder sb = new StringBuilder();
      for (byte b : digest) {
        sb.append(String.format("%02x", b));
      }
      return sb.toString();
    } catch (Exception e) {
      return String.valueOf(value.hashCode());
    }
  }

  /**
   * Limpia la caché de archivos de audio
   */
  @PluginMethod
  public void clearAudioCache(PluginCall call) {
    try {
      File cacheDir = getAudioCacheDir();
      android.content.SharedPreferences prefs = getContext().getSharedPreferences(LIBRARY_PREFS, android.content.Context.MODE_PRIVATE);
      String activeProtectedPath = prefs.getString("active_cached_file_path", "");
      String queuedProtectedPath = prefs.getString("next_cached_file_path", "");
      Set<String> protectedCachePaths = new HashSet<>();
      if (activeProtectedPath != null && !activeProtectedPath.isEmpty()) protectedCachePaths.add(activeProtectedPath);
      if (queuedProtectedPath != null && !queuedProtectedPath.isEmpty()) protectedCachePaths.add(queuedProtectedPath);
      for (TrackEntity e : dao().getAll()) {
        if (e.cachedFilePath != null && !e.cachedFilePath.isEmpty()) protectedCachePaths.add(e.cachedFilePath);
        if (e.localUri != null && e.localUri.startsWith("/")) protectedCachePaths.add(e.localUri);
      }
      if (cacheDir.exists()) {
        Set<String> protectedPaths = new HashSet<>();
        String currentPath = call.getString("currentFilePath");
        String nextPath = call.getString("nextFilePath");
        if (currentPath != null && !currentPath.isEmpty()) protectedPaths.add(currentPath);
        if (nextPath != null && !nextPath.isEmpty()) protectedPaths.add(nextPath);
        for (TrackEntity e : dao().getAll()) {
          if (e.cachedFilePath != null && !e.cachedFilePath.isEmpty()) protectedPaths.add(e.cachedFilePath);
          if (e.localUri != null && e.localUri.startsWith("/")) protectedPaths.add(e.localUri);
        }
        File[] files = cacheDir.listFiles();
        if (files != null) {
          for (File file : files) {
            if (!protectedCachePaths.contains(file.getAbsolutePath())) file.delete();
          }
        }
      }
      android.util.Log.d("MusicScanner", "✅ Caché de audio limpiada");
      JSObject result = new JSObject();
      result.put("success", true);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Error clearing cache: " + e.getMessage(), e);
    }
  }

  /**
   * Obtiene la carátula del álbum como data URL (las imágenes son pequeñas, está bien usar base64)
   */
  @PluginMethod
  public void getAlbumArt(PluginCall call) {
    String albumArtUri = call.getString("albumArtUri");
    if (albumArtUri == null || albumArtUri.isEmpty()) {
      JSObject result = new JSObject();
      result.put("dataUrl", (String) null);
      call.resolve(result);
      return;
    }

    try {
      Uri uri = Uri.parse(albumArtUri);
      ContentResolver resolver = getContext().getContentResolver();
      
      InputStream inputStream = resolver.openInputStream(uri);
      if (inputStream == null) {
        JSObject result = new JSObject();
        result.put("dataUrl", (String) null);
        call.resolve(result);
        return;
      }

      ByteArrayOutputStream byteBuffer = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int len;
      while ((len = inputStream.read(buffer)) != -1) {
        byteBuffer.write(buffer, 0, len);
      }
      inputStream.close();

      byte[] imageBytes = byteBuffer.toByteArray();
      String base64Image = Base64.encodeToString(imageBytes, Base64.NO_WRAP);
      String dataUrl = "data:image/jpeg;base64," + base64Image;

      JSObject result = new JSObject();
      result.put("dataUrl", dataUrl);
      call.resolve(result);
    } catch (Exception e) {
      android.util.Log.w("MusicScanner", "No se pudo obtener carátula: " + e.getMessage());
      JSObject result = new JSObject();
      result.put("dataUrl", (String) null);
      call.resolve(result);
    }
  }


  private TrackDao dao() {
    return AppDatabase.get(getContext()).trackDao();
  }

  private String stableIdFrom(JSObject track) {
    String mediaStoreId = track.optString("mediaStoreId", track.optString("id", ""));
    String sourceUri = track.optString("contentUri", track.optString("sourceUri", ""));
    return sha1(mediaStoreId + "|" + sourceUri);
  }

  private boolean safeEq(String a, String b) {
    String la = a == null ? "" : a.trim().toLowerCase();
    String lb = b == null ? "" : b.trim().toLowerCase();
    return la.equals(lb);
  }

  private TrackEntity toEntity(JSObject track, long now) {
    TrackEntity e = new TrackEntity();
    e.stableId = stableIdFrom(track);
    e.mediaStoreId = track.optString("mediaStoreId", track.optString("id", null));
    e.sourceUri = track.optString("contentUri", track.optString("sourceUri", null));
    e.localUri = null;
    e.cachedFilePath = null;
    e.title = track.optString("title", track.optString("name", "Unknown"));
    e.artist = track.optString("artist", "Unknown Artist");
    e.album = track.optString("album", "Unknown Album");
    e.duration = track.optLong("duration", 0L);
    e.size = track.optLong("size", 0L);
    e.dateModified = track.optLong("dateModified", 0L);
    e.mimeType = track.optString("mimeType", "audio/mpeg");
    String name = track.optString("name", "");
    int dot = name.lastIndexOf('.');
    e.extension = dot > 0 ? name.substring(dot + 1).toLowerCase() : "";
    e.sourceType = "media-store";
    e.sourceVersionKey = track.optString("sourceVersionKey", (e.mediaStoreId != null ? e.mediaStoreId : "") + ":" + e.size + ":" + e.dateModified);
    if (track.has("albumId")) e.albumId = track.optLong("albumId");
    e.albumArtUri = track.optString("albumArtUri", null);
    if (track.has("bitDepth")) e.bitDepth = track.optInt("bitDepth");
    if (track.has("sampleRate")) e.sampleRate = track.optInt("sampleRate");
    if (track.has("bitrate")) e.bitrate = track.optInt("bitrate");
    if (track.has("channels")) e.channels = track.optInt("channels");
    if (track.has("isHiRes")) e.isHiRes = track.optBoolean("isHiRes");
    e.unavailable = track.optBoolean("unavailable", false);
    e.unavailableReason = track.optString("unavailableReason", null);
    e.lastSeenAt = track.optLong("lastSeenAt", now);
    long ms = track.optLong("missingSince", 0L);
    e.missingSince = ms > 0 ? ms : null;
    e.missingCount = track.optInt("missingCount", 0);
    e.scanCompleteness = track.optString("scanCompleteness", "complete");
    e.createdAt = track.optLong("createdAt", now);
    e.updatedAt = now;
    return e;
  }

  private JSObject toJs(TrackEntity e) {
    JSObject o = new JSObject();
    o.put("id", e.stableId);
    o.put("stableId", e.stableId);
    o.put("mediaStoreId", e.mediaStoreId);
    o.put("contentUri", e.sourceUri);
    o.put("sourceUri", e.sourceUri);
    o.put("sourceType", e.sourceType);
    o.put("name", e.title);
    o.put("title", e.title);
    o.put("artist", e.artist);
    o.put("album", e.album);
    o.put("duration", e.duration);
    o.put("size", e.size);
    o.put("mimeType", e.mimeType);
    o.put("dateModified", e.dateModified);
    o.put("sourceVersionKey", e.sourceVersionKey);
    o.put("albumId", e.albumId);
    if (e.albumArtUri != null && !e.albumArtUri.isEmpty()) {
      o.put("albumArtUri", e.albumArtUri);
    } else if (e.albumId != null && e.albumId > 0) {
      o.put("albumArtUri", "content://media/external/audio/albumart/" + e.albumId);
    } else {
      o.put("albumArtUri", (String) null);
    }
    if (e.bitDepth != null) o.put("bitDepth", e.bitDepth);
    if (e.sampleRate != null) o.put("sampleRate", e.sampleRate);
    if (e.bitrate != null) o.put("bitrate", e.bitrate);
    if (e.channels != null) o.put("channels", e.channels);
    if (e.isHiRes != null) o.put("isHiRes", e.isHiRes);
    o.put("unavailable", e.unavailable);
    o.put("unavailableReason", e.unavailableReason);
    o.put("lastSeenAt", e.lastSeenAt);
    o.put("missingSince", e.missingSince != null ? e.missingSince : 0);
    o.put("missingCount", e.missingCount);
    o.put("scanCompleteness", e.scanCompleteness);
    return o;
  }

  private synchronized void migrateSharedPrefsToRoomIfNeeded() {
    android.content.SharedPreferences prefs = getContext().getSharedPreferences(LIBRARY_PREFS, android.content.Context.MODE_PRIVATE);
    if (prefs.getBoolean(ROOM_MIGRATED_KEY, false)) return;
    try {
      android.util.Log.i("MusicScanner", "migrationStarted");
      JSArray old = loadLegacySharedPrefsLibrary();
      int oldCount = old.length();
      android.util.Log.i("MusicScanner", "oldTracksCount=" + oldCount);
      long now = System.currentTimeMillis() / 1000L;
      List<TrackEntity> entities = new java.util.ArrayList<>();
      for (int i = 0; i < old.length(); i++) entities.add(toEntity(new JSObject(old.getJSONObject(i).toString()), now));
      AppDatabase db = AppDatabase.get(getContext());
      db.runInTransaction(() -> {
        if (!entities.isEmpty()) dao().upsertAll(entities);
      });
      int migrated = dao().countAll();
      android.util.Log.i("MusicScanner", "migratedCount=" + migrated);
      if (oldCount > 0 && migrated < oldCount) {
        android.util.Log.e("MusicScanner", "migrationFailed: migratedCount < oldTracksCount");
        return;
      }
      prefs.edit().putBoolean(ROOM_MIGRATED_KEY, true).apply();
      android.util.Log.i("MusicScanner", "migrationCompleted");
    } catch (Exception e) {
      android.util.Log.e("MusicScanner", "migrationFailed", e);
    }
  }

  private JSArray scanMusicFromMediaStore() {
    JSArray musicFiles = new JSArray();
    ContentResolver resolver = getContext().getContentResolver();

    Uri collection;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL);
    } else {
      collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
    }

    String[] projection = {
      MediaStore.Audio.Media._ID,
      MediaStore.Audio.Media.DISPLAY_NAME,
      MediaStore.Audio.Media.TITLE,
      MediaStore.Audio.Media.ARTIST,
      MediaStore.Audio.Media.ALBUM,
      MediaStore.Audio.Media.DURATION,
      MediaStore.Audio.Media.SIZE,
      MediaStore.Audio.Media.MIME_TYPE,
      MediaStore.Audio.Media.ALBUM_ID,
      MediaStore.Audio.Media.DATE_MODIFIED
    };

    // NO filtrar por IS_MUSIC para incluir archivos Hi-Res
    String selection = null;
    String sortOrder = MediaStore.Audio.Media.TITLE + " ASC";

    Cursor cursor = resolver.query(collection, projection, selection, null, sortOrder);

    if (cursor == null) {
      return musicFiles;
    }

    if (cursor.getCount() == 0) {
      cursor.close();
      return musicFiles;
    }

    try {
      int idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID);
      int nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME);
      int titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE);
      int artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST);
      int albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM);
      int durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION);
      int sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE);
      int mimeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE);
      int albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID);
      int dateModifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED);

      while (cursor.moveToNext()) {
        long id = cursor.getLong(idColumn);
        String name = cursor.getString(nameColumn);
        String title = cursor.getString(titleColumn);
        String artist = cursor.getString(artistColumn);
        String album = cursor.getString(albumColumn);
        long duration = cursor.getLong(durationColumn);
        long size = cursor.getLong(sizeColumn);
        String mimeType = cursor.getString(mimeColumn);
        long albumId = cursor.getLong(albumIdColumn);
        long dateModified = cursor.getLong(dateModifiedColumn);

        // Filtrar solo archivos de audio válidos
        if (mimeType == null || !mimeType.startsWith("audio/")) {
          continue;
        }

        Uri contentUri = ContentUris.withAppendedId(collection, id);
        Uri albumArtUri = ContentUris.withAppendedId(
          Uri.parse("content://media/external/audio/albumart"),
          albumId
        );
        AudioFormatInfo formatInfo = getAudioFormatInfo(contentUri);

        // Detectar si es Hi-Res basado en el formato
        boolean isHiRes = false;
        if (formatInfo.bitDepth != null && formatInfo.sampleRate != null) {
          isHiRes = formatInfo.bitDepth >= 16 && formatInfo.sampleRate >= 44100;
        } else if (mimeType != null) {
          isHiRes = mimeType.contains("flac") || 
                    mimeType.contains("wav") || 
                    mimeType.contains("aiff") ||
                    mimeType.contains("alac") ||
                    mimeType.contains("dsd");
        }

        JSObject fileObj = new JSObject();
        fileObj.put("id", String.valueOf(id));
        fileObj.put("name", name != null ? name : "Unknown");
        fileObj.put("title", title != null && !title.isEmpty() ? title : (name != null ? name : "Unknown"));
        fileObj.put("artist", artist != null && !artist.isEmpty() ? artist : "Unknown Artist");
        fileObj.put("album", album != null && !album.isEmpty() ? album : "Unknown Album");
        fileObj.put("duration", duration / 1000);
        fileObj.put("size", size);
        fileObj.put("mimeType", mimeType != null ? mimeType : "audio/mpeg");
        fileObj.put("contentUri", contentUri.toString());
        fileObj.put("albumArtUri", albumArtUri.toString());
        fileObj.put("albumId", albumId);
        fileObj.put("dateModified", dateModified);
        fileObj.put("sourceVersionKey", id + ":" + size + ":" + dateModified);
        if (formatInfo.bitDepth != null) fileObj.put("bitDepth", formatInfo.bitDepth);
        if (formatInfo.sampleRate != null) fileObj.put("sampleRate", formatInfo.sampleRate);
        if (formatInfo.bitrate != null) fileObj.put("bitrate", formatInfo.bitrate);
        if (formatInfo.channels != null) fileObj.put("channels", formatInfo.channels);
        fileObj.put("isHiRes", isHiRes);

        musicFiles.put(fileObj);
      }
    } finally {
      cursor.close();
    }

    return musicFiles;
  }

  private void persistLibrary(JSArray tracks) throws Exception {
    migrateSharedPrefsToRoomIfNeeded();
    long now = System.currentTimeMillis() / 1000L;
    List<TrackEntity> entities = new ArrayList<>();
    for (int i = 0; i < tracks.length(); i++) {
      entities.add(toEntity(new JSObject(tracks.getJSONObject(i).toString()), now));
    }
    if (!entities.isEmpty()) dao().upsertAll(entities);
  }

  private JSArray loadPersistedLibrary() throws Exception {
    migrateSharedPrefsToRoomIfNeeded();
    List<TrackEntity> entities = dao().getAll();
    if (!entities.isEmpty()) {
      JSArray out = new JSArray();
      for (TrackEntity e : entities) out.put(toJs(e));
      return out;
    }
    return loadLegacySharedPrefsLibrary();
  }

  private JSArray loadLegacySharedPrefsLibrary() throws Exception {
    String raw = getContext()
      .getSharedPreferences(LIBRARY_PREFS, android.content.Context.MODE_PRIVATE)
      .getString(LIBRARY_KEY, "[]");
    String safeRaw = raw != null ? raw : "[]";
    return new JSArray(safeRaw);
  }

  private JSObject findPersistedTrackById(String id) throws Exception {
    migrateSharedPrefsToRoomIfNeeded();
    TrackEntity entity = dao().findByAnyId(id);
    if (entity != null) return toJs(entity);
    JSArray tracks = loadLegacySharedPrefsLibrary();
    for (int i = 0; i < tracks.length(); i++) {
      JSONObject trackJson = tracks.getJSONObject(i);
      JSObject track = new JSObject(trackJson.toString());
      if (id.equals(track.optString("id"))) return track;
    }
    return null;
  }

  private void upsertTrack(JSArray list, JSObject track) throws Exception {
    String id = track.optString("id", "");
    if (id.isEmpty()) {
      return;
    }
    for (int i = 0; i < list.length(); i++) {
      JSONObject existingJson = list.getJSONObject(i);
      JSObject existing = new JSObject(existingJson.toString());
      if (id.equals(existing.optString("id"))) {
        list.put(i, track);
        return;
      }
    }
    list.put(track);
  }

  private JSObject buildTrackFromUri(Uri uri) {
    try {
      ContentResolver resolver = getContext().getContentResolver();
      String mimeType = resolver.getType(uri);
      if (mimeType == null) mimeType = "audio/mpeg";

      String displayName = "Unknown";
      long size = 0L;
      Cursor cursor = resolver.query(uri, new String[]{
        MediaStore.MediaColumns.DISPLAY_NAME,
        MediaStore.MediaColumns.SIZE
      }, null, null, null);
      if (cursor != null) {
        try {
          if (cursor.moveToFirst()) {
            int nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME);
            int sizeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE);
            if (nameIdx >= 0) displayName = cursor.getString(nameIdx);
            if (sizeIdx >= 0) size = cursor.getLong(sizeIdx);
          }
        } finally {
          cursor.close();
        }
      }

      String title = displayName;
      String artist = "Unknown Artist";
      String album = "Unknown Album";
      long durationSeconds = 0L;
      MediaMetadataRetriever retriever = new MediaMetadataRetriever();
      try {
        retriever.setDataSource(getContext(), uri);
        String metadataTitle = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE);
        String metadataArtist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST);
        String metadataAlbum = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM);
        String metadataDuration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
        if (metadataTitle != null && !metadataTitle.trim().isEmpty()) title = metadataTitle;
        if (metadataArtist != null && !metadataArtist.trim().isEmpty()) artist = metadataArtist;
        if (metadataAlbum != null && !metadataAlbum.trim().isEmpty()) album = metadataAlbum;
        if (metadataDuration != null && !metadataDuration.trim().isEmpty()) durationSeconds = Long.parseLong(metadataDuration) / 1000L;
      } catch (Exception ignored) {
      } finally {
        try {
          retriever.release();
        } catch (Exception ignored) {
        }
      }

      AudioFormatInfo formatInfo = getAudioFormatInfo(uri);
      JSObject fileObj = new JSObject();
      String id = sha1(uri.toString());
      fileObj.put("id", id);
      fileObj.put("name", displayName);
      fileObj.put("title", title);
      fileObj.put("artist", artist);
      fileObj.put("album", album);
      fileObj.put("duration", durationSeconds);
      fileObj.put("size", size);
      fileObj.put("mimeType", mimeType);
      fileObj.put("contentUri", uri.toString());
      fileObj.put("dateModified", System.currentTimeMillis() / 1000L);
      fileObj.put("sourceVersionKey", id + ":" + size + ":" + fileObj.optLong("dateModified", 0L));
      if (formatInfo.bitDepth != null) fileObj.put("bitDepth", formatInfo.bitDepth);
      if (formatInfo.sampleRate != null) fileObj.put("sampleRate", formatInfo.sampleRate);
      if (formatInfo.bitrate != null) fileObj.put("bitrate", formatInfo.bitrate);
      fileObj.put("isHiRes", isHiResByMetadata(formatInfo, mimeType));
      return fileObj;
    } catch (Exception e) {
      return null;
    }
  }

  private boolean isHiResByMetadata(AudioFormatInfo formatInfo, String mimeType) {
    if (formatInfo != null && formatInfo.bitDepth != null && formatInfo.sampleRate != null) {
      return formatInfo.bitDepth >= 16 && formatInfo.sampleRate >= 44100;
    }
    if (mimeType == null) return false;
    return mimeType.contains("flac") ||
      mimeType.contains("wav") ||
      mimeType.contains("aiff") ||
      mimeType.contains("alac") ||
      mimeType.contains("dsd");
  }
}
