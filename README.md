# VelocityAdsGmaAdapter for iOS

Google Mobile Ads custom event adapter that wraps the **Velocity Ads iOS SDK** (`VelocityAdsSDK`) and plugs it into the AdMob / Google Ad Manager mediation waterfall.

## Supported ad formats

| Format | Supported |
|---|---|
| Interstitial | ✓ |
| Rewarded | ✓ |
| Banner / MREC / Leaderboard / Adaptive banner | ✓ |

## Requirements

| Dependency | Minimum version |
|---|---|
| iOS | 13.0 |
| Xcode | 16.0 (Swift 6 toolchain) |
| Google Mobile Ads SDK | 13.0.0 |
| VelocityAdsSDK | 0.10.0 |

## Installation

### CocoaPods

Add both the adapter and its dependencies to your `Podfile`:

```ruby
pod 'Google-Mobile-Ads-SDK', '>= 13.0.0', '< 14.0.0'
pod 'VelocityAdsSDK',        '~> 0.10.0'
pod 'VelocityAdsGmaAdapter', '0.10.0.0'
```

Then run:

```bash
pod install
```

### Swift Package Manager

SPM requires 3-segment `major.minor.patch` versions, but adapter versions have 4 segments (`A.B.C.D`).
Tags are therefore **encoded** as integers: each segment is zero-padded to 2 digits and concatenated.

| Adapter version | Encoded SPM tag |
|---|---|
| `0.10.0.0` | `100000.0.0` |
| `0.10.0.1` | `100001.0.0` |
| `1.0.0.0`  | `1000000.0.0` |

Formula: `A` `BB` `CC` `DD` (each segment 2 digits, leading zeros on the whole number stripped) → `N.0.0`.

1. In Xcode, go to **File → Add Package Dependencies…**
2. Enter the adapter repository URL:

   ```
   https://github.com/velocityiodev/velocityads-ios-gma-adapter
   ```

3. Set the Dependency Rule to **Exact Version** and enter the encoded tag from the [Releases](https://github.com/velocityiodev/velocityads-ios-gma-adapter/releases) page (e.g. `100000.0.0` for adapter `0.10.0.0`).
4. Add `VelocityAdsGmaAdapter` to your app target.

The adapter declares its own SPM dependencies on `GoogleMobileAds` and `VelocityAdsSDK`, so they are pulled in automatically.

## AdMob / Ad Manager setup

### 1. Create a custom event

1. In the AdMob UI, go to **Mediation → Waterfall sources → Custom events** (or in Ad Manager: **Delivery → Yield groups → Custom event**).
2. Click **Add custom event** and fill in the form:

   | Field | Value |
   |---|---|
   | Label | Velocity Ads (or any label) |
   | Class Name | `VelocityAdsGmaAdapter` |
   | Parameter | see below |

### 2. Configure the parameter

The **Parameter** field carries the Velocity configuration for the mapping as a JSON object:

```json
{"appKey":"YOUR_VELOCITY_APP_KEY","adUnitId":"YOUR_VELOCITY_AD_UNIT_ID"}
```

- `adUnitId` (required) — the Velocity ad unit ID for this placement.
- `appKey` (recommended) — your Velocity app key. Include it on every mapping so the adapter can initialize the Velocity SDK on its own. Use **one Velocity app key per application process** across all mappings.

If your app already initializes the Velocity SDK directly, `appKey` may be omitted and the parameter can be just the bare ad unit ID string.

### 3. Add Velocity Ads to your ad units

Add the custom event to the mediation group / yield group of each ad unit you want Velocity Ads to fill. For rewarded ad units, configure the reward amount and type in the AdMob UI — the adapter delivers the reward the Google Mobile Ads SDK is configured with.

## SDK initialization

The adapter initializes the Velocity SDK automatically. You do **not** need to call `VelocityAds.initSDK` yourself.

- When the Google Mobile Ads SDK sets up its adapters (`MobileAds.shared.start`), the adapter initializes the Velocity SDK using the first `appKey` found across your custom event mappings.
- If no mapping carries an `appKey`, the adapter reports ready immediately and initializes the Velocity SDK lazily on the first ad request that does carry one — or relies on your app having initialized the SDK directly.
- If the Velocity SDK is already initialized by your app, the adapter detects this and skips initialization.

Concurrent initialization attempts are coalesced; the Velocity SDK is initialized at most once per process.

## Privacy

**GDPR / TCF** — The Velocity SDK reads the IAB TCF v2 consent signals (`IABTCF_gdprApplies`, `IABTCF_TCString`) directly from `UserDefaults`. Google's User Messaging Platform (UMP) SDK and every IAB-registered CMP write these keys, so no additional integration is required.

**CCPA / US privacy** — The Google Mobile Ads SDK does not expose a per-request "do not sell" signal to adapters. If you need to forward a CCPA opt-out, call the Velocity SDK directly from your app:

```swift
VelocityAds.setDoNotSell(true) // user opted out of sale of personal data
```

## Banner sizes

| Google Mobile Ads `AdSize` | Velocity size |
|---|---|
| `AdSizeBanner` (320×50) | Banner |
| `AdSizeMediumRectangle` (300×250) | MREC |
| `AdSizeLeaderboard` (728×90) | Leaderboard |
| Anchored adaptive (`largeAnchoredAdaptiveBanner(width:)` and variants) | Adaptive — served at the exact width × height requested |
| Inline adaptive / other fixed sizes | Served at the exact width × height requested |
| `AdSizeFluid` | Not supported — the request fails and the waterfall advances |

## Error reporting

Load and show failures are surfaced as standard `NSError` values:

- Errors raised by the Velocity SDK use the domain `io.velocityads.sdk`. The error code is the closest `RequestError` category (no fill, network, invalid request, internal); the original Velocity error code and message are attached as `NSUnderlyingErrorKey` and are visible in Ad Inspector.
- Errors detected by the adapter itself (missing configuration, SDK not initialized, ad not ready, unsupported size, adapter released) use the domain `io.velocityads.gma`.

## How it works

```
Google Mobile Ads SDK
      │
      ▼
VelocityAdsGmaAdapter          (MediationAdapter)
      │
      ├── VelocityGmaInterstitialAd   (MediationInterstitialAd + VelocityInterstitialAdDelegate)
      ├── VelocityGmaRewardedAd       (MediationRewardedAd + VelocityRewardedAdDelegate)
      ├── VelocityGmaBannerAd         (MediationBannerAd + VelocityBannerAdDelegate)
      └── VelocityAdsErrorMapper      (VelocityAdsError → NSError)
```

**Interstitial / Rewarded**

1. The Google Mobile Ads SDK calls `loadInterstitial(for:completionHandler:)` / `loadRewardedAd(for:completionHandler:)` → the adapter creates a `VelocityInterstitialAd` / `VelocityRewardedAd` and calls `.load(delegate:)`.
2. On success, the adapter hands the ad object to the completion handler and receives the event delegate for display-phase callbacks.
3. The Google Mobile Ads SDK calls `present(from:)` → the adapter checks `isReady`, then calls `.show()`.
4. On dismiss, the adapter releases the ad reference.

**Banner**

1. The Google Mobile Ads SDK calls `loadBanner(for:completionHandler:)` → the adapter maps the requested `AdSize` to a Velocity size, creates a `VelocityBannerAdView` and `VelocityBannerAd`, and calls `.load(bannerView:delegate:)`.
2. On success, the adapter hands the ad object to the completion handler; the Google Mobile Ads SDK reads its `view` and places it in the ad container. Impression and click callbacks flow through the event delegate.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
