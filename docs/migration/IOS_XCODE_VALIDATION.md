# iOS Xcode validation for EpicenterNative

## Exact cause of the runtime error

The frontend iOS-only route calls `registerPlugin("EpicenterNative")` from TypeScript and then invokes `EpicenterNative.importTracks()`. After the `ios/` folder was regenerated with `rm -rf ios`, `npx cap add ios`, and `npx cap sync ios`, the official Xcode project opened correctly, but the native implementation was no longer available to Capacitor. Capacitor therefore had a JavaScript proxy with no native implementation and showed:

```text
"EpicenterNative" plugin is not implemented on ios
```

A previous repair path also proved unsafe because hand-editing `ios/App/App.xcodeproj/project.pbxproj` can produce a Nanaimo parser failure such as:

```text
Nanaimo::Reader::ParseError
Found additional characters after parsing the root plist object
runOnlyForDeploymentPostprocessing = 0; }};
```

This fix keeps the official Capacitor-generated `ios/` project and does **not** manually add native sources to `project.pbxproj`.

## Safe registration approach

The native implementation is packaged as a local Capacitor iOS plugin:

```text
plugins/epicenter-native-ios
```

The root app depends on it via `package.json`, so `npx cap sync ios` discovers it as a normal Capacitor plugin and safely updates:

- `ios/App/Podfile` with `pod 'EpicenterNativeIos', :path => ...`
- `ios/App/App/capacitor.config.json` with `packageClassList: ["EpicenterNativePlugin"]`

This means CocoaPods/Xcode integrates the Swift sources through a Pod target instead of manual `project.pbxproj` source edits.

## TypeScript wrapper

The frontend wrapper is registered as:

```ts
registerPlugin<EpicenterNativePlugin>('EpicenterNative')
```

This name matches the Swift plugin `jsName`.

## Native plugin class

The plugin class is:

```swift
@objc(EpicenterNativePlugin)
public class EpicenterNativePlugin: CAPPlugin, CAPBridgedPlugin
```

and it declares:

```swift
public let jsName = "EpicenterNative"
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

## Restored native files

Mirror copies are kept under the regenerated official iOS app folder for Xcode visibility/manual inspection:

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

The compiled source of truth for automatic Capacitor registration is the local plugin package:

```text
plugins/epicenter-native-ios/ios/Plugins/EpicenterNativePlugin.swift
plugins/epicenter-native-ios/ios/NativeAudio/*.swift
plugins/epicenter-native-ios/ios/DSP/*.swift
```

## Compile Sources / target validation

Do not hand-edit `ios/App/App.xcodeproj/project.pbxproj`.

The preferred validation is:

```bash
node scripts/verify-ios-native-plugin.mjs
```

It checks that:

- the TypeScript wrapper registers `EpicenterNative`
- the local plugin package contains the Swift native sources
- the iOS app mirror files are present
- `EpicenterNativePlugin.swift` has `@objc(EpicenterNativePlugin)`, `CAPPlugin`, `CAPBridgedPlugin`, `jsName = "EpicenterNative"`, and required methods
- `ios/App/App/capacitor.config.json` contains `EpicenterNativePlugin` in `packageClassList`
- `ios/App/Podfile` contains the safe local pod `EpicenterNativeIos`
- `project.pbxproj` does not contain manual native source references or the known corrupt `}};` Nanaimo pattern
- `Info.plist` contains `UIBackgroundModes` with `audio`

If you choose not to use the local pod and instead add files manually in Xcode, use only Xcode UI:

1. Open `ios/App/App.xcworkspace`.
2. Select target `App`.
3. Open **Build Phases > Compile Sources**.
4. Press `+` > **Add Files...**.
5. Add `EpicenterNativePlugin.swift` and all required `NativeAudio/*.swift` files.
6. Do not manually edit `project.pbxproj`.

For this branch, the local pod route is preferred because it survives `npx cap sync ios` without manual project-file edits.

## Info.plist

`ios/App/App/Info.plist` must contain:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## Validation results

- `pnpm build`: passed.
- `npx cap sync ios`: passed and found `epicenter-native-ios@1.0.0`.
- `node scripts/verify-ios-native-plugin.mjs`: passed.
- `pod install --allow-root`: passed in this Linux container after installing CocoaPods locally as a gem; no Nanaimo parser error was raised.

On macOS, run normal `pod install` from `ios/App` without `--allow-root`.

## Manual iPhone validation

1. Open `ios/App/App.xcworkspace`.
2. Run **Product > Clean Build Folder**.
3. Build and run on a physical iPhone.
4. Press **Agregar música**.
5. Confirm UIDocumentPicker opens instead of showing `"EpicenterNative" plugin is not implemented on ios`.
6. Import a song.
7. Close/reopen the app and confirm `getLibraryPage` returns the persisted SQLite track.
8. Play a song and confirm playback goes through the native plugin.
