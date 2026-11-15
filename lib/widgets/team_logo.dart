import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

/// A team's logo, drawn from the SVG stored at `/TeamLogos/{teamDbKey}`.
///
/// Shows the team's initials in a badge while logos load, when the team has
/// no logo yet (a new club), and when the stored SVG cannot be drawn.
class TeamLogo extends StatelessWidget {
  /// Creates the logo for the team stored under [teamDbKey].
  const TeamLogo({
    super.key,
    required this.teamDbKey,
    required this.teamName,
    required this.size,
  });

  /// The team's database key, for example `nrl-Broncos`.
  final String teamDbKey;

  /// The team's display name, used for the initials badge.
  final String teamName;

  /// The logo's width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!di.isRegistered<TeamLogosViewModel>()) {
      return _logoFor(null);
    }
    final TeamLogosViewModel logos = di<TeamLogosViewModel>();
    return ListenableBuilder(
      listenable: logos,
      builder: (context, _) => _logoFor(logos.svgFor(teamDbKey)),
    );
  }

  Widget _logoFor(String? svg) {
    final Widget badge = TeamInitialsBadge(teamName: teamName, size: size);
    if (svg == null) return badge;
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      semanticsLabel: teamName,
      placeholderBuilder: (_) => badge,
      errorBuilder: (_, _, _) => badge,
    );
  }
}

/// A round badge with up to two initials of [teamName].
class TeamInitialsBadge extends StatelessWidget {
  /// Creates the badge for [teamName] at [size].
  const TeamInitialsBadge({
    super.key,
    required this.teamName,
    required this.size,
  });

  /// The team's display name.
  final String teamName;

  /// The badge's width and height.
  final double size;

  /// The first letter of each of the first two words of [teamName].
  static String initialsOf(String teamName) => teamName
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      label: teamName,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.all(size * 0.18),
            child: Text(
              initialsOf(teamName),
              style: TextStyle(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
