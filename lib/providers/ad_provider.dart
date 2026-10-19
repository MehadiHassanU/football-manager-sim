import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/services/ad_service.dart';

export '../core/services/ad_service.dart';

/// Google's official **test** rewarded unit. It always fills, never bills, and
/// is the only unit that may be used before the app has real AdMob inventory.
///
/// Replace with the production rewarded unit when the store build gets its own
/// AdMob account (see `docs/store/ads-plan.md`). Shipping a test unit in
/// production is a policy violation, so this is deliberately the one line to
/// change — not a scattering of IDs.
const String kRewardedTestUnitId = 'ca-app-pub-3940256099942544/5224354917';

/// Shows a Google AdMob rewarded video and reports whether the manager watched
/// it to the end.
///
/// One placement only: the sponsorship reroll. There are deliberately no
/// banners or interstitials — the manager chooses the ad or nothing happens.
class GoogleAdService implements AdService {
  /// Initialisation is expensive and idempotent, so it is done once, lazily,
  /// on the first ad request rather than during app start.
  Future<void>? _initialisation;

  Future<void> _ensureInitialised() {
    return _initialisation ??= MobileAds.instance.initialize();
  }

  @override
  Future<AdReward> showRewarded({required String placement}) async {
    // The SDK only exists on the mobile targets. Keeping the guard here means
    // the rest of the app never has to ask which platform it is running on.
    if (!(Platform.isAndroid || Platform.isIOS)) return AdReward.unavailable;

    try {
      await _ensureInitialised();
      final loaded = Completer<RewardedAd?>();
      RewardedAd.load(
        adUnitId: kRewardedTestUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: loaded.complete,
          onAdFailedToLoad: (error) => loaded.complete(null),
        ),
      );
      final ad = await loaded.future;
      if (ad == null) return AdReward.unavailable;

      // The reward callback fires only when the video has been watched to the
      // end; dismissing early therefore resolves as `dismissed`, not `earned`.
      final watched = Completer<AdReward>();
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (ad) {
          if (!watched.isCompleted) watched.complete(AdReward.dismissed);
          ad.dispose();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          if (!watched.isCompleted) watched.complete(AdReward.unavailable);
          ad.dispose();
        },
      );
      await ad.show(onUserEarnedReward: (ad, reward) {
        if (!watched.isCompleted) watched.complete(AdReward.earned);
      });
      return await watched.future;
    } catch (_) {
      // No fill, no network, SDK not ready: the button must degrade to "no ad
      // right now", never throw into the widget tree.
      return AdReward.unavailable;
    }
  }
}

/// The rewarded-ad service behind the sponsorship reroll.
///
/// Overridden with a fake in widget tests, so no test ever talks to AdMob.
final adServiceProvider = Provider<AdService>((ref) => GoogleAdService());
