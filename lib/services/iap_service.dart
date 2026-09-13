import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'purchase_account.dart';
import 'purchase_environment.dart';

enum PurchasePhase {
  idle,
  starting,
  pending,
  validating,
  restoring,
  verified,
  cancelled,
  empty,
  failed,
  waiting,
}

class PurchaseFlow {
  const PurchaseFlow(this.phase, {this.message, this.uid});
  final PurchasePhase phase;
  final String? message;
  final String? uid;
  bool get busy =>
      phase == PurchasePhase.starting ||
      phase == PurchasePhase.validating ||
      phase == PurchasePhase.restoring;
}

class IAPService {
  IAPService({
    @visibleForTesting InAppPurchase? iap,
    @visibleForTesting http.Client? httpClient,
    @visibleForTesting String? validateReceiptUrlOverride,
    PurchaseEnvironment? environment,
    PurchaseAccount? account,
    @visibleForTesting Duration requestTimeout = const Duration(seconds: 15),
    @visibleForTesting Duration storeTimeout = const Duration(seconds: 45),
  }) : _iap = iap ?? InAppPurchase.instance,
       _fakeStore = iap != null,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _environment = environment ?? PurchaseEnvironment.current,
       _environmentWasImplicit = environment == null,
       _ownsAccount = account == null,
       _account = account ?? FirebasePurchaseAccount(environment: environment),
       _requestTimeout = requestTimeout,
       _storeTimeout = storeTimeout,
       _validateReceiptUrlOverride = validateReceiptUrlOverride;

  static const String kMonthlyId = 'are_coach_monthly';
  static const String kYearlyId = 'are_coach_yearly';

  static const Set<String> _productIds = {kMonthlyId, kYearlyId};

  static const String _envValidateReceiptUrl = String.fromEnvironment(
    'VALIDATE_RECEIPT_URL',
  );

  /// Whether this build is allowed to sell on Android.
  ///
  /// The server can now verify Play purchases, but only once it has been given
  /// a Play service account (`GOOGLE_PLAY_SERVICE_ACCOUNT`). This flag is what
  /// ties the storefront to that configuration: the release workflow sets it
  /// from the `ANDROID_PURCHASES_ENABLED` repo variable, and it defaults to
  /// false so a build that predates the server setup cannot take money.
  static const bool androidPurchasesEnabled = bool.fromEnvironment(
    'ANDROID_PURCHASES_ENABLED',
  );

  static bool get purchasesSupported => computePurchasesSupported(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
    androidEnabled: androidPurchasesEnabled,
    canValidate: _validEndpoint(_envValidateReceiptUrl),
  );

  @visibleForTesting
  static bool computePurchasesSupported({
    required TargetPlatform platform,
    required bool isWeb,
    required bool androidEnabled,
    required bool canValidate,
  }) =>
      !isWeb &&
      canValidate &&
      (platform == TargetPlatform.iOS ||
          platform == TargetPlatform.macOS ||
          (platform == TargetPlatform.android && androidEnabled));

  final InAppPurchase _iap;
  final bool _fakeStore;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final PurchaseAccount _account;
  final bool _ownsAccount;
  final PurchaseEnvironment _environment;
  final bool _environmentWasImplicit;
  final Duration _requestTimeout;
  final Duration _storeTimeout;
  final String? _validateReceiptUrlOverride;
  String get _endpoint =>
      _validateReceiptUrlOverride ?? _environment.validationEndpoint;

  String? get configurationErrorMessage {
    if (_environmentWasImplicit &&
        _validateReceiptUrlOverride != null &&
        _validEndpoint(_endpoint)) {
      return null;
    }
    return _environment.configurationError;
  }

  static bool _validEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  bool get _hasStore =>
      _fakeStore ||
      (!kIsWeb &&
          {
            TargetPlatform.iOS,
            TargetPlatform.macOS,
            TargetPlatform.android,
          }.contains(defaultTargetPlatform));
  String? get currentUid => _account.uid;

  bool get canPurchase =>
      (_fakeStore || purchasesSupported) &&
      _validEndpoint(_endpoint) &&
      configurationErrorMessage == null &&
      _account.uid != null;
  bool get _hasRetryForCurrentAccount {
    final uid = _account.uid;
    return uid != null &&
        _retry.values.any(
          (entry) => entry.ownerUid == uid || entry.attemptUid == uid,
        );
  }

  bool get canStartPurchase =>
      canPurchase &&
      !_disposed &&
      !flow.value.busy &&
      flow.value.phase != PurchasePhase.pending &&
      flow.value.phase != PurchasePhase.waiting &&
      !_hasRetryForCurrentAccount;
  // Restore/recovery must work even when new Android sales are switched off.
  bool get canRestore =>
      _hasStore &&
      _validEndpoint(_endpoint) &&
      configurationErrorMessage == null &&
      _account.uid != null;

  final flow = ValueNotifier<PurchaseFlow>(
    const PurchaseFlow(PurchasePhase.idle),
  );
  final _purchaseController = StreamController<PurchaseDetails>.broadcast();
  Stream<PurchaseDetails> get purchaseUpdates => _purchaseController.stream;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  StreamSubscription<String?>? _authSubscription;
  Future<void>? _initializing;
  Future<void>? _restore;
  bool _disposed = false;
  String? _uid;
  int _epoch = 0;
  Timer? _storeTimer;
  final _inFlight = <String, Future<void>>{};
  final _inFlightAccounts = <String, String>{};
  final _retry = <String, _PurchaseRetry>{};
  final _finished = <String>{};
  final _completions = <String, Future<void>>{};
  int _matchingEvents = 0;
  PurchaseFlow? _announcedSuccess;

  bool takeVerifiedNotice(PurchaseFlow state) {
    if (_disposed ||
        !identical(flow.value, state) ||
        state.phase != PurchasePhase.verified ||
        state.uid != _account.uid ||
        identical(_announcedSuccess, state)) {
      return false;
    }
    _announcedSuccess = state;
    return true;
  }

  Future<void> initialize() {
    if (_disposed || _subscription != null || !_hasStore) return Future.value();
    return _initializing ??= _initialize()
        .catchError((Object _) {
          _fail(
            'store_unavailable',
            'The store could not be initialized. Try again later.',
          );
        })
        .whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    _uid = _account.uid;
    _setFlow(PurchasePhase.idle);
    _authSubscription ??= _account.changes.listen(
      _accountChanged,
      onError: (_) => _accountChanged(null),
    );
    // Subscribe before any store await: StoreKit may deliver immediately.
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object error) => _fail(
        'store_unavailable',
        'The store could not be reached. Try Restore Purchases again.',
      ),
    );
  }

  void _accountChanged(String? uid) {
    if (_disposed || uid == _uid) return;
    _uid = uid;
    _epoch++;
    _storeTimer?.cancel();
    _setFlow(
      PurchasePhase.idle,
      'Account changed. Restore purchases for this account.',
    );
    if (uid != null) unawaited(retryPendingPurchases());
  }

  bool _current(String uid, int epoch) =>
      !_disposed && _account.uid == uid && _uid == uid && _epoch == epoch;

  void _setFlow(PurchasePhase phase, [String? message]) {
    if (!_disposed) {
      flow.value = PurchaseFlow(phase, message: message, uid: _uid);
    }
  }

  void _fail(String code, String message) {
    if (_disposed) return;
    _storeTimer?.cancel();
    _setFlow(PurchasePhase.failed, message);
    _purchaseController.addError(
      IAPError(source: 'purchase_service', code: code, message: message),
    );
  }

  void _waitForStore(PurchasePhase phase, String message) {
    _setFlow(phase, message);
    _storeTimer?.cancel();
    _storeTimer = Timer(_storeTimeout, () {
      _setFlow(
        PurchasePhase.waiting,
        'Still waiting for the store. Check your store account or try Restore Purchases.',
      );
    });
  }

  Future<List<ProductDetails>> loadProducts() async {
    if (!canPurchase || _disposed) return [];
    await initialize();
    if (!await _iap.isAvailable().timeout(_requestTimeout)) return [];
    final response = await _iap
        .queryProductDetails(_productIds)
        .timeout(_requestTimeout);
    if (response.error != null) throw StateError('Store query failed');
    return response.productDetails;
  }

  Future<void> purchaseSubscription(ProductDetails product) async {
    if (configurationErrorMessage != null) {
      throw IAPError(
        source: 'purchase_service',
        code: 'purchase_configuration_invalid',
        message: configurationErrorMessage!,
      );
    }
    if (!canPurchase || _disposed) throw StateError('Purchases unavailable');
    await initialize();
    if (!canStartPurchase) {
      throw IAPError(
        source: 'purchase_service',
        code: 'purchase_unresolved',
        message: 'Resolve the previous purchase with Restore Purchases.',
      );
    }
    final uid = _account.uid!;
    final epoch = _epoch;
    _waitForStore(PurchasePhase.starting, 'Waiting for the store...');
    try {
      final apple =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      final token = apple ? await _prepareApplePurchase(uid, epoch) : null;
      if (!_current(uid, epoch)) return;
      final sent = await _iap
          .buyNonConsumable(
            purchaseParam: PurchaseParam(
              productDetails: product,
              applicationUserName: token,
            ),
          )
          .timeout(_storeTimeout);
      if (_current(uid, epoch) && !sent) {
        _storeTimer?.cancel();
        _setFlow(PurchasePhase.cancelled, 'Purchase was not started.');
      }
    } on TimeoutException {
      if (_current(uid, epoch) &&
          (flow.value.phase == PurchasePhase.starting ||
              flow.value.phase == PurchasePhase.waiting)) {
        _storeTimer?.cancel();
        _setFlow(
          PurchasePhase.waiting,
          'Still waiting for the store. Check your store account or try Restore Purchases.',
        );
      }
    } catch (_) {
      if (_current(uid, epoch)) {
        _fail(
          'purchase_start_failed',
          'Could not start the purchase. Check your store account before trying again.',
        );
      }
    }
  }

  Future<void> restorePurchases() {
    if (_disposed || !canRestore) {
      _fail(
        'restore_unavailable',
        'Restore is unavailable in this build. Sign in and check the store configuration.',
      );
      return Future.value();
    }
    return _restore ??= _restorePurchases().whenComplete(() => _restore = null);
  }

  Future<void> _restorePurchases() async {
    await initialize();
    final uid = _account.uid!;
    final epoch = _epoch;
    final before = _matchingEvents;
    _waitForStore(PurchasePhase.restoring, 'Checking previous purchases...');
    try {
      await retryPendingPurchases();
      if (!_current(uid, epoch)) return;
      await _iap.restorePurchases().timeout(_storeTimeout);
      // Flush the plugin's async broadcast before deciding whether it was empty.
      await Future<void>.delayed(Duration.zero);
      await Future.wait(_inFlight.values.toList());
      if (!_current(uid, epoch)) return;
      _storeTimer?.cancel();
      if (flow.value.phase == PurchasePhase.restoring) {
        _setFlow(
          _matchingEvents == before
              ? PurchasePhase.empty
              : PurchasePhase.waiting,
          _matchingEvents == before
              ? 'No matching purchases were returned by the store.'
              : 'No purchase was confirmed for this account. Sign in to the original account and try Restore Purchases.',
        );
      }
    } catch (_) {
      if (_current(uid, epoch)) {
        _fail(
          'restore_unavailable',
          'Restore could not finish. Try again when the store is available.',
        );
      }
    }
  }

  String _key(PurchaseDetails p) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            p.verificationData.source,
            p.productID,
            p.purchaseID ?? p.verificationData.serverVerificationData,
          ]),
        ),
      )
      .toString();

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    if (_disposed) return;
    // Also catches an auth change before its stream callback was delivered.
    _accountChanged(_account.uid);
    for (final purchase in purchases) {
      if (!_productIds.contains(purchase.productID)) {
        if (purchase.status == PurchaseStatus.canceled ||
            purchase.status == PurchaseStatus.error) {
          unawaited(_finishTerminal(purchase));
        } else if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          // Unknown paid products need a fulfillment/migration policy. Never
          // acknowledge an undelivered purchase merely to clear the queue.
          _fail(
            'unsupported_product',
            'A purchase is not supported by this app version. Update the app or contact support.',
          );
        }
        continue;
      }
      final retry = _retry[_key(purchase)];
      if (retry != null &&
          (!_canRetry(retry, _account.uid) ||
              (retry.ownerUid == null &&
                  retry.attemptUid != _account.uid &&
                  purchase.status != PurchaseStatus.purchased &&
                  purchase.status != PurchaseStatus.restored))) {
        // An unresolved attempt reserves its account's retry gate, but is not
        // ownership proof. A recovery-required response releases that attempt.
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _matchingEvents++;
        _storeTimer?.cancel();
        unawaited(_process(purchase));
      } else if (purchase.status == PurchaseStatus.error) {
        unawaited(_finishTerminal(purchase));
        _fail(
          'purchase_error',
          purchase.error?.message ?? 'Purchase failed. Please try again.',
        );
      } else {
        _storeTimer?.cancel();
        _setFlow(
          purchase.status == PurchaseStatus.pending
              ? PurchasePhase.pending
              : PurchasePhase.cancelled,
          purchase.status == PurchaseStatus.pending
              ? 'Payment is pending in the store. You can leave this screen and check later.'
              : 'Purchase cancelled.',
        );
        if (purchase.status == PurchaseStatus.canceled) {
          unawaited(_finishTerminal(purchase));
        }
        _purchaseController.add(purchase);
      }
    }
  }

  // StoreKit 1 failed/cancelled queue entries must also be finished. This is
  // cleanup of a terminal failure, never a validation or access grant.
  Future<void> _finishTerminal(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase ||
        purchase.verificationData.source != 'app_store') {
      return;
    }
    final uid = _account.uid;
    final epoch = _epoch;
    try {
      await _completionFor(purchase).timeout(_requestTimeout);
    } catch (_) {
      if (uid != null && _current(uid, epoch)) {
        _fail(
          'completion_failed',
          'The store could not clear the cancelled purchase. Try restoring again.',
        );
      }
    }
  }

  Future<void> retryPendingPurchases() async {
    if (_disposed) return;
    final uid = _account.uid;
    if (uid == null) return;
    for (final entry in _retry.values.toList()) {
      if (_canRetry(entry, uid) ||
          (entry.ownerUid == null &&
              _isJws(entry.purchase) &&
              _inFlight.containsKey(_key(entry.purchase)))) {
        await _process(entry.purchase);
      }
    }
  }

  bool _canRetry(_PurchaseRetry entry, String? uid) => entry.ownerUid != null
      ? entry.ownerUid == uid
      : _isJws(entry.purchase) &&
            (entry.attemptUid == null || entry.attemptUid == uid);

  Future<void> _process(PurchaseDetails purchase) {
    final key = _key(purchase);
    final uid = _account.uid;
    final old = _retry[key];
    if (old != null && old.ownerUid != null && old.ownerUid != uid) {
      return Future.value();
    }
    final pending = _inFlight[key];
    if (pending != null) {
      final epoch = _epoch;
      if (_inFlightAccounts[key] == '$uid:$epoch') return pending;
      // Restore may start while the previous account's proof is still pending.
      // Re-evaluate after it settles; never run concurrent validation of the key.
      return pending.then((_) {
        if (uid != null && _current(uid, epoch) && _retry.containsKey(key)) {
          return _process(purchase);
        }
      });
    }
    if (old != null && !_canRetry(old, uid)) return Future.value();
    final completedKey = '$uid:$_epoch:$key';
    if (_finished.contains(completedKey)) {
      // An explicit restore is a new access check, not a second completion.
      if (_restore != null && uid != null) {
        return _inFlight[key] = _refreshRestoredAccess(uid, _epoch)
            .whenComplete(() {
              _inFlight.remove(key);
            });
      }
      return Future.value();
    }
    // First delivery identifies only an attempt account, never a JWS owner.
    // Cold-start/released entries stay unreserved until ownership is proven.
    _retry[key] = _PurchaseRetry(
      purchase,
      ownerUid: old?.ownerUid ?? (_isJws(purchase) ? null : uid),
      attemptUid: old == null ? uid : old.attemptUid,
    );
    _inFlightAccounts[key] = '$uid:$_epoch';
    return _inFlight[key] = _validateAndComplete(purchase, key, uid, _epoch)
        .whenComplete(() {
          _inFlight.remove(key);
          _inFlightAccounts.remove(key);
        });
  }

  Future<void> _refreshRestoredAccess(String uid, int epoch) async {
    try {
      final active = await _account
          .refreshEntitlement(uid)
          .timeout(_requestTimeout);
      if (!_current(uid, epoch)) return;
      if (active) {
        _setFlow(PurchasePhase.verified, 'Premium access confirmed.');
      } else {
        _fail(
          'entitlement_unavailable',
          'No active subscription was confirmed for this account.',
        );
      }
    } catch (_) {
      if (_current(uid, epoch)) {
        _fail(
          'entitlement_unavailable',
          'Subscription access could not be checked. Try Restore Purchases again.',
        );
      }
    }
  }

  Future<void> _validateAndComplete(
    PurchaseDetails purchase,
    String key,
    String? uid,
    int epoch,
  ) async {
    if (!_validEndpoint(_endpoint) || uid == null) {
      _fail(
        'validation_unavailable',
        'Purchase could not be confirmed. Sign in and try Restore Purchases when validation is available.',
      );
      return;
    }
    _setFlow(PurchasePhase.validating, 'Confirming your purchase...');
    final outcome = await _validateWithServer(purchase, uid, epoch);
    if (outcome == _Validation.ownershipRecoveryRequired) {
      final entry = _retry[key];
      if (entry != null && entry.ownerUid == null && entry.attemptUid == uid) {
        // Safe bookkeeping even after a switch: no ownership, UI or entitlement
        // is assigned by a late rejection. The next account can request proof.
        _retry[key] = _PurchaseRetry(purchase);
      }
    }
    if (!_current(uid, epoch)) return;
    if (outcome != _Validation.verified) {
      if (outcome == _Validation.rejected) {
        // A terminal verdict (including an expired restore) must not block a
        // new subscription. Unavailable validation remains retryable.
        _retry.remove(key);
        // Rejection deliberately carries transactionFinalization:not_safe.
        // Even an expired/revoked JWS must not imply finalization policy. Store
        // redelivery may revalidate it while a new purchase is no longer blocked.
      }
      _fail(
        outcome == _Validation.rejected
            ? 'receipt_invalid'
            : 'validation_unavailable',
        outcome == _Validation.rejected
            ? 'Receipt could not be verified. Contact support.'
            : 'We could not confirm your purchase right now. Try Restore Purchases again when the connection is available.',
      );
      return;
    }
    try {
      _retry[key] = _PurchaseRetry(purchase, ownerUid: uid, attemptUid: uid);
      final entitled = _environment.isSandbox
          ? await _sandboxProof(purchase, uid).timeout(_requestTimeout)
          : await _account.refreshEntitlement(uid).timeout(_requestTimeout);
      if (!_current(uid, epoch)) return;
      if (!entitled) {
        _fail(
          'entitlement_unavailable',
          'Your subscription access is not confirmed yet. Try Restore Purchases again.',
        );
        return;
      }
      if (purchase.pendingCompletePurchase) {
        // Keep the underlying future across a timeout. A later retry waits for
        // the same acknowledgment instead of issuing a concurrent second one.
        await _completionFor(purchase).timeout(_requestTimeout);
      }
      if (!_current(uid, epoch)) return;
      _finished.add('$uid:$epoch:$key');
      _retry.remove(key);
      _account.notifyEntitlementChanged(uid);
      _setFlow(PurchasePhase.verified, 'Premium access confirmed.');
      _purchaseController.add(purchase);
    } catch (_) {
      if (_current(uid, epoch)) {
        _fail(
          'purchase_unfinished',
          'Purchase confirmation could not finish. Try Restore Purchases again.',
        );
      }
    }
  }

  Future<void> _completionFor(PurchaseDetails purchase) {
    final key = _key(purchase);
    return _completions.putIfAbsent(
      key,
      () => Future<void>.sync(() => _complete(purchase)).catchError((
        Object error,
        StackTrace stack,
      ) {
        _completions.remove(key);
        Error.throwWithStackTrace(error, stack);
      }),
    );
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (!_fakeStore && purchase is GooglePlayPurchaseDetails) {
      // The generic API returns Future<void> and discards BillingResult.
      final platform =
          InAppPurchasePlatform.instance as InAppPurchaseAndroidPlatform;
      final result = await platform.completePurchase(purchase);
      if (result.responseCode != BillingResponse.ok) {
        throw StateError('Store acknowledgment failed');
      }
    } else {
      await _iap.completePurchase(purchase);
    }
  }

  Future<_Validation> _validateWithServer(
    PurchaseDetails purchase,
    String uid,
    int epoch,
  ) async {
    try {
      final headers = await _account.headers(uid).timeout(_requestTimeout);
      if (!_current(uid, epoch)) return _Validation.unavailable;
      final response = await _httpClient
          .post(
            Uri.parse(_endpoint),
            headers: headers,
            body: jsonEncode({
              'receiptData': purchase.verificationData.serverVerificationData,
              'platform': purchase.verificationData.source,
              if (purchase.verificationData.source == 'app_store') ...{
                'appleEnvironment': _environment.appleName,
                'firebaseProjectId': _environment.firebaseProjectId,
                'entitlementSource': _environment.entitlementSource,
                'receiptFormat': _isJws(purchase)
                    ? 'storekit2_jws'
                    : 'legacy_receipt',
                'transactionId': purchase.purchaseID,
                'productId': purchase.productID,
              },
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        if (_isJws(purchase) && response.statusCode == 503) {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic> &&
              body['outcome'] == 'unavailable' &&
              body['code'] == 'apple_ownership_recovery_required') {
            return _Validation.ownershipRecoveryRequired;
          }
        }
        return _Validation.unavailable;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['valid'] is! bool) {
        return _Validation.unavailable;
      }
      if (purchase.verificationData.source == 'app_store') {
        // Neither HTTP success nor an account-level entitlement proves this
        // individual StoreKit transaction was delivered to its rightful owner.
        if (!_isJws(purchase) ||
            purchase.purchaseID == null ||
            body['uid'] != uid ||
            body['transactionId'] != purchase.purchaseID ||
            body['productId'] != purchase.productID ||
            body['environment'] != _environment.appleName ||
            body['firebaseProjectId'] != _environment.firebaseProjectId ||
            body['entitlementScope'] != _environment.scope) {
          return _Validation.unavailable;
        }
        if (body['valid'] == true &&
            body['outcome'] == 'verified' &&
            body['transactionFinalization'] == 'verified_transaction' &&
            body['expiresAt'] is int &&
            body['expiresAt'] > DateTime.now().millisecondsSinceEpoch) {
          return _Validation.verified;
        }
      } else if (body['valid'] == true) {
        return _Validation.verified;
      }
      if (body['valid'] == false &&
          body['outcome'] == 'not_entitled' &&
          body['transactionFinalization'] == 'not_safe') {
        return _Validation.rejected;
      }
      return _Validation.unavailable;
    } catch (_) {
      return _Validation.unavailable;
    }
  }

  bool _isJws(PurchaseDetails purchase) =>
      purchase.verificationData.source == 'app_store' &&
      (purchase is SK2PurchaseDetails ||
          purchase.verificationData.serverVerificationData.contains('.'));

  Future<String> _prepareApplePurchase(String uid, int epoch) async {
    if (configurationErrorMessage != null) {
      throw StateError(configurationErrorMessage!);
    }
    final headers = await _account.headers(uid).timeout(_requestTimeout);
    if (!_current(uid, epoch)) throw StateError('Account changed');
    final response = await _httpClient
        .post(
          Uri.parse(_endpoint),
          headers: headers,
          body: jsonEncode({
            'platform': 'app_store',
            'action': 'prepare_apple_purchase',
            'appleEnvironment': _environment.appleName,
            'firebaseProjectId': _environment.firebaseProjectId,
            'entitlementSource': _environment.entitlementSource,
          }),
        )
        .timeout(_requestTimeout);
    if (!_current(uid, epoch) || response.statusCode != 200) {
      throw StateError('Purchase preparation unavailable');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['uid'] != uid ||
        body['environment'] != _environment.appleName ||
        body['firebaseProjectId'] != _environment.firebaseProjectId ||
        body['entitlementScope'] != _environment.scope ||
        body['appAccountToken'] is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(body['appAccountToken'])) {
      throw StateError('Purchase preparation invalid');
    }
    return body['appAccountToken'] as String;
  }

  Future<bool> _sandboxProof(PurchaseDetails purchase, String uid) async {
    if (!_environment.isSandbox || purchase.purchaseID == null) return false;
    final proof = await _account.refreshAppleEntitlement(
      uid,
      transactionId: purchase.purchaseID,
      productId: purchase.productID,
    );
    return proof.active &&
        proof.processedTransaction &&
        proof.uid == uid &&
        proof.environment == _environment.appleName &&
        proof.scope == _environment.scope &&
        proof.transactionId == purchase.purchaseID &&
        proof.productId == purchase.productID &&
        proof.expiresAt != null &&
        proof.expiresAt!.isAfter(DateTime.now());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _storeTimer?.cancel();
    _subscription?.cancel();
    _authSubscription?.cancel();
    _purchaseController.close();
    flow.dispose();
    if (_ownsHttpClient) _httpClient.close();
    if (_ownsAccount) _account.dispose();
  }
}

class _PurchaseRetry {
  const _PurchaseRetry(this.purchase, {this.ownerUid, this.attemptUid});
  final PurchaseDetails purchase;
  // For JWS only an exact verified server response can set ownerUid.
  // Legacy/Play keep their previous captured-account behavior.
  final String? ownerUid;
  final String? attemptUid;
}

enum _Validation { verified, rejected, unavailable, ownershipRecoveryRequired }
