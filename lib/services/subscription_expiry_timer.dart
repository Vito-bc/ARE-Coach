import 'dart:async';

/// Rechecks an absolute entitlement expiry while allowing renewal or disposal.
class SubscriptionExpiryTimer {
  SubscriptionExpiryTimer(this._onExpired, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final void Function() _onExpired;
  final DateTime Function() _now;
  Timer? _timer;

  void schedule(DateTime expiry) {
    cancel();
    void checkExpiry() {
      final remaining = expiry.difference(_now());
      if (remaining <= Duration.zero) {
        _timer = null;
        _onExpired();
        return;
      }
      // Browser setTimeout overflows above signed-int32 milliseconds (~25
      // days). Recheck the absolute deadline daily, including after tab sleep.
      const maxDelay = Duration(days: 1);
      _timer = Timer(remaining > maxDelay ? maxDelay : remaining, checkExpiry);
    }

    checkExpiry();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
