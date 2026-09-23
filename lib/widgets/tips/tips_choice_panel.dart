import 'package:flutter/material.dart';
import 'tips_card_layout.dart';

/// The existing 2 / 1 / 2 panel, with inline and vertical alternatives.
/// Callers supply chips so selection, saving and percentage logic stay separate.
class TipsChoicePanel extends StatelessWidget {
  const TipsChoicePanel({
    super.key,
    required this.children,
    this.arrangement = TipsChoiceArrangement.paired,
  }) : assert(children.length == 5);

  final List<Widget> children;
  final TipsChoiceArrangement arrangement;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: switch (arrangement) {
        TipsChoiceArrangement.paired => Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                children[0], const SizedBox(width: 8), children[1],
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [children[2]]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              children[3], const SizedBox(width: 8), children[4],
            ]),
          ],
        ),
        TipsChoiceArrangement.inline => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 8), children[index],
            ],
          ]),
        ),
        TipsChoiceArrangement.vertical => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final child in children)
              ConstrainedBox(constraints: const BoxConstraints(minHeight: 48),
                child: child)],
          ),
        ),
      },
    );
  }
}
