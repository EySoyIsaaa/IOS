# iOS-only frontend route

This branch is now optimized exclusively for iPhone/iOS native playback and library management. Android and Web library/playback paths are intentionally not preserved here because those products live in separate branches/projects.

## Removed Android/Web routes

- The Home screen no longer imports or calls the Android media scanner hook.
- The visible library importer no longer renders Android automatic scanning or Web fallback picker UI.
- Manual import no longer creates an `<input type="file">` fallback and no longer stores tracks through browser persistence.
- Playback no longer resolves device URLs through Android scanner helpers and no longer loads audio into browser audio elements or worklets.
- The media notification hook is a safe no-op facade; iOS Now Playing and remote commands are owned by the native plugin.
- The problematic media-session/mediastore npm dependencies were removed from the frontend dependency graph.

## Replaced hooks and facades

- `useAudioQueue` is now an iOS-native queue/library facade. Its source of truth is `EpicenterNative`.
- `useIosNativeAudioProcessor` is the main playback facade. It calls native iOS playback methods and exposes the shape expected by the existing Home UI.
- `useIntegratedAudioProcessor` now forwards to the iOS-native facade for legacy imports only; it does not run the old browser audio implementation.
- `useStreamingEpicenter` is a placeholder for the future native DSP phase and does not start browser DSP processing.
- `useMediaNotification` exposes the expected methods but intentionally does not import or call an external media-session plugin.

## iOS library loading

At app start, `useAudioQueue` loads tracks only from:

```ts
EpicenterNative.getLibraryPage({ offset: 0, limit: 1000, sort: 'addedAt' })
```

The temporary required logs are emitted during load:

- `[iOS Native Library] app start load`
- `[iOS Native Library] loaded count`

Manual import calls only:

```ts
EpicenterNative.importTracks()
```

After import, the hook refreshes the library by calling `EpicenterNative.getLibraryPage(...)` again and emits:

- `[iOS Native Library] import requested`
- `[iOS Native Library] imported count`

Deleting a track calls only:

```ts
EpicenterNative.deleteTrack({ id })
```

## iOS playback

Home routes playback through `useIosNativeAudioProcessor`, which calls:

- `EpicenterNative.play({ trackId })`
- `EpicenterNative.pause()`
- `EpicenterNative.seek({ seconds })`
- `EpicenterNative.stop()`
- `EpicenterNative.getPlaybackState()`

The queue facade synchronizes queue order with:

```ts
EpicenterNative.setQueue({ trackIds, startIndex })
```

Next/previous queue actions call `EpicenterNative.next()` and `EpicenterNative.previous()`.

Temporary playback logs are emitted from the native facade:

- `[iOS Native Playback] play trackId`
- `[iOS Native Playback] state`
- `[iOS Native Playback] error`

## Pending DSP/EQ/FX work

DSP/EQ/FX UI remains visually available, but this phase does not implement the full native DSP pipeline. The current frontend keeps controls wired as safe stubs or native placeholders only. A later dedicated DSP phase should connect Epicenter DSP, EQ bands, reverb, and FX to the native AVAudioEngine chain without restoring browser worklet processing.
