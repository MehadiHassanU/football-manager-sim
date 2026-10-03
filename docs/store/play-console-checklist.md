# Play Console Submission Checklist — Touchline Legend

Every form pre-answered. Work top to bottom; items marked ☁️ need your studio
account/decision, everything else is copy-paste from this folder.

## 0. Before you open Play Console

- [ ] ☁️ Host `docs/store/privacy-policy.html` (GitHub Pages / any static host)
      → this becomes your **policy URL**; Play Console requires a public URL
- [ ] ☁️ Replace `support@yourstudio.example` in the policy + listing with the real inbox
- [ ] ☁️ Create the developer account profile (name, address, phone — private, not public)
- [ ] ☁️ Pay the one-time $25 registration fee if not already done
- [ ] ☁️ Decide the final **application ID** (signing milestone, deferred) — required before upload

## 1. App content (Policy → App content)

| Form | Answer |
|---|---|
| **Privacy policy** | Paste hosted URL from step 0 |
| **Ads** | v1.0: **No, my app does not contain ads** → flip to Yes at v1.1 (see ads-plan.md) |
| **In-app purchases** | No |
| **Content ratings** | Start questionnaire → Category: *Game* → answer below |
| **Target audience** | Age groups: **13–15, 16–17, 18+** (NOT "children under 13") → no child-appeal design |
| **News app** | No |
| **COVID-19** | No |
| **Data safety** | v1.0: **"No, this app does not collect or share user data."** (v1.1 worksheet in ads-plan.md) |
| **Government apps** | No |
| **Financial features** | None |

### Content rating questionnaire answers (→ expect Teen / PEGI 12)

| Question | Answer |
|---|---|
| Category | Game |
| Contains violence? | Yes → *Mild/Implied, non-realistic* (simulated sports) |
| Sexual content / nudity | No |
| Language | No |
| Controlled substances | No |
| User-generated content sharing | No (no chat, no sharing between users) |
| Sharing physical location | No |
| Purchasing digital goods | No |
| Gambling / contests | No |

## 2. Main store listing (Growth → Store listing)

- [ ] Title: `Touchline Legend`
- [ ] Short description: `Your Tactics. Your Club. Your Legacy.`
- [ ] Full description: paste from `listing.md`
- [ ] App icon: `assets/icon-512.png` (512×512)
- [ ] Feature graphic: `assets/feature-graphic.png` (1024×512)
- [ ] Phone screenshots: upload all 3 from `assets/`
- [ ] ☁️ Contact email (use the real support inbox)

## 3. Production release (Release → Production)

- [ ] ☁️ Generate keystore + signing config (deferred milestone)
- [ ] ☁️ Set final application ID (deferred milestone)
- [ ] Build: `flutter build appbundle --release` (Play requires **AAB**, not APK)
- [ ] Release notes: paste v1.0 block from `listing.md`
- [ ] Countries: ☁️ choose availability
- [ ] Devices: default (phone + tablet)

## 4. Pre-launch order of operations

1. ☁️ Signing + application ID milestones (blocking)
2. Upload AAB to **internal testing** first, install on a device, verify:
   - Label shows "Touchline Legend" on the launcher
   - New career → play match → standings update
   - Settings → Privacy Policy opens
3. Complete App content forms
4. Submit for review (typical review: a few hours to ~7 days)

## 5. Common rejection reasons we've pre-empted

| Risk | Mitigation |
|---|---|
| Missing privacy policy URL | In-app screen + hosted copy ready |
| Data safety mismatch | Worksheet answers match actual behavior (local-only) |
| "Contains ads" mismatch | v1.0 has no SDK → declare No |
| Target audience mismatch | 13+ declared; no child-oriented graphics in listing |
| Real player names licensing | ⚠️ **Still open** — see roadmap; consider fictional dataset before wide release |
