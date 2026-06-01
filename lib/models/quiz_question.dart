class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.section,
    required this.question,
    required this.options,
    required this.correctOption,
    required this.explanation,
    required this.codeReference,
    required this.examWeight,
    this.topic,
    this.difficulty,
  });

  final String id;
  final String section;
  final String question;
  final List<String> options;
  final String correctOption;
  final String explanation;
  final String codeReference;

  /// NCARB-aligned sub-topic within the division (e.g. "Egress & Life Safety").
  /// Null for legacy questions that pre-date topic tagging.
  final String? topic;

  /// Difficulty tier: 'easy', 'medium', or 'hard'.
  final String? difficulty;

  /// Relative topic priority for study selection and analytics.
  ///
  /// Not a point value; not an NCARB scoring percentage.
  /// Scale 1-20: higher = more exam-critical / high-yield / code-risk topic.
  final int examWeight;

  factory QuizQuestion.fromMap(String id, Map<String, dynamic> data) {
    final options = (data['options'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
    return QuizQuestion(
      id: id,
      section: data['section']?.toString() ?? 'Unknown',
      question: data['question']?.toString() ?? '',
      options: options,
      correctOption: data['correctOption']?.toString() ?? '',
      explanation: data['explanation']?.toString() ?? '',
      codeReference: data['codeReference']?.toString() ?? '',
      examWeight: (data['examWeight'] as num?)?.toInt() ?? 0,
      topic: data['topic']?.toString(),
      difficulty: data['difficulty']?.toString(),
    );
  }

  Map<String, dynamic> toMap({String state = 'NY'}) {
    return {
      'section': section,
      'question': question,
      'options': options,
      'correctOption': correctOption,
      'explanation': explanation,
      'codeReference': codeReference,
      'examWeight': examWeight,
      if (topic != null) 'topic': topic,
      'difficulty': difficulty ?? 'medium',
      'state': state,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
