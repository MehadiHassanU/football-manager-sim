/// What came back from a rewarded ad.
enum AdReward {
  /// Watched to the end: the reward is earned.
  earned,

  /// Closed before the ad finished: no reward.
  dismissed,

  /// No ad could be shown — offline, no fill, or an unsupported platform.
  unavailable,
}

/// The one ad the game shows: a rewarded video the manager chooses to watch in
/// exchange for a free reroll of the sponsorship offers.
///
/// Kept as an interface so screens can be handed a fake in tests and so the
/// real SDK never leaks into the widget tree. Implementations must never show
/// anything the manager did not ask for.
abstract class AdService {
  /// Shows the rewarded video and resolves with what happened.
  ///
  /// [placement] names where the ad was requested, which is what ad networks
  /// report on and what makes a future second placement pin downable.
  Future<AdReward> showRewarded({required String placement});
}

/// A service that cannot show ads, for platforms and tests where the reward
/// flow still has to work — the caller simply never gets it for free.
class NoAdsService implements AdService {
  const NoAdsService();

  @override
  Future<AdReward> showRewarded({required String placement}) async =>
      AdReward.unavailable;
}
