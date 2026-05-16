import { useState } from 'react';

export interface StoredTrack {
  id: string;
  title: string;
  artist: string;
  duration: number;
  file: Blob;
  coverUrl?: string;
  timestamp: number;
}

export async function saveTrackToLibrary(_track: StoredTrack): Promise<void> {
  throw new Error('IndexedDB is disabled in the Android build. Use the native Room music library.');
}

export async function getAllTracksFromLibrary(): Promise<StoredTrack[]> {
  return [];
}

export async function deleteTrackFromLibrary(_id: string): Promise<void> {
  // No-op: library deletion is handled by the native Room adapter.
}

export function useLibraryPersistence() {
  const [library, setLibrary] = useState<StoredTrack[]>([]);
  const [isLoading] = useState(false);

  const addTrack = async (track: StoredTrack) => {
    await saveTrackToLibrary(track);
    setLibrary((prev) => [...prev, track]);
  };

  const removeTrack = async (id: string) => {
    await deleteTrackFromLibrary(id);
    setLibrary((prev) => prev.filter((track) => track.id !== id));
  };

  return {
    library,
    isLoading,
    addTrack,
    removeTrack,
  };
}
