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
  s.source_files = 'ios/Plugins/*.swift', 'ios/NativeAudio/*.swift', 'ios/DSP/*.{swift,h,hpp,mm,cpp}'
  s.public_header_files = 'ios/DSP/EpicenterDSPBridge.h'
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17', 'CLANG_CXX_LIBRARY' => 'libc++' }
  s.dependency 'Capacitor'
  s.frameworks = 'AVFoundation', 'MediaPlayer', 'UIKit', 'UniformTypeIdentifiers'
  s.libraries = 'sqlite3'
end
