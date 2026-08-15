import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class LadderEmptyStateCard extends StatelessWidget {
  const LadderEmptyStateCard({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color backgroundColor = isDarkMode
        ? Colors.amber.shade900
        : Colors.amber.shade50;
    final Color borderColor = isDarkMode
        ? Colors.amber.shade700
        : Colors.amber.shade300;
    final Color foregroundColor = isDarkMode
        ? Colors.amber.shade100
        : Colors.amber.shade900;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: foregroundColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ladder coming soon',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foregroundColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@Preview(
  name: 'Ladder empty state - light',
  group: 'Ladder',
  size: Size(390, 160),
)
@Preview(
  name: 'Ladder empty state - dark',
  group: 'Ladder',
  size: Size(390, 160),
  brightness: Brightness.dark,
)
Widget ladderEmptyStateCardPreview() {
  return const MaterialApp(
    home: Scaffold(
      body: LadderEmptyStateCard(
        message: 'Standings will appear once Round 1 is complete.',
      ),
    ),
  );
}
