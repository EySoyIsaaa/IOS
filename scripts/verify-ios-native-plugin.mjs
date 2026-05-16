import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const pbxprojPath = join(root, 'ios/App/App.xcodeproj/project.pbxproj');
const infoPlistPath = join(root, 'ios/App/App/Info.plist');
const wrapperPath = join(root, 'client/src/native/iosNativeAudio.ts');

const requiredSwiftSources = [
  'AppDelegate.swift',
  'ViewController.swift',
  'NativeAudio/NativeAudioModels.swift',
  'NativeAudio/NativeLibraryDatabase.swift',
  'NativeAudio/NativeTrackImporter.swift',
  'NativeAudio/NativeTrackRepository.swift',
  'NativeAudio/NativeAudioSessionManager.swift',
  'NativeAudio/NativeAudioEngine.swift',
  'NativeAudio/NativeQueueManager.swift',
  'NativeAudio/NativePlaybackController.swift',
  'NativeAudio/NowPlayingManager.swift',
  'NativeAudio/RemoteCommandManager.swift',
  'DSP/AudioLimiter.swift',
  'DSP/EQ31BandProcessor.swift',
  'DSP/ReverbProcessor.swift',
  'Plugins/EpicenterNativePlugin.swift',
];

const requiredPluginMethods = [
  'importTracks',
  'getLibraryPage',
  'getTrack',
  'deleteTrack',
  'setQueue',
  'play',
  'pause',
  'stop',
  'seek',
  'next',
  'previous',
  'getPlaybackState',
];

const fail = (message) => {
  console.error(`❌ ${message}`);
  process.exitCode = 1;
};

for (const path of [pbxprojPath, infoPlistPath, wrapperPath]) {
  if (!existsSync(path)) {
    fail(`Missing required file: ${path}`);
  }
}

if (process.exitCode) process.exit(process.exitCode);

const pbxproj = readFileSync(pbxprojPath, 'utf8');
const infoPlist = readFileSync(infoPlistPath, 'utf8');
const wrapper = readFileSync(wrapperPath, 'utf8');
const plugin = readFileSync(join(root, 'ios/App/App/Plugins/EpicenterNativePlugin.swift'), 'utf8');

for (const source of requiredSwiftSources) {
  const fullPath = join(root, 'ios/App/App', source);
  if (!existsSync(fullPath)) {
    fail(`Missing native source: ios/App/App/${source}`);
    continue;
  }

  const fileName = source.split('/').pop();
  if (!pbxproj.includes(`${fileName} in Sources`)) {
    fail(`Native source is not in target App Compile Sources: ${source}`);
  }
}

if (!wrapper.includes("registerPlugin<EpicenterNativePlugin>('EpicenterNative')")) {
  fail('TypeScript wrapper is not registered as EpicenterNative');
}

if (!plugin.includes('@objc(EpicenterNativePlugin)')) {
  fail('EpicenterNativePlugin.swift is missing @objc(EpicenterNativePlugin)');
}

if (!plugin.includes('public class EpicenterNativePlugin: CAPPlugin')) {
  fail('EpicenterNativePlugin.swift is not a CAPPlugin class');
}

for (const method of requiredPluginMethods) {
  if (!plugin.includes(`CAPPluginMethod(name: "${method}"`) || !plugin.includes(`func ${method}(`)) {
    fail(`EpicenterNativePlugin.swift does not register/implement ${method}`);
  }
}

if (!infoPlist.includes('<key>UIBackgroundModes</key>') || !infoPlist.includes('<string>audio</string>')) {
  fail('Info.plist is missing UIBackgroundModes audio');
}

if (!process.exitCode) {
  console.log('✅ EpicenterNative iOS plugin files are present and referenced by target App Compile Sources.');
  console.log('✅ TypeScript wrapper uses registerPlugin("EpicenterNative").');
  console.log('✅ Info.plist contains UIBackgroundModes audio.');
}
