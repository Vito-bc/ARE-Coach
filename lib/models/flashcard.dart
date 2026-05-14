class Flashcard {
  const Flashcard({
    required this.id,
    required this.section,
    required this.front,
    required this.back,
    required this.codeRef,
    required this.examTip,
  });

  final String id;
  final String section;
  final String front;
  final String back;
  final String codeRef;
  final String examTip;

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: json['id'] as String,
        section: json['section'] as String,
        front: json['front'] as String,
        back: json['back'] as String,
        codeRef: json['codeRef'] as String,
        examTip: json['examTip'] as String,
      );
}

enum CardStatus { fresh, learning, mastered }
