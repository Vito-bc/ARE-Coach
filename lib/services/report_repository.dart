import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

enum FlagReason { incorrectAnswer, outdated, unclearWording, other }

extension FlagReasonLabel on FlagReason {
  String get label {
    switch (this) {
      case FlagReason.incorrectAnswer:
        return 'Incorrect answer';
      case FlagReason.outdated:
        return 'Outdated';
      case FlagReason.unclearWording:
        return 'Unclear wording';
      case FlagReason.other:
        return 'Other';
    }
  }

  String get value {
    switch (this) {
      case FlagReason.incorrectAnswer:
        return 'incorrect_answer';
      case FlagReason.outdated:
        return 'outdated';
      case FlagReason.unclearWording:
        return 'unclear_wording';
      case FlagReason.other:
        return 'other';
    }
  }
}

class ReportRepository {
  final _db = FirebaseFirestore.instance;

  Future<void> flagQuestion({
    required String uid,
    required String questionId,
    required String questionText,
    required FlagReason reason,
    String? comment,
  }) async {
    try {
      await _db.collection('reports').add({
        'uid': uid,
        'questionId': questionId,
        'questionText': questionText,
        'reason': reason.value,
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stack) {
      try {
        FirebaseCrashlytics.instance.recordError(e, stack);
      } catch (_) {}
      rethrow;
    }
  }
}
