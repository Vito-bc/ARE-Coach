import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/seed_questions.dart';
import '../models/quiz_question.dart';

typedef QuestionLoader = Future<List<MapEntry<String, Map<String, dynamic>>>> Function(int limit);

class QuestionRepository {
  QuestionRepository({
    FirebaseFirestore? firestore,
    QuestionLoader? loader,
  })  : _providedFirestore = firestore,
        _loader = loader;

  final FirebaseFirestore? _providedFirestore;
  final QuestionLoader? _loader;
  FirebaseFirestore get _firestore => _providedFirestore ?? FirebaseFirestore.instance;

  Future<List<QuizQuestion>> loadNyQuestions({int limit = 20}) async {
    // 1. Try Firestore first (3s timeout — fall back fast if empty/unavailable)
    try {
      final rows = await (_loader != null ? _loader(limit) : _fetchFromFirestore(limit))
          .timeout(const Duration(seconds: 3));
      if (rows.isNotEmpty) {
        return rows.map((row) => QuizQuestion.fromMap(row.key, row.value)).toList();
      }
    } catch (e) {
      debugPrint('loadNyQuestions: Firestore unavailable, falling back to asset ($e)');
    }

    // 2. Fall back to bundled JSON asset
    try {
      final jsonStr = await rootBundle.loadString('assets/seeds/questions_ny.json');
      final List<dynamic> raw = json.decode(jsonStr);
      final questions = raw
          .map((e) => QuizQuestion.fromMap(e['id'] as String, e as Map<String, dynamic>))
          .toList();
      if (limit > 0 && questions.length > limit) {
        questions.shuffle();
        return questions.take(limit).toList();
      }
      return questions;
    } catch (e, stack) {
      debugPrint('loadNyQuestions: bundled asset failed, falling back to seed ($e)');
      try { FirebaseCrashlytics.instance.recordError(e, stack); } catch (_) {}
    }

    // 3. Last resort — 3 hardcoded questions
    return seedQuestions;
  }

  /// Load directly from bundled JSON asset — no Firestore needed.
  Future<List<QuizQuestion>> loadFromAsset({int limit = 20}) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/seeds/questions_ny.json');
      final List<dynamic> raw = json.decode(jsonStr);
      final questions = raw
          .map((e) => QuizQuestion.fromMap(e['id'] as String, e as Map<String, dynamic>))
          .toList()
        ..shuffle();
      return limit > 0 && questions.length > limit
          ? questions.take(limit).toList()
          : questions;
    } catch (e, stack) {
      debugPrint('loadFromAsset failed, falling back to seed ($e)');
      try { FirebaseCrashlytics.instance.recordError(e, stack); } catch (_) {}
      return seedQuestions;
    }
  }

  Future<List<MapEntry<String, Map<String, dynamic>>>> _fetchFromFirestore(int limit) async {
    final query = await _firestore
        .collection('questions')
        .where('state', isEqualTo: 'NY')
        .limit(limit)
        .get();
    return query.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
  }
}
