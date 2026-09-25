import 'dart:developer';

import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:flutter/material.dart';

/// Submits a tip, with the permission, timing and God Mode checks the tip
/// buttons have always applied. Presentation lives in the adaptive card; this
/// keeps the rules in one place for whichever surface offers the choice.
Future<void> submitTip(
  BuildContext context,
  GameTipViewModel gameTipViewModel,
  GameResult option,
) async {
  if (gameTipViewModel.currentTipper.isAnonymous) {
    _notify(
      context,
      Colors.orange,
      'Read-only mode: Tipping is disabled for anonymous users.',
    );
    return;
  }

  try {
    if (gameTipViewModel.allTipsViewModel.tipperViewModel.inGodMode) {
      await _confirmGodModeTip(context, gameTipViewModel, option);
      return;
    }

    if (gameTipViewModel.game.gameState == GameState.startedResultKnown ||
        gameTipViewModel.game.gameState == GameState.startedResultNotKnown) {
      _notify(context, Colors.red, 'Tipping for this game has closed.');
      return;
    }

    final existing = gameTipViewModel.tip;
    if (existing != null && existing.tip == option) {
      final label = gameTipViewModel.game.league == League.afl
          ? existing.tip.aflTooltip
          : existing.tip.nrlTooltip;
      _notify(
        context,
        Colors.orange,
        'Your tip [$label] has already been submitted.',
      );
      return;
    }

    await gameTipViewModel.addTip(_tipFor(gameTipViewModel, option));
  } catch (e) {
    final message = 'Error submitting tip: $e';
    log(message);
    if (!context.mounted) {
      return;
    }
    _notify(context, Colors.red, message);
  }
}

Future<void> _confirmGodModeTip(
  BuildContext context,
  GameTipViewModel gameTipViewModel,
  GameResult option,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      icon: const Icon(Icons.warning),
      iconColor: Colors.red,
      title: const Text('Warning: God Mode'),
      content: const Text(
        'You are tipping in God Mode. Are you sure you want to submit this '
        'tip? You cannot revert back to no tip, but you can change this tip '
        'later if needed.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Submit'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await gameTipViewModel.addTip(_tipFor(gameTipViewModel, option));
  }
}

Tip _tipFor(GameTipViewModel gameTipViewModel, GameResult option) => Tip(
  tipper: gameTipViewModel.currentTipper,
  game: gameTipViewModel.game,
  tip: option,
  submittedTimeUTC: DateTime.now().toUtc(),
);

void _notify(BuildContext context, Color background, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(backgroundColor: background, content: Text(message)));
}
