#
# Be sure to run `pod lib lint MixinServices.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MixinServices'
  s.version          = '0.1.0'
  s.summary          = 'Mixin Core Services.'
  s.description      = <<-DESC
Mixin Core Services.
                       DESC

  s.homepage         = 'https://github.com/wuyueyang/MixinServices'
  s.license          = { :type => 'GNU GPL v3', :file => 'LICENSE' }
  s.author           = { 'wuyueyang' => 'wuyueyang@mixin.one' }
  s.source           = { :git => 'https://github.com/wuyueyang/MixinServices.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'

  s.static_framework = true

  s.ios.vendored_frameworks = 'MixinServices/Goutils.framework'
  s.source_files = 'MixinServices/Foundation/**/*', 'MixinServices/Crypto/**/*', 'MixinServices/Storage/**/*', 'MixinServices/Services/**/*'

  s.dependency 'AppCenter'
  s.dependency 'Alamofire'
  s.dependency 'SDWebImage'
  s.dependency 'SDWebImageYYPlugin/YYImage'
  s.dependency 'YYImage/WebP'
  s.dependency 'DeviceGuru'
  s.dependency 'GzipSwift'
  s.dependency 'Zip'
  s.dependency 'libsignal-protocol-c'
  s.dependency 'SocketRocket'
  s.dependency 'GRDB.swift/SQLCipher'
  s.dependency 'SQLCipher', '~> 4.0'
  s.dependency 'SwiftyMarkdown'
  s.dependency 'lottie-ios'
  s.dependency 'BoringSSL'

  s.test_spec 'DatabaseTests' do |dbtest|
    dbtest.source_files = 'MixinServicesTests/Database/*'
  end
end
