import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// Stands in for a stats page's table or list while it has nothing to show,
/// such as before a new comp's first game is scored.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, required this.message});

  /// What is coming, for example "Ladder coming soon".
  final String title;

  /// When it will appear.
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

    // It sits where the table would start and keeps to its message's height
    // rather than filling the table's slot.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardCornerRadius),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: foregroundColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
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
      ),
    );
  }
}

@Preview(name: 'Empty state - light', group: 'Stats', size: Size(390, 160))
@Preview(
  name: 'Empty state - dark',
  group: 'Stats',
  size: Size(390, 160),
  brightness: Brightness.dark,
)
Widget emptyStateCardPreview() {
  return const MaterialApp(
    home: Scaffold(
      body: EmptyStateCard(
        title: 'Ladder coming soon',
        message: 'Standings will appear once Round 1 is complete.',
      ),
    ),
  );
}
