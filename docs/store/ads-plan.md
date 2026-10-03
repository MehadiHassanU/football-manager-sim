# Ads Plan — Touchline Legend

**Decision:** v1.0 ships **without** an ad SDK. This document prepares everything so the
ad-enabled release (v1.1) is a drop-in change and the Play Console declarations stay truthful.

## Current status (v1.0)

- ❌ No ad SDK integrated
- ❌ Play Console "Contains ads" must remain **UNCHECKED**
- ✅ Privacy policy already discloses the planned change (see `privacy-policy.md` → Advertising)

## Planned placements (v1.1)

| Placement | Format | Location | Rationale |
|---|---|---|---|
| `ft_banner` | Adaptive banner | Full-time match summary, bottom | Natural dwell moment, never covers ratings |
| `postmatch_interstitial` | Interstitial | After tapping "Back to Home" from full time | Session-break moment; capped at 1 per 3 matches |
| `menu_banner` | Adaptive banner | Main menu footer | Idle browsing, low frustration |

**Hard rules we commit to:**
- No interstitial within 60s of app start (Google policy + good UX)
- Never between ticker minutes — mid-match flow stays ad-free
- Settings gets an explicit **"Ads"** section with a "Reduce ads" toggle (disables interstitials)
- Ads never shown on Privacy Policy, Settings, or New Career screens

## Setup steps for the studio (before v1.1)

1. Create a Google AdMob account and register the app (needs the final **application ID** — currently deferred).
2. Create three ad units matching the table above; record their unit IDs.
3. Add `google_mobile_ads` to `pubspec.yaml`; initialize in `main()` **after** `SaveService().init()`.
4. Add the AdMob **App ID** meta-data to `AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.gms.ads.APPLICATION_ID"
       android:value="ca-app-pub-XXXXXXXX~YYYYYYY"/>
   ```
5. Implement placements per the table; gate interstitials behind the Settings toggle.
6. **Update the privacy policy** (both in-app and hosted) from "planned" to present tense **before** upload.
7. Flip Play Console: Data safety (AdMob declarations below) and check "Contains ads".

## Data safety worksheet (v1.1 with ads)

| Question | Answer |
|---|---|
| Does your app collect or share user data? | **Yes** (only once ads are enabled) |
| Data collected: Device or other IDs | Collected — App functionality, Analytics, Advertising — **Shared** with ad provider — Not optional (SDK-level) |
| Data collected: App interactions | Collected — Analytics, Advertising — Shared — Not optional |
| Data collected: Approximate location (IP) | Collected — Advertising — Shared — Not optional |
| Data collected: App info & performance (crash logs) | Collected — Analytics — Not shared — Optional |
| Is data encrypted in transit? | Yes (HTTPS by SDK) |
| Can users request deletion? | Yes — via Google's ad-personalization controls + uninstall clears local data |

**v1.0 (current) worksheet answer:** "No — this app does not collect or share user data."

*Keep both answers handy: v1.0 declaration when first submitting, v1.1 declaration when the ad update ships.*
