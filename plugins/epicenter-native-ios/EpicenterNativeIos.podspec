Pod::Spec.new do |s|
  s.name = 'EpicenterNativeIos'
  s.version = '1.0.0'
  s.summary = 'Epicenter native iOS Capacitor plugin'
  s.license = 'MIT'
  s.homepage = 'https://example.com/epicenter-native-ios'
  s.author = { 'Epicenter' => 'ios@example.com' }
  s.source = { :path => '.' }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.source_files = 'ios/Plugins/*.swift', 'ios/NativeAudio/*.swift', 'ios/DSP/*.swift'
  s.dependency 'Capacitor'
  s.frameworks = 'AVFoundation', 'MediaPlayer', 'UIKit', 'UniformTypeIdentifiers'
  s.libraries = 'sqlite3'
end
