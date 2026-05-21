#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint emotion_detection.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'emotion_detection'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*', '../apple/EmotionNativeSDK/Sources/EmotionNativeSDK/**/*.swift'
  s.static_framework = true

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'emotion_detection_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  s.dependency 'ZIPFoundation', '~> 0.9'
  s.dependency 'onnxruntime-objc', '1.20.0'

  # onnxruntime-objc 1.20.0 requires macOS 11.0+.
  s.platform = :osx, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.7'

  # Reuse encrypted model assets from the iOS directory via a dedicated bundle.
  s.resource_bundles = {
    'emotion_detection_models' => [
      '../ios/Assets/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.enc',
      '../ios/Assets/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.manifest.json',
      '../ios/Assets/aih_exp15_float16.enc',
      '../ios/Assets/aih_exp15_float16.manifest.json'
    ]
  }
end
