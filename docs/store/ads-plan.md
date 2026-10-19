# Ads Plan — Touchline Legend

**Decision:** the game ships with exactly **one** ad placement — a rewarded video the
manager chooses to watch in exchange for a fresh set of sponsorship offers. There are
no banners, no interstitials, and no ads anywhere in the match flow.

## Current status

- ✅ `google_mobile_ads` integrated (behind the `AdService` interface)
- ✅ Rewarded placement live on the Sponsorships screen (`sponsorship_reroll`)
- ✅ Release manifest carries `INTERNET` and the AdMob **App ID**; `minSdk` is at
  least 23 (the SDK floor)
- ⚠️ **Test IDs only** — Google's official test rewarded unit and test app ID. The
  production units must replace them before a store build (see below)
- ✅ Privacy policy updated to present tense (in-app screen, `privacy-policy.md`,
  `privacy-policy.html`)
- ✅ Play Console **"Contains ads"** flips to **Yes** at submission
- ✅ Data safety worksheet below matches what AdMob actually receives

## The placement

| Placement | Format | Where | Trigger | Rationale |
|---|---|---|---|---|
| `sponsorship_reroll` | Rewarded video | Sponsorships screen → any slot without a deal | "Watch an ad for fresh offers" | The manager asks for it; the reward is a new shortlist |

**Why only rewarded:** a football manager sim is a paid-attention product, not an ad
vehicle. A rewarded video is opt-in, tied to a genuine decision (keep the current
offers or gamble on a fresh set), and skippable by simply not tapping the button. A
manager can play a twenty-season career without ever seeing an ad.

## Hard rules we commit to

- No banner and no interstitial anywhere: nothing appears over the UI uninvited.
- No ad during a match, at full time, or between ticker minutes.
- No ad required to progress. The rewarded video only refreshes a shortlist, and an
  untouched shortlist is signed automatically at the first matchday.
- No ad before the manager opens the Sponsorships screen and taps the button.
- No ad on startup, Settings, Privacy Policy, New Career or the Home screen.
- One request per tap: while a video is loading, every reroll button is disabled.
- No fill (offline, no inventory) is a normal outcome: the button says so and the
  offers stay exactly as they were.
- No personalised advertising is requested for users under 13; the store listing
  targets 13+.

## Swapping the test IDs for production

Two constants, nothing else:

1. `lib/providers/ad_provider.dart` → `kRewardedTestUnitId`
   (currently `ca-app-pub-3940256099942544/5224354917`).
2. `android/app/src/main/AndroidManifest.xml` → the
   `com.google.android.gms.ads.APPLICATION_ID` meta-data
   (currently `ca-app-pub-3940256099942544~3347511713`).

Studio checklist:

1. Create an AdMob account and register the app (needs the final application ID).
2. Create **one** rewarded ad unit; record the unit ID.
3. Replace both constants, rebuild, and verify a test-device shows the real unit.
4. Never ship the test IDs to production — Google treats test-unit traffic as invalid.
5. If personalised ads are served in the EEA/UK, add the UMP consent flow and the
   `app-ads.txt` entry in AdMob before launch.

## Data safety worksheet (with the rewarded placement)

| Question | Answer |
|---|---|
| Does your app collect or share user data? | **Yes** |
| Device or other IDs | Collected — Advertising — **Shared** with Google AdMob — User-initiated (only when a video is requested) |
| App interactions | Collected — Advertising — Shared — User-initiated |
| Approximate location (from IP) | Collected — Advertising — Shared — User-initiated |
| App info & performance | Collected — Advertising — Shared — User-initiated |
| Is data encrypted in transit? | Yes (HTTPS by the SDK) |
| Can users request deletion? | Uninstall clears all local data; ad-personalisation controls live in Google Ads Settings |

**Historical v1.0-without-ads answer:** "No — this app does not collect or share user
data." The current build contains the SDK, so the **Yes** worksheet is the one to
submit.
