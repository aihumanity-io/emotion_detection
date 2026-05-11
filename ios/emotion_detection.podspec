#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint emotion_detection.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'emotion_detection'
  s.version          = '0.2.0'
  s.summary          = 'A emotion detection Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://emotionai.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'David Chiu' => 'fdchiu@@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*', '../apple/EmotionNativeSDK/Sources/EmotionNativeSDK/**/*.swift'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'ZIPFoundation', '~> 0.9'
  s.dependency 'onnxruntime-objc', '1.20.0'
  #pod 'ZIPFoundation', '~> 0.9'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.7'

   s.resources        = [
     'Assets/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.enc',
     'Assets/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.manifest.json'
   ]

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'emotion_detection_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
