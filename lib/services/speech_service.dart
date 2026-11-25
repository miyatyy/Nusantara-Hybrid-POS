import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final ValueNotifier<bool> isListeningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> wordsSpokenNotifier = ValueNotifier<String>('');
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => isListeningNotifier.value;

  Future<bool> init() async {
    try {
      _isAvailable = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech error: $val');
          isListeningNotifier.value = false;
        },
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (val == 'done' || val == 'notListening') {
            isListeningNotifier.value = false;
          }
        },
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('Speech init exception: $e');
      _isAvailable = false;
      return false;
    }
  }

  Future<void> startListening({
    required Function(String text) onResult,
    String localeId = 'id_ID',
  }) async {
    if (!_isAvailable) {
      final available = await init();
      if (!available) {
        onResult('Dictation not available on device');
        return;
      }
    }

    try {
      isListeningNotifier.value = true;
      wordsSpokenNotifier.value = '';
      await _speech.listen(
        onResult: (result) {
          wordsSpokenNotifier.value = result.recognizedWords;
          onResult(result.recognizedWords);
          if (result.finalResult) {
            isListeningNotifier.value = false;
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('startListening error: $e');
      isListeningNotifier.value = false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
      isListeningNotifier.value = false;
    } catch (_) {}
  }
}
