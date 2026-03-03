import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/seed_questions.dart';
import '../models/quiz_question.dart';

class QuestionRepository {
  QuestionRepository({FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore => _providedFirestore ?? FirebaseFirestore.instance;

  Future<List<QuizQuestion>> loadNyQuestions({int limit = 20}) async {
    try {
      final query = await _firestore
          .collection('questions')
          .where('state', isEqualTo: 'NY')
          .limit(limit)
          .get();

      if (query.docs.isEmpty) {
        return seedQuestions;
      }

      return query.docs
          .map((doc) => QuizQuestion.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return seedQuestions;
    }
  }
}
