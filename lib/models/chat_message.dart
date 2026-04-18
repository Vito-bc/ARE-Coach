enum ChatRole { user, coach, error }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.time,
  });

  final ChatRole role;
  final String text;
  final DateTime time;
}
