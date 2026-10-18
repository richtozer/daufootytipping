import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_under_controls_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

class TeamGamesHistoryPage extends StatefulWidget {
  final Team team;
  final League league;

  /// The Hero tag the logo flew in with, when the caller's own tag differs
  /// from this page's. Defaults to the team's own tag.
  final String? heroTag;

  const TeamGamesHistoryPage({
    super.key,
    required this.team,
    required this.league,
    this.heroTag,
  });

  @override
  State<TeamGamesHistoryPage> createState() => _TeamGamesHistoryPageState();
}

class _TeamGamesHistoryPageState extends State<TeamGamesHistoryPage> {
  bool _isLoading = true;
  List<TeamGameHistoryItem> _gameHistory = [];
  String? _error;
  // Arrives newest first, which is Date descending; say so in the heading,
  // and sort on load so the heading is telling the truth.
  int? _sortColumnIndex = 0;
  bool _sortAscending = false;

  static const columns = [
    AppColumn.text('Date', sortable: true, descendingFirst: true),
    AppColumn.text('Opponent', sortable: true),
    AppColumn.numeric('Score', sortable: true),
    AppColumn.numeric('Round', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final body =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final values = <Object?>[
      body,
      scaler,
      direction,
      isDarkMode,
      DateTime.now().year,
      for (final game in _gameHistory) ...[
        game.gameDate,
        game.result,
        game.opponentName,
        game.opponentLogoUri,
        game.teamScore,
        game.opponentScore,
        game.roundNumber,
        game.isHomeGame,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    // The ladder's own shading marks what matters there; here it marks a win.
    final winColour = isDarkMode
        ? Colors.lightGreen[900]
        : Colors.lightGreen[200];
    _rows = [
      for (final game in _gameHistory)
        AppRow(
          colour: game.result == 'Won' ? winColour : null,
          cells: [
            AppCell.text(_formatDate(game.gameDate)),
            AppCell.text(
              // The notation of a results table: v at home, @ away.
              '${game.isHomeGame ? 'v' : '@'} ${game.opponentName}',
              semanticLabel:
                  '${game.isHomeGame ? 'Home against' : 'Away at'} ${game.opponentName}',
              style: const TextStyle(fontWeight: FontWeight.w500),
              leading:
                  game.opponentLogoUri != null &&
                      game.opponentLogoUri!.isNotEmpty
                  ? SvgPicture.asset(
                      game.opponentLogoUri!,
                      width: 20,
                      height: 20,
                      placeholderBuilder: (_) => const Icon(
                        Icons.shield,
                        size: 20,
                        color: Colors.grey,
                      ),
                    )
                  : const Icon(Icons.shield, size: 20, color: Colors.grey),
              leadingSize: const Size(20, 20),
            ),
            AppCell.text(
              '${_resultInitial(game.result)} ${game.teamScore}\u2013${game.opponentScore}',
              semanticLabel:
                  '${game.result}, ${game.teamScore} to ${game.opponentScore}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            AppCell.text('R${game.roundNumber}'),
          ],
        ),
    ];
    return _rows;
  }

  String _resultInitial(String result) => switch (result) {
    'Won' => 'W',
    'Lost' => 'L',
    'Draw' => 'D',
    _ => '',
  };

  @override
  void initState() {
    super.initState();
    _fetchGameHistory();
  }

  Future<void> _fetchGameHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final gamesViewModel = di<DAUCompsViewModel>().gamesViewModel;
      final history = await gamesViewModel!.getCompleteTeamGameHistory(
        widget.team,
        widget.league,
      );
      if (mounted) {
        setState(() {
          _gameHistory = history;
          _applySort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSort(int columnIndex, bool ascending) {
    if (_gameHistory.isEmpty) return;

    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort();
    });
  }

  /// Puts the rows in the order the heading claims they are in, rather than
  /// trusting whatever order they arrived in to match.
  void _applySort() {
    final int? columnIndex = _sortColumnIndex;
    if (columnIndex == null) return;
    final bool ascending = _sortAscending;
    _gameHistory.sort((a, b) {
      int compareResult = 0;
      switch (columnIndex) {
        case 0: // Date
          compareResult = a.gameDate.compareTo(b.gameDate);
          break;
        case 1: // Opponent
          compareResult = a.opponentName.compareTo(b.opponentName);
          break;
        case 2: // Score, by the margin the team won or lost by
          compareResult = (a.teamScore - a.opponentScore).compareTo(
            b.teamScore - b.opponentScore,
          );
          break;
        case 3: // Round
          compareResult = a.roundNumber.compareTo(b.roundNumber);
          break;
      }
      return ascending ? compareResult : -compareResult;
    });
  }

  String _formatDate(DateTime date) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final isCurrentYear = date.year == DateTime.now().year;
    final day = date.day.toString().padLeft(2, '0');
    final month = monthNames[date.month - 1];

    if (isCurrentYear) {
      return '$day $month';
    }
    return '$day $month ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SelectedCompBanner(
      child: Scaffold(
        body: AppUnderControlsArea(
          child: AppTableFrame(
            columns: columns,
            rows: _tableRows(context),
            frozenLeading: 1,
            heading: AppTableHeading(
              leading: Hero(
                tag: widget.heroTag ?? teamHeroTag(widget.team.dbkey),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child:
                      widget.team.logoURI != null &&
                          widget.team.logoURI!.isNotEmpty
                      ? SvgPicture.asset(
                          widget.team.logoURI!,
                          placeholderBuilder: (context) =>
                              const Icon(Icons.shield),
                        )
                      : const Icon(Icons.shield),
                ),
              ),
              title: '${widget.team.name} - Game History',
              description:
                  'Matchup history for the ${widget.team.name} across recent years. Green shading marks games won by the ${widget.team.name}. Tap column headings to sort.',
            ),
            table: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _gameHistory.isEmpty
                ? const Center(
                    child: Text('No game history available for this team.'),
                  )
                : Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: AppTable(
                      columns: columns,
                      rows: _tableRows(context),
                      frozenLeading: 1,
                      sort: _sortColumnIndex == null
                          ? null
                          : AppSort(
                              column: _sortColumnIndex!,
                              ascending: _sortAscending,
                            ),
                      onSort: _onSort,
                      scrollbarColour: widget.league.colour,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
