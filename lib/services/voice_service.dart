import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  VoiceService()
      : _speechToText = SpeechToText(),
        _flutterTts = FlutterTts();

  final SpeechToText _speechToText;
  final FlutterTts _flutterTts;

  Future<bool> init() async {
    final available = await _speechToText.initialize();
    await _flutterTts.setSpeechRate(0.46);
    return available;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> listen({
    required void Function(String words) onResult,
  }) async {
    if (!_speechToText.isAvailable) {
      final ok = await _speechToText.initialize();
      if (!ok) return;
    }

    await _speechToText.listen(
      onResult: (result) => onResult(result.recognizedWords),
      listenOptions: SpeechListenOptions(partialResults: true),
      localeId: 'en_US',
    );
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
  }

  Future<void> dispose() async {
    await _speechToText.stop();
    await _flutterTts.stop();
  }
}
