import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

class LanguageTogglePill extends StatelessWidget {
  const LanguageTogglePill({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService();

    return ValueListenableBuilder<String>(
      valueListenable: locService.currentLanguage,
      builder: (context, lang, child) {
        final isEn = lang == 'en';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(35),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.brightYellow.withAlpha(150),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOption(
                label: 'EN',
                selected: isEn,
                onTap: () => locService.setLanguage('en'),
              ),
              _buildOption(
                label: 'ID',
                selected: !isEn,
                onTap: () => locService.setLanguage('id'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brightYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: selected ? AppTheme.darkNavy : Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
