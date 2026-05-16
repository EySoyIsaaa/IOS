/**
 * iOS-only local playlist shell. Track library persistence lives in EpicenterNative.
 */
export interface StoredTrackMetadata {
  id: string;
  title: string;
  artist: string;
  duration: number;
}

export interface StoredPlaylist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: number;
  updatedAt: number;
}

let playlists: StoredPlaylist[] = [];

export const fileToBlob = async (file: File) => new Blob([file]);
export const blobToFile = (blob: Blob, name: string, type = 'audio/mpeg') => new File([blob], name, { type });

const now = () => Date.now();
const newId = () => `ios-playlist-${now()}-${Math.random().toString(36).slice(2)}`;

export const musicLibraryDB = {
  getTrackMetadataPage: async () => ({ records: [] as StoredTrackMetadata[], total: 0 }),
  getAllTrackMetadata: async () => [] as StoredTrackMetadata[],
  saveTrack: async () => undefined,
  getTrack: async () => undefined,
  deleteTrack: async () => undefined,
  clear: async () => undefined,
  importManualTracksFromPicker: async () => ({ records: [] as StoredTrackMetadata[], changed: 0 }),
  getAllPlaylists: async () => playlists,
  createPlaylist: async (name: string) => {
    const playlist = { id: newId(), name, trackIds: [], createdAt: now(), updatedAt: now() };
    playlists = [playlist, ...playlists];
    return playlist;
  },
  deletePlaylist: async (id: string) => {
    playlists = playlists.filter((playlist) => playlist.id !== id);
  },
  renamePlaylist: async (id: string, name: string) => {
    playlists = playlists.map((playlist) => playlist.id === id ? { ...playlist, name, updatedAt: now() } : playlist);
  },
  addTrackToPlaylist: async (playlistId: string, trackId: string) => {
    playlists = playlists.map((playlist) => playlist.id === playlistId && !playlist.trackIds.includes(trackId)
      ? { ...playlist, trackIds: [...playlist.trackIds, trackId], updatedAt: now() }
      : playlist);
  },
  removeTrackFromPlaylist: async (playlistId: string, trackId: string) => {
    playlists = playlists.map((playlist) => playlist.id === playlistId
      ? { ...playlist, trackIds: playlist.trackIds.filter((id) => id !== trackId), updatedAt: now() }
      : playlist);
  },
};
