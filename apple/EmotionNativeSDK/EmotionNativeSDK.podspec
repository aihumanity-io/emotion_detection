Pod::Spec.new do |s|
  s.name = 'EmotionNativeSDK'
  s.version = '0.1.0'
  s.summary = 'Native Apple SDK wrapper for emotion detection.'
  s.description = <<-DESC
Native iOS and macOS SDK wrapper for the emotion detection core ABI, including
camera frame, Vision face detection, still-image, and secure-store boundaries.
  DESC
  s.homepage = 'https://github.com/fdchiu/emotion_detection'
  s.license = { :file => '../../LICENSE' }
  s.author = { 'David Chiu' => 'fdchiu@gmail.com' }
  s.source = { :path => '.' }
  s.source_files = 'Sources/EmotionNativeSDK/**/*.swift'
  s.swift_versions = ['5.7']
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '11.0'
  s.frameworks = 'CoreGraphics', 'Security', 'Vision'
end
