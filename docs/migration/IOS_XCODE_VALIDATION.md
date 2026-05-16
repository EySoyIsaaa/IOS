# iOS Xcode validation for EpicenterNative

## Exact cause of the runtime error

The frontend iOS-only route calls `registerPlugin("EpicenterNative")` from TypeScript and then invokes `EpicenterNative.importTracks()`. After the `ios/` folder was regenerated with `npx cap add ios`, the official Xcode project opened correctly, but the native `EpicenterNativePlugin` implementation was no longer available to Capacitor on iOS. Capacitor therefore had a JavaScript proxy with no compiled native implementation and showed:

```text
"EpicenterNative" plugin is not implemented on ios
```

A later attempt to fix this by injecting Swift files directly into `ios/App/App.xcodeproj/project.pbxproj` corrupted the plist and caused CocoaPods/Nanaimo to fail with:

```text
Nanaimo::Reader::ParseError
Found additional characters after parsing the root plist object
runOnlyForDeploymentPostprocessing = 0; }};
```

The current fix deliberately avoids manual `project.pbxproj` edits.

## Safe registration strategy

The iOS project is the official Capacitor-generated project from:

```bash
rm -rf ios
npx cap add ios
pnpm build
npx cap sync ios
```

Native Epicenter files are restored into `ios/App/App/...` for inspection/manual Xcode use, but they are **not** manually inserted into `project.pbxproj`.

The compiled implementation is provided by a local Capacitor plugin package:

```text
plugins/epicenter-native
```

The app depends on it with:

```json
"@epicenter/native": "file:plugins/epicenter-native"
```

Capacitor discovers that package, adds this to `ios/App/App/capacitor.config.json`:

```json
"packageClassList": ["EpicenterNativePlugin"]
```

and adds the CocoaPods dependency to `ios/App/Podfile`:

```ruby
pod 'EpicenterNative', :path => '../../node_modules/.../@epicenter/native'
```

This lets CocoaPods/Xcode compile the Swift plugin without hand-editing `App.xcodeproj`.

## TypeScript wrapper

The frontend wrapper remains:

```ts
registerPlugin<EpicenterNativePlugin>('EpicenterNative')
```

The name matches the Swift plugin `jsName`.

## Native plugin class

The plugin class is restored in both places:

```text
ios/App/App/Plugins/EpicenterNativePlugin.swift
plugins/epicenter-native/ios/Sources/EpicenterNativePlugin/EpicenterNativePlugin.swift
```

It uses the Capacitor-compatible class name:

```swift
@objc(EpicenterNativePlugin)
public class EpicenterNativePlugin: CAPPlugin, CAPBridgedPlugin
```

and declares:

```swift
public let jsName = "EpicenterNative"
```

## Restored native files

The native files restored under the official iOS app tree are:

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

The compiled local plugin package contains the same Swift/native implementation under:

```text
plugins/epicenter-native/ios/Sources/EpicenterNativePlugin/
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

Do **not** manually edit `project.pbxproj`.

The intended state is:

- `ios/App/App.xcodeproj/project.pbxproj` stays official/Capacitor-generated.
- `project.pbxproj` does not contain manual `EpicenterNativePlugin.swift` or `NativeAudio/` source references.
- `EpicenterNative` compiles via the generated CocoaPods pod entry.

A validation script checks this:

```bash
node scripts/verify-ios-native-plugin.mjs
```

It verifies:

- the TypeScript wrapper registers `EpicenterNative`
- the local plugin package and podspec exist
- `Podfile` includes `pod 'EpicenterNative'`
- `capacitor.config.json` includes `EpicenterNativePlugin` in `packageClassList`
- the restored iOS source copies exist
- the compiled plugin package sources exist
- required plugin methods are registered and implemented
- `Info.plist` contains `UIBackgroundModes` with `audio`
- `project.pbxproj` does not include manual native Epicenter source references

## Manual Xcode verification steps

On a Mac:

1. Run `pnpm install`.
2. Run `pnpm build`.
3. Run `npx cap sync ios`.
4. Run `cd ios/App && pod install`.
5. Open `ios/App/App.xcworkspace`.
6. Confirm the Pods project contains `EpicenterNative`.
7. Confirm `ios/App/App/Info.plist` contains `UIBackgroundModes` → `audio`.
8. Run **Product > Clean Build Folder**.
9. Build and run on a physical iPhone.
10. Press **Agregar música** and confirm the UIDocumentPicker opens instead of showing `"EpicenterNative" plugin is not implemented on ios`.
11. Import a song, close/reopen the app, and confirm `getLibraryPage` returns the persisted SQLite track.
12. Play a song and confirm playback goes through the native plugin.

If you choose not to use the local plugin package and want the source copies under `ios/App/App` compiled directly, add files from Xcode only:

```text
Target App > Build Phases > Compile Sources > + > Add Files
```

Do not edit `project.pbxproj` by hand.

## Validation results in this environment

- `node scripts/verify-ios-native-plugin.mjs`: passed.
- `pnpm build`: passed.
- `npx cap sync ios`: passed and found `@epicenter/native@0.0.1`.
- `pod install --allow-root`: passed after installing CocoaPods in the user gem path for this environment.
- `ruby -e "gem 'xcodeproj','1.27.0'; require 'xcodeproj'; Xcodeproj::Project.open('ios/App/App.xcodeproj')"`: passed, confirming Nanaimo can parse the regenerated official `project.pbxproj`.
