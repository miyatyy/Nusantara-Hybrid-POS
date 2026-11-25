import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/speech_service.dart';
import '../services/localization_service.dart';
import '../models/menu_item.dart';
import '../models/raw_material.dart';
import '../state/pos_state.dart';
import '../theme/app_theme.dart';

class AiOrderBox extends StatefulWidget {
  final List<MenuItem> menuItems;
  final Map<String, RawMaterial> rawStockMap;
  final Function(double? cashReceived)? onCashDetected;

  const AiOrderBox({
    super.key,
    required this.menuItems,
    required this.rawStockMap,
    this.onCashDetected,
  });

  @override
  State<AiOrderBox> createState() => _AiOrderBoxState();
}

class _AiOrderBoxState extends State<AiOrderBox> {
  final TextEditingController _controller = TextEditingController();
  final SpeechService _speech = SpeechService();
  final AiService _ai = AiService();
  bool _isProcessing = false;

  final List<String> _samplePrompts = [
    '2 Palm Sugar Latte less ice, 1 Croissant, cash 100k',
    '1 Nasi Ayam Sambal Matah, 1 Es Teh Melati',
    '2 Kyoto Matcha Latte, 1 Pisang Madu, bayar 100rb',
    '1 Paket Semangat Pagi, cash 50k',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleVoiceDictation() async {
    if (_speech.isListening) {
      await _speech.stopListening();
    } else {
      final loc = LocalizationService();
      final localeCode = loc.isIndonesian ? 'id_ID' : 'en_US';

      await _speech.startListening(
        localeId: localeCode,
        onResult: (words) {
          setState(() {
            _controller.text = words;
          });
        },
      );
    }
    setState(() {});
  }

  Future<void> _processAiOrder([String? customPrompt]) async {
    final text = customPrompt ?? _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _ai.parseNaturalOrder(
        prompt: text,
        menuItems: widget.menuItems,
        rawStockMap: widget.rawStockMap,
        mode: InferenceMode.preferOnDevice,
      );

      final posState = PosState();
      for (final orderItem in result.items) {
        posState.addToCart(
          orderItem.menuItem,
          quantity: orderItem.quantity,
          notes: orderItem.notes,
        );
      }

      if (result.cashReceived != null) {
        widget.onCashDetected?.call(result.cashReceived);
      }

      if (mounted) {
        final engineDesc = result.engineUsed == 'ON_DEVICE'
            ? 'Local: Gemini Nano'
            : 'Cloud: Gemini 3.8 Flash';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.royalBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.brightYellow),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Added ${result.items.length} item(s) to Cart via $engineDesc',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('AI Order Parse Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService();
    final hint = loc.isIndonesian
        ? 'Pesan AI: 2 Latte, 1 Croissant...'
        : 'AI Order: 2 Latte, 1 Croissant...';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slim, Compact Single-Row Pill Bar (Height: 46)
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: AppTheme.royalBlue.withAlpha(140), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.royalBlue.withAlpha(18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: AppTheme.royalBlue,
                ),
                const SizedBox(width: 8),

                // Compact Input Field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkNavy,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _processAiOrder(),
                  ),
                ),

                // Inline Mic Icon Button
                IconButton(
                  onPressed: _handleVoiceDictation,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    _speech.isListening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _speech.isListening ? AppTheme.roseRed : AppTheme.cobaltBlue,
                    size: 19,
                  ),
                  tooltip: _speech.isListening ? tr('voice_stop') : tr('voice_start'),
                ),

                // Small Golden Yellow Pill Button
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isProcessing ? null : () => _processAiOrder(),
                      borderRadius: BorderRadius.circular(18),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppTheme.goldenAmber,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.goldenAmber.withAlpha(100),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isProcessing)
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: AppTheme.darkNavy,
                                ),
                              )
                            else
                              const Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: AppTheme.darkNavy,
                              ),
                            const SizedBox(width: 3),
                            Text(
                              loc.isIndonesian ? 'Pesan AI' : 'AI Order',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.darkNavy,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 5),

          // Slim Horizontal Row of Quick Sample Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.royalBlue.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Quick:',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                ),
                ..._samplePrompts.map((prompt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: ActionChip(
                      label: Text(
                        prompt,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppTheme.lightBlueTint,
                      side: BorderSide(color: AppTheme.blueSubtle.withAlpha(180)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onPressed: () {
                        _controller.text = prompt;
                        _processAiOrder(prompt);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
