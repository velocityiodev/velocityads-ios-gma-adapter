# Changelog

## [0.11.0.0] - Unreleased

### Breaking Changes

* **Minimum iOS version raised from 13.0 to 15.0**, matching Velocity Ads iOS SDK 0.11.0. Apps with a lower deployment target must raise it to 15.0 before upgrading; CocoaPods and Swift Package Manager will not resolve the adapter otherwise.

### Changed

* Wraps Velocity Ads iOS SDK 0.11.0.

## [0.10.1.0] - 2026-09-17

### Added

* Initial release of the Velocity Ads Google Mobile Ads (AdMob / Ad Manager) custom event adapter for iOS.
* Supported ad formats: interstitial, rewarded, and banner — the banner format also serves MREC, leaderboard, and adaptive banner sizes.
* Wraps Velocity Ads iOS SDK 0.10.1.
* Supports Google Mobile Ads SDK 13.x.
* Requires iOS 13.0 or later.
* CocoaPods (`VelocityAdsGmaAdapter`) and Swift Package Manager distribution.
