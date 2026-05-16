require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'EpicenterNative'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = 'https://epicenter.local/native-ios'
  s.author = { 'Epicenter' => 'ios@epicenter.local' }
  s.source = { :path => '.' }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp,hpp}'
  s.ios.deployment_target = '13.0'
  s.dependency 'Capacitor'
  s.frameworks = 'AVFoundation', 'MediaPlayer', 'UIKit'
  s.library = 'sqlite3'
  s.swift_version = '5.1'
end
