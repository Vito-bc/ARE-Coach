import 'coach_source.dart';

/// A successful Coach response: the same `answer` / `grounded` / `sources`
/// triple the HTTP endpoint returns (functions/index.js askCoach response
/// body), carried through instead of discarded so the caller can render
/// citations.
class CoachAnswer {
  const CoachAnswer({
    required this.answer,
    required this.grounded,
    required this.sources,
  });

  final String answer;
  final bool grounded;

  /// In backend retrieval order -- the model's inline "[Source N]" labels
  /// refer to this order, so it must never be sorted, filtered, or re-ranked.
  final List<CoachSource> sources;
}
