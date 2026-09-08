# AGENTS.md — velocityads-ios-gma-adapter

Engineering guide for contributors and coding agents working on the Velocity Ads Google Mobile Ads adapter for iOS.

---

## ⚠️ This is a public repository

This repository is publicly visible. Every file in it — `README.md`, `CHANGELOG.md`, source code comments, commit messages, and any other documentation — can be read by anyone, including publishers, competitors, and the general public.

### What must never appear in this repo

- Internal repository names (e.g. SDK internal repos, internal tooling repos).
- Internal field names, API paths, server endpoints, or request/response structures that are not part of the public SDK surface.
- Roadmap information: future mediation platforms, future adapter plans, or any unreleased product direction.
- Naming convention strategy documents or internal architecture decisions.
- CI secrets, credentials, or values — and any prose about them (formats, provenance, where a key is reused). The workflow YAML already validates and names the secrets it needs; do not duplicate that in documentation.
- References to internal tools, dashboards, or services not accessible to publishers.
- Internal SDK bridge APIs (e.g. mediation/plugin bridge seams) and how telemetry or analytics are attributed. Publishers integrate through the Google Mobile Ads SDK; they do not need to know how the adapter talks to the SDK internally.
- Maintainer release runbooks. The step-by-step release procedure lives in the team's internal documentation, not in this repo. The workflow's dispatch inputs are self-describing for anyone with permission to run it.

### What belongs here

- `README.md` — **publisher-facing only**: how to add the adapter via CocoaPods / SPM, configure the AdMob custom event, handle privacy, supported formats, version compatibility. No maintainer or release content.
- Adapter behaviour documentation (initialization, ad formats, error handling).
- Public-facing `CHANGELOG.md` entries describing user-visible changes.

### Rule for coding agents

Before writing or editing any file that will be committed to this repo, ask: *could a publisher or external developer read this and learn something we did not intend to disclose?* If yes, rewrite or omit it.

---

## Project overview

This package is the official Google Mobile Ads **custom event adapter** that bridges the Velocity Ads iOS SDK (`VelocityAdsSDK`) into the AdMob / Google Ad Manager mediation waterfall.

- **Repository**: `velocityads-ios-gma-adapter` (public)
- **Distribution**: CocoaPods trunk (`VelocityAdsGmaAdapter`) + Swift Package Manager (git tag)
- **Version scheme**: 4-segment podspec version (`<sdkMajor>.<sdkMinor>.<sdkPatch>.<adapterBuild>`); two git tags per release — the **4-segment tag** (e.g. `0.10.0.0`) for CocoaPods and an **encoded SPM tag** (e.g. `100000.0.0`) for Swift Package Manager (SPM only accepts 3-segment semver; encoding: zero-pad each segment to 2 digits and concatenate)
- **Minimum iOS**: 13.0
- **Supported Google Mobile Ads SDK**: 13.x

---

## Module layout

```
velocityads-ios-gma-adapter/
├── Sources/VelocityAdsGmaAdapter/
│ ├── AdapterVersion.swift # Version constant: velocityAdsGmaAdapterVersion
│ ├── AdapterLog.swift # os_log wrapper for adapter warnings
│ ├── VelocityAdsGmaAdapter.swift # Core adapter: MediationAdapter, setUp, versions, load entry points
│ ├── VelocityAdsGmaAdapter+Init.swift # Init coalescing, app-key memory, mediation info
│ ├── VelocityAdsGmaAdapter+Interstitial.swift # Interstitial load + VelocityGmaInterstitialAd (MediationInterstitialAd)
│ ├── VelocityAdsGmaAdapter+Rewarded.swift # Rewarded load + VelocityGmaRewardedAd (MediationRewardedAd)
│ ├── VelocityAdsGmaAdapter+Banner.swift # Banner load, size resolution + VelocityGmaBannerAd (MediationBannerAd)
│ ├── VelocityInterstitialAdapterDelegate.swift # Translates Velocity callbacks → GMA interstitial events
│ ├── VelocityRewardedAdapterDelegate.swift # Translates Velocity callbacks → GMA rewarded events
│ ├── VelocityBannerAdapterDelegate.swift # Translates Velocity callbacks → GMA banner events
│ ├── VelocityAdsServerParameters.swift # Parses the custom event "parameter" string
│ ├── VelocityAdsErrorMapper.swift # Builds NSError values (adapter + SDK domains)
│ ├── VersionNumberParser.swift # Adapter / SDK version strings → VersionNumber
│ ├── InitCoalescer.swift # Coalesces concurrent init attempts
│ └── InFlightInitPoller.swift # Polls for in-progress SDK init
├── Tests/VelocityAdsGmaAdapterTests/ # XCTest suite
├── Package.swift # SPM manifest
├── VelocityAdsGmaAdapter.podspec # CocoaPods podspec
└── .github/workflows/
 ├── unit-tests.yml # CI: SwiftLint + xcodebuild simulator tests on PR/push
 ├── publish-adapter.yml # Release: validate → test → pod lint → tag + GitHub Release + trunk push
 └── cocoapods-keepalive.yml # Scheduled: keeps CocoaPods trunk token alive
```

---

## Adapter class name

The class registered in the AdMob **Custom event** entry is:

```
VelocityAdsGmaAdapter
```

Do not rename this class (or remove its `@objc(VelocityAdsGmaAdapter)` attribute) — it is a hard-coded string in every publisher's AdMob configuration and the Google Mobile Ads SDK instantiates it by name.

---

## Custom event parameter contract

The Google Mobile Ads SDK delivers one opaque string per custom event mapping (`GADCustomEventParametersServer`). `VelocityAdsServerParameters` accepts:

- a JSON object `{"appKey":"…","adUnitId":"…"}` (`appKey` optional), or
- a bare string, treated as the ad unit ID.

Do not add new keys without updating `README.md`; the parameter is publisher-facing configuration.

---

## Threading model

- `setUp(with:completionHandler:)` and the version getters are class methods and may be invoked on a background queue; `setUp` hops to the main actor before touching the coalescer.
- Load entry points are invoked on the main thread and their completion handlers must be called on the main thread.
- `InitCoalescer`, the per-format ad classes and all Velocity delegate protocols are `@MainActor`.

---

## Versioning

Version source of truth: `velocityAdsGmaAdapterVersion` in `Sources/VelocityAdsGmaAdapter/AdapterVersion.swift`.

The podspec `s.version` must always match. `adapterVersion()` reports the value to Google as `major.minor.(patch * 100 + adapterBuild)`, matching Google's mediation adapter convention. The release workflow creates **two** git tags per release:

- The **4-segment tag** (e.g. `0.10.0.0`) — used by CocoaPods (`s.source[:tag]` is the full 4-segment `s.version`) and as the GitHub Release anchor.
- The **encoded SPM tag** (e.g. `100000.0.0`) — Swift Package Manager only accepts 3-segment semver, so each of the four segments is zero-padded to 2 digits and concatenated (`0.10.0.0` → `00100000` → `100000` → `100000.0.0`).

When bumping the version, update **both** `AdapterVersion.swift` and `VelocityAdsGmaAdapter.podspec` together.

---

## Build & verification

```bash
# Resolve SPM dependencies
swift package resolve

# Run unit tests (requires a connected simulator or Xcode)
xcodebuild test -scheme VelocityAdsGmaAdapter \
 -destination "platform=iOS Simulator,name=iPhone 17"

# Lint Swift code
swiftlint lint --strict

# Lint podspec (validates against live CocoaPods repos — requires network)
pod spec lint VelocityAdsGmaAdapter.podspec --allow-warnings --skip-tests
```

**SDK-first requirement**: `Package.swift` depends on the public `velocityads-ios-sdk` tag and `VelocityAdsSDK` CocoaPods pod. CI and `pod spec lint` will fail until the matching SDK version is published.

---

## CI workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `unit-tests.yml` | PR / push to `main` | SwiftLint (strict) + xcodebuild simulator tests |
| `publish-adapter.yml` | Manual dispatch | Validate (versions + CHANGELOG + duplicate-tag guard) → test → pod lint → GPG tag + GitHub Release + CocoaPods trunk push |
| `cocoapods-keepalive.yml` | Every 2 days (scheduled) | Pings CocoaPods trunk to prevent token expiry |

The `env:` block at the top of each workflow file contains all adapter-specific values (scheme name, podspec name). All other steps are mediation-agnostic.

---

## Swift conventions

Follow the conventions from the Velocity Ads iOS SDK `AGENTS.md`:

- Swift-first; no Objective-C.
- `internal` for anything not part of the public adapter surface. The only public type is `VelocityAdsGmaAdapter`.
- No `fatalError`, `preconditionFailure`, or `assertionFailure` in adapter code.
- No force-unwrap (`!`) in production code.
- Code must pass `swiftlint lint --strict` before merging.

---

## Changelog convention

Follow [Keep a Changelog](https://keepachangelog.com). Use `### Added`, `### Changed`, `### Fixed`, `### Breaking Changes` as section headings. Write for publishers — describe user-visible behaviour, not internal implementation.

---

## Code hygiene

Delete everything that no longer reflects the current state of the codebase:

- Dead code and unused imports.
- Stale comments or narration-only comments.
- Any reference to internal repos, tools, or field names (see the **Public repository** section above).

---

## Pre-merge checklist

1. `xcodebuild test` passes against a simulator.
2. `swiftlint lint --strict` passes with zero violations.
3. `AdapterVersion.swift` and `VelocityAdsGmaAdapter.podspec` versions match.
4. No internal repo names, field names, key material details, bridge APIs, or roadmap content in any committed file.
5. `CHANGELOG.md` updated if the change is user-visible.
6. `README.md` updated if the public-facing integration instructions changed.
