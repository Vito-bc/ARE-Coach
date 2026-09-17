import 'coach_source.dart';

enum ChatRole { user, coach, error }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.time,
    this.sources = const [],
    this.grounded = true,
  });

  final ChatRole role;
  final String text;
  final DateTime time;

  /// Citations for a coach answer, in the exact order the backend returned
  /// them -- the model's inline "[Source N]" labels refer to this order, so
  /// it must never be sorted, filtered, or re-ranked here. Empty for
  /// user/error messages and for coach messages that never came from a live
  /// Coach call (the welcome banner, the demo reply).
  final List<CoachSource> sources;

  /// Whether this coach answer was grounded in a retrieved source. Only
  /// meaningful for role == ChatRole.coach; defaults to true so messages
  /// that never came from a live Coach call don't trigger the "ungrounded"
  /// treatment.
  final bool grounded;
}
