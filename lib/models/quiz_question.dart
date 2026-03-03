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
  });

  final String id;
  final String section;
  final String question;
  final List<String> options;
  final String correctOption;
  final String explanation;
  final String codeReference;
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
      'difficulty': 'medium',
      'state': state,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
