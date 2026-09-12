import 'dart:async';

import 'package:are_coach/services/subscription_expiry_timer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 9, 11);

  for (final days in [30, 365]) {
    test(
      '$days-day expiry does not fire on the next real event-loop tick',
      () async {
        var expired = false;
        final timer = SubscriptionExpiryTimer(() => expired = true);
        try {
          timer.schedule(DateTime.now().add(Duration(days: days)));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(expired, isFalse);
        } finally {
          timer.cancel();
        }
      },
    );

    test('$days-day access survives browser timer overflow until expiry', () {
      fakeAsync((async) {
        var role = 'premium';
        final timer = SubscriptionExpiryTimer(
          () => role = 'free',
          now: async.getClock(start).now,
        );
        // Model the browser's signed-int32 timeout limit, including on the VM.
        runZoned(
          () {
            timer.schedule(start.add(Duration(days: days)));
            async.elapse(const Duration(milliseconds: 1));
            expect(role, 'premium');
            async.elapse(
              Duration(days: days) - const Duration(milliseconds: 2),
            );
            expect(role, 'premium');
            async.elapse(const Duration(milliseconds: 1));
            expect(role, 'free');
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final browserDelay = duration.inMilliseconds > 0x7fffffff
                  ? Duration.zero
                  : duration;
              return parent.createTimer(zone, browserDelay, callback);
            },
          ),
        );
        timer.cancel();
      });
    });
  }

  test('renewal cancels the old expiry and uses the new absolute deadline', () {
    fakeAsync((async) {
      var expirations = 0;
      final timer = SubscriptionExpiryTimer(
        () => expirations++,
        now: async.getClock(start).now,
      );
      timer.schedule(start.add(const Duration(days: 2)));
      async.elapse(const Duration(days: 1));
      timer.schedule(start.add(const Duration(days: 32)));
      async.elapse(const Duration(days: 30));
      expect(expirations, 0);
      async.elapse(const Duration(days: 1));
      expect(expirations, 1);
      async.elapse(const Duration(days: 32));
      expect(expirations, 1);
    });
  });

  test('cancel stops the rearmed timer on revocation or provider disposal', () {
    fakeAsync((async) {
      var expirations = 0;
      final timer = SubscriptionExpiryTimer(
        () => expirations++,
        now: async.getClock(start).now,
      );
      timer.schedule(start.add(const Duration(days: 365)));
      async.elapse(const Duration(days: 26));
      timer.cancel();
      timer.cancel();
      async.elapse(const Duration(days: 400));
      expect(expirations, 0);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'delayed callback after a suspended tab rechecks the absolute expiry',
    () {
      fakeAsync((async) {
        var expired = false;
        final timer = SubscriptionExpiryTimer(
          () => expired = true,
          now: async.getClock(start).now,
        );
        timer.schedule(start.add(const Duration(days: 30)));
        async.elapseBlocking(const Duration(days: 40));
        async.elapse(Duration.zero);
        expect(expired, isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    },
  );

  test('an already expired subscription does not start another wait', () {
    fakeAsync((async) {
      var expired = false;
      final timer = SubscriptionExpiryTimer(
        () => expired = true,
        now: async.getClock(start).now,
      );
      timer.schedule(start.subtract(const Duration(seconds: 1)));
      async.elapse(Duration.zero);
      expect(expired, isTrue);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });
}
