/**
 * Epicenter Hi-Fi - Native persistent music library adapter.
 *
 * Esta versión de Android usa exclusivamente la biblioteca nativa SQLite/Room
 * expuesta por el plugin MusicScanner. IndexedDB queda deshabilitada para evitar
 * que el WebView conserve copias o metadatos divergentes de las canciones.
 */

const isAndroidNativeLibraryAvailable = (): boolean => {
  if (typeof window === 'undefined') return false;
  const ua = window.navigator.userAgent.toLowerCase();
  return /android/.test(ua) && !!(window as any).Capacitor?.Plugins?.MusicScanner;
};

const getMusicScanner = () => (window as any).Capacitor?.Plugins?.MusicScanner;

const requireNativeLibrary = () => {
  const plugin = getMusicScanner();
  if (!isAndroidNativeLibraryAvailable() || !plugin) {
    throw new Error('Native Android music library is required; IndexedDB is disabled');
  }
  return plugin;
};

const mapNativeTrack = (track: any): StoredTrackMetadata => {
  const albumId = typeof track.albumId === 'number' ? track.albumId : undefined;
  const reconstructedAlbumArtUri = !track.albumArtUri && albumId && albumId > 0
    ? `content://media/external/audio/albumart/${albumId}`
    : undefined;
  const albumArtUri = track.albumArtUri || reconstructedAlbumArtUri;

  return {
    id: String(track.stableId || track.id || ''),
    title: track.title || track.name || 'Unknown',
    artist: track.artist || 'Unknown Artist',
    duration: typeof track.duration === 'number' ? track.duration : 0,
    bitDepth: typeof track.bitDepth === 'number' ? track.bitDepth : undefined,
    sampleRate: typeof track.sampleRate === 'number' ? track.sampleRate : undefined,
    bitrate: typeof track.bitrate === 'number' ? track.bitrate : undefined,
    isHiRes: typeof track.isHiRes === 'boolean' ? track.isHiRes : undefined,
    coverBase64: undefined,
    fileName: track.name || track.title || 'Unknown',
    fileType: track.mimeType || 'audio/mpeg',
    fileSize: typeof track.size === 'number' ? track.size : 0,
    addedAt: typeof track.createdAt === 'number' ? track.createdAt * 1000 : Date.now(),
    sourceUri: track.contentUri || track.sourceUri,
    sourceType: track.sourceType === 'manual-uri' ? 'manual-uri' : 'media-store',
    albumId,
    albumArtUri,
    mediaStoreId: String(track.mediaStoreId || ''),
    dateModified: typeof track.dateModified === 'number' ? track.dateModified : undefined,
    sourceVersionKey: track.sourceVersionKey || `${track.mediaStoreId || track.id}:${track.size || 0}:${track.dateModified || 0}`,
    unavailable: !!track.unavailable,
    unavailableReason: track.unavailableReason || '',
    lastSeenAt: typeof track.lastSeenAt === 'number' ? track.lastSeenAt * 1000 : Date.now(),
    missingSince: typeof track.missingSince === 'number' ? track.missingSince * 1000 : 0,
    missingCount: typeof track.missingCount === 'number' ? track.missingCount : 0,
    scanCompleteness: track.scanCompleteness === 'partial' ? 'partial' : 'complete',
    lastValidatedAt: Date.now(),
    fingerprint: `${track.sourceType || 'media-store'}_${track.mediaStoreId || track.id || ''}_${track.size || 0}_${track.dateModified || 0}`,
  };
};

export interface StoredTrackMetadata {
  id: string;
  title: string;
  artist: string;
  duration: number;
  bitDepth?: number;
  sampleRate?: number;
  bitrate?: number;
  isHiRes?: boolean;
  coverBase64?: string;
  fileName: string;
  fileType: string;
  fileSize: number;
  addedAt: number;
  sourceUri?: string;
  sourceType?: 'file' | 'media-store' | 'manual-uri';
  albumId?: number;
  albumArtUri?: string;
  mediaStoreId?: string;
  dateModified?: number;
  sourceVersionKey?: string;
  unavailable?: boolean;
  unavailableReason?: string;
  lastSeenAt?: number;
  missingSince?: number;
  missingCount?: number;
  scanCompleteness?: 'partial' | 'complete';
  lastValidatedAt?: number;
  fingerprint?: string;
}

export interface StoredPlaylist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: number;
  updatedAt: number;
  coverUrl?: string;
}

class MusicLibraryDB {
  async init(): Promise<void> {
    requireNativeLibrary();
  }

  generateFingerprint(
    fileName: string,
    fileSize: number,
    options?: {
      duration?: number;
      artist?: string;
      title?: string;
      sourceType?: 'file' | 'media-store' | 'manual-uri';
      mediaStoreId?: string;
    }
  ): string {
    const normalizedName = fileName.toLowerCase().trim();
    const normalizedArtist = (options?.artist || '').toLowerCase().trim();
    const normalizedTitle = (options?.title || '').toLowerCase().trim();
    const normalizedDuration = Math.round((options?.duration || 0) * 10) / 10;
    const sourceType = options?.sourceType || 'manual-uri';
    const mediaStorePart = options?.mediaStoreId ? `_${options.mediaStoreId}` : '';
    return `${sourceType}${mediaStorePart}_${normalizedName}_${fileSize}_${normalizedDuration}_${normalizedArtist}_${normalizedTitle}`;
  }

  async findTrackByFingerprint(fingerprint: string): Promise<StoredTrackMetadata | null> {
    const all = await this.getAllTrackMetadata();
    return all.find((t) => t.fingerprint === fingerprint) || null;
  }

  async saveTrack(
    _id: string,
    _metadata: Omit<StoredTrackMetadata, 'id'>,
    _audioBlob: Blob,
  ): Promise<void> {
    throw new Error('Saving Web File blobs is disabled. Use MusicScanner.pickManualAudioTracks so Room stores content:// URIs.');
  }

  async saveTrackReference(
    _id: string,
    _metadata: Omit<StoredTrackMetadata, 'id'>,
  ): Promise<void> {
    // Room is the source of truth. References are created by native scan/import methods.
  }

  async importManualTracksFromPicker(): Promise<{ records: StoredTrackMetadata[]; changed: number; count: number }> {
    const plugin = requireNativeLibrary();
    const result = await plugin.pickManualAudioTracks();
    const records = (result?.records || []).map(mapNativeTrack);
    return {
      records,
      changed: Number(result?.changed || records.length || 0),
      count: Number(result?.count || 0),
    };
  }

  async getTrackMetadataPage(params?: {
    page?: number;
    pageSize?: number;
    search?: string;
    sortBy?: 'title' | 'artist' | 'dateModified';
    sortDir?: 'asc' | 'desc';
  }): Promise<{ records: StoredTrackMetadata[]; total: number; page: number; pageSize: number }> {
    const plugin = requireNativeLibrary();
    const page = params?.page ?? 1;
    const pageSize = params?.pageSize ?? 100;
    const result = await plugin.getLibraryPage({
      page,
      pageSize,
      search: params?.search ?? '',
      sortBy: params?.sortBy ?? 'dateModified',
      sortDir: params?.sortDir ?? 'desc',
    });
    return {
      records: (result?.records || []).map(mapNativeTrack),
      total: Number(result?.total || 0),
      page: Number(result?.page || page),
      pageSize: Number(result?.pageSize || pageSize),
    };
  }

  async getAllTrackMetadata(): Promise<StoredTrackMetadata[]> {
    const plugin = requireNativeLibrary();
    const first = await plugin.getLibraryPage({ page: 1, pageSize: 100, search: '', sortBy: 'dateModified', sortDir: 'desc' });
    const total = Number(first?.total || 0);
    const pageSize = 100;
    const pages = Math.max(1, Math.ceil(total / pageSize));
    const records = [...(first?.records || [])];
    for (let page = 2; page <= pages; page++) {
      const next = await plugin.getLibraryPage({ page, pageSize, search: '', sortBy: 'dateModified', sortDir: 'desc' });
      records.push(...(next?.records || []));
    }
    return records.map(mapNativeTrack);
  }

  async getAudioBlob(_id: string): Promise<Blob | null> {
    return null;
  }

  async deleteTrack(id: string): Promise<void> {
    const plugin = requireNativeLibrary();
    await plugin.deleteTrackById({ id });
  }

  async clearAll(): Promise<void> {
    const plugin = requireNativeLibrary();
    await plugin.clearNativeLibrary();
  }

  async createPlaylist(name: string): Promise<StoredPlaylist> {
    return { id: `playlist-${Date.now()}`, name, trackIds: [], createdAt: Date.now(), updatedAt: Date.now() };
  }
  async getAllPlaylists(): Promise<StoredPlaylist[]> { return []; }
  async getPlaylist(_id: string): Promise<StoredPlaylist | null> { return null; }
  async updatePlaylist(_playlist: StoredPlaylist): Promise<void> {}
  async deletePlaylist(_id: string): Promise<void> {}
  async addTrackToPlaylist(_playlistId: string, _trackId: string): Promise<void> {}
  async removeTrackFromPlaylist(_playlistId: string, _trackId: string): Promise<void> {}
  async renamePlaylist(_id: string, _newName: string): Promise<void> {}
  async cleanupPlaylistReferences(_deletedTrackId: string): Promise<void> {}
}

export const musicLibraryDB = new MusicLibraryDB();

export async function imageToBase64(url: string): Promise<string | undefined> {
  try {
    const response = await fetch(url);
    const blob = await response.blob();
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = () => resolve(undefined);
      reader.readAsDataURL(blob);
    });
  } catch {
    return undefined;
  }
}

export function fileToBlob(file: File): Promise<Blob> {
  return Promise.resolve(file);
}

export function blobToFile(blob: Blob, fileName: string, fileType: string): File {
  return new File([blob], fileName, { type: fileType });
}

export default musicLibraryDB;
