import 'package:cloud_firestore/cloud_firestore.dart';

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
    try {
      final rows = await (_loader != null ? _loader(limit) : _fetchFromFirestore(limit));
      if (rows.isEmpty) {
        return seedQuestions;
      }

      return rows
          .map((row) => QuizQuestion.fromMap(row.key, row.value))
          .toList();
    } catch (_) {
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
