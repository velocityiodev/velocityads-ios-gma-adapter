Pod::Spec.new do |s|
  s.name             = 'VelocityAdsGmaAdapter'
  s.version          = '0.10.0.0'
  s.summary          = 'Google Mobile Ads custom event adapter for the Velocity Ads iOS SDK.'
  s.description      = <<-DESC
    VelocityAdsGmaAdapter bridges the Velocity Ads iOS SDK into the AdMob /
    Google Ad Manager mediation waterfall, supporting interstitial, rewarded, and
    banner / MREC / leaderboard / adaptive banner ad formats.
  DESC

  s.homepage         = 'https://github.com/velocityiodev/velocityads-ios-gma-adapter'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Velocity Ads' => 'sdk@velocityads.io' }

  # Both the CocoaPods release tag and the pod version are the full 4-segment
  # version — the release workflow creates a 4-segment git tag (e.g. 0.10.0.0)
  # for CocoaPods. (The separate encoded SPM tag is only for Swift Package Manager,
  # which cannot parse 4-segment versions; CocoaPods never uses it.)
  s.source           = {
    :git => 'https://github.com/velocityiodev/velocityads-ios-gma-adapter.git',
    :tag => s.version.to_s
  }

  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/VelocityAdsGmaAdapter/**/*.swift'

  s.dependency 'Google-Mobile-Ads-SDK', '>= 13.0.0', '< 14.0.0'
  s.dependency 'VelocityAdsSDK', '~> 0.10.0'

  # Google-Mobile-Ads-SDK ships as a static XCFramework.
  s.static_framework = true
end
