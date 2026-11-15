import 'dart:async';
import 'dart:io';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Registers a [TeamLogosViewModel] serving the seed logos in `team_logos/`,
/// so widget and golden tests draw real team logos rather than initials.
///
/// The value arrives on the next microtask; pump before matching goldens.
TeamLogosViewModel registerSeedTeamLogos() {
  final Map<String, Map<String, String>> logos = {
    for (final File file in Directory(
      'team_logos',
    ).listSync().whereType<File>())
      if (file.path.endsWith('.svg'))
        file.uri.pathSegments.last.replaceFirst(RegExp(r'\.svg$'), ''): {
          teamLogoSvgKey: file.readAsStringSync(),
        },
  };
  final TeamLogosViewModel teamLogos = TeamLogosViewModel(
    source: () => Stream<Object?>.value(logos),
  );
  di.registerSingleton<TeamLogosViewModel>(
    teamLogos,
    dispose: (viewModel) => viewModel.dispose(),
  );
  return teamLogos;
}
