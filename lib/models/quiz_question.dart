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
}
