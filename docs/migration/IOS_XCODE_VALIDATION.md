# iOS Xcode validation for EpicenterNative

## Exact cause of the runtime error

The frontend iOS-only route calls `registerPlugin("EpicenterNative")` from TypeScript and then invokes `EpicenterNative.importTracks()`. After the `ios/` folder was regenerated with `npx cap add ios`, the official Xcode project opened correctly, but the native `EpicenterNativePlugin` implementation was no longer registered in the iOS target/bridge. Capacitor therefore had a JavaScript proxy with no native implementation and showed:

```text
"EpicenterNative" plugin is not implemented on ios
```

The fix is not to replace `App.xcodeproj` or hand-generate a new `project.pbxproj`. The fix is to keep the official iOS project and ensure the native Swift sources are present, compiled in target `App`, and explicitly registered with the Capacitor bridge.

## TypeScript wrapper

The frontend wrapper is registered as:

```ts
registerPlugin<EpicenterNativePlugin>('EpicenterNative')
```

This name must match the Swift plugin `jsName`.

## Native plugin registration

The plugin class is restored at:

```text
ios/App/App/Plugins/EpicenterNativePlugin.swift
```

It uses the Capacitor-compatible class name:

```swift
@objc(EpicenterNativePlugin)
public class EpicenterNativePlugin: CAPPlugin, CAPBridgedPlugin
```

The bridge registration is done in the app `CAPBridgeViewController` subclass:

```swift
class ViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        super.capacitorDidLoad()
        registerEpicenterNativePlugin()
    }

    private func registerEpicenterNativePlugin() {
        bridge?.registerPluginInstance(EpicenterNativePlugin())
        NSLog("[iOS Native] EpicenterNativePlugin registered with Capacitor bridge")
    }
}
```

This explicit registration is the part that prevents `EpicenterNative` from resolving to an unimplemented iOS plugin after a clean iOS project regeneration.

## Restored Swift/native files

The native files that must remain under the official iOS project are:

```text
ios/App/App/Plugins/EpicenterNativePlugin.swift
ios/App/App/NativeAudio/NativeAudioModels.swift
ios/App/App/NativeAudio/NativeLibraryDatabase.swift
ios/App/App/NativeAudio/NativeTrackImporter.swift
ios/App/App/NativeAudio/NativeTrackRepository.swift
ios/App/App/NativeAudio/NativeAudioSessionManager.swift
ios/App/App/NativeAudio/NativeAudioEngine.swift
ios/App/App/NativeAudio/NativeQueueManager.swift
ios/App/App/NativeAudio/NativePlaybackController.swift
ios/App/App/NativeAudio/NowPlayingManager.swift
ios/App/App/NativeAudio/RemoteCommandManager.swift
ios/App/App/DSP/AudioLimiter.swift
ios/App/App/DSP/EQ31BandProcessor.swift
ios/App/App/DSP/ReverbProcessor.swift
ios/App/App/DSP/EpicenterDSPBridge.h
ios/App/App/DSP/EpicenterDSPBridge.mm
ios/App/App/DSP/EpicenterDSPCore.hpp
ios/App/App/DSP/EpicenterDSPCore.cpp
```

The plugin exposes the required methods:

- `importTracks`
- `getLibraryPage`
- `getTrack`
- `deleteTrack`
- `setQueue`
- `play`
- `pause`
- `stop`
- `seek`
- `next`
- `previous`
- `getPlaybackState`

## Target App / Compile Sources verification

A validation script was added:

```bash
node scripts/verify-ios-native-plugin.mjs
```

It checks that:

- the TypeScript wrapper registers `EpicenterNative`
- `EpicenterNativePlugin.swift` has the expected `@objc(EpicenterNativePlugin)` Capacitor class
- the required plugin methods are registered and implemented
- the Swift native audio files are referenced in `ios/App/App.xcodeproj/project.pbxproj` as `* in Sources`
- `Info.plist` contains `UIBackgroundModes` with `audio`

## Manual Xcode verification steps

If Xcode validation cannot be run in the current environment, verify on a Mac:

1. Open `ios/App/App.xcworkspace`.
2. Select target `App`.
3. Open **Build Phases > Compile Sources**.
4. Confirm `EpicenterNativePlugin.swift` is listed.
5. Confirm all files under `NativeAudio/` listed above are present in Compile Sources.
6. Confirm the Swift DSP placeholder files are present in Compile Sources.
7. Open `Info.plist` and confirm `UIBackgroundModes` contains `audio`.
8. Run **Product > Clean Build Folder**.
9. Build and run on a physical iPhone.
10. Press **Agregar música** and confirm the UIDocumentPicker opens instead of showing `"EpicenterNative" plugin is not implemented on ios`.
11. Import a song, close/reopen the app, and confirm `getLibraryPage` returns the persisted SQLite track.
12. Play a song and confirm playback goes through the native plugin.

## Validation results in this environment

- `node scripts/verify-ios-native-plugin.mjs`: passed.
- `pnpm build`: passed.
- `npx cap sync ios`: passed. The command still warns that CocoaPods/Xcode are not installed in this Linux environment, so final `pod install` and Xcode build validation must be run on a Mac.

## Commit

Record the final commit hash from `git rev-parse HEAD` after committing this fix.
