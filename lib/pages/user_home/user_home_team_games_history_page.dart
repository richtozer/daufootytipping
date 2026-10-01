import 'dart:math' as math;
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

class TeamGamesHistoryPage extends StatefulWidget {
  final Team team;
  final League league;

  const TeamGamesHistoryPage({
    super.key,
    required this.team,
    required this.league,
  });

  @override
  State<TeamGamesHistoryPage> createState() => _TeamGamesHistoryPageState();
}

class _TeamGamesHistoryPageState extends State<TeamGamesHistoryPage> {
  bool _isLoading = true;
  List<TeamGameHistoryItem> _gameHistory = [];
  String? _error;
  int? _sortColumnIndex;
  bool _sortAscending = false;

  static const columns = [
    AppColumn.text('Date', sortable: true),
    AppColumn.text('Result', sortable: true),
    AppColumn.text('Opponent', grow: true, sortable: true),
    AppColumn.numeric('Score', sortable: true),
    AppColumn.numeric('Round', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final values = <Object?>[
      body, scaler, direction, DateTime.now().year,
      for (final game in _gameHistory) ...[
        game.gameDate, game.result, game.opponentName, game.opponentLogoUri,
        game.teamScore, game.opponentScore, game.roundNumber, game.isHomeGame,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(text: TextSpan(text: text, style: style),
        textScaler: scaler, textDirection: direction)..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }
    _rows = [
      for (final game in _gameHistory) (() {
        final badge = measure(game.isHomeGame ? 'Home' : 'Away',
          body.copyWith(fontSize: 10, fontWeight: FontWeight.w500));
        final round = measure('R${game.roundNumber}', body);
        final roundSize = Size(badge.width + 10 + 6 + round.width,
          math.max(badge.height + 4, round.height));
        final (colour, icon) = switch (game.result) {
          'Won' => (Colors.green, Icons.check_circle),
          'Lost' => (Colors.red, Icons.cancel),
          'Draw' => (Colors.orange, Icons.remove_circle),
          _ => (Colors.grey, Icons.help),
        };
        return AppRow(cells: [
          AppCell.text(_formatDate(game.gameDate)),
          AppCell.text(game.result,
            style: TextStyle(color: colour, fontWeight: FontWeight.w500),
            leading: Icon(icon, color: colour, size: 14),
            leadingSize: const Size(14, 14)),
          AppCell.text(game.opponentName, style: const TextStyle(fontWeight: FontWeight.w500),
            leading: game.opponentLogoUri != null && game.opponentLogoUri!.isNotEmpty
                ? SvgPicture.asset(game.opponentLogoUri!, width: 20, height: 20,
                    placeholderBuilder: (_) => const Icon(Icons.shield, size: 20, color: Colors.grey))
                : const Icon(Icons.shield, size: 20, color: Colors.grey),
            leadingSize: const Size(20, 20)),
          AppCell.text('${game.teamScore} - ${game.opponentScore}'),
          AppCell.widget(Row(mainAxisSize: MainAxisSize.min, children: [
            _buildHomeAwayBadge(game), const SizedBox(width: 6),
            Text('R${game.roundNumber}', style: body),
          ]), intrinsicSize: roundSize,
            semanticLabel: '${game.isHomeGame ? 'Home' : 'Away'}, Round ${game.roundNumber}'),
        ]);
      })(),
    ];
    return _rows;
  }

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

      _gameHistory.sort((a, b) {
        int compareResult = 0;
        switch (columnIndex) {
          case 0: // Date
            compareResult = a.gameDate.compareTo(b.gameDate);
            break;
          case 1: // Result
            compareResult = a.result.compareTo(b.result);
            break;
          case 2: // Opponent
            compareResult = a.opponentName.compareTo(b.opponentName);
            break;
          case 3: // Score
            final aTotal = a.teamScore + a.opponentScore;
            final bTotal = b.teamScore + b.opponentScore;
            compareResult = aTotal.compareTo(bTotal);
            break;
          case 4: // Round
            compareResult = a.roundNumber.compareTo(b.roundNumber);
            break;
        }
        return ascending ? compareResult : -compareResult;
      });
    });
  }

  Widget _buildHomeAwayBadge(TeamGameHistoryItem game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: game.isHomeGame
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: game.isHomeGame
              ? Colors.blue.withValues(alpha: 0.3)
              : Colors.purple.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
        game.isHomeGame ? 'Home' : 'Away',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: game.isHomeGame ? Colors.blue[700] : Colors.purple[700],
        ),
      ),
    );
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
    final orientation = MediaQuery.of(context).orientation;

    return SelectedCompBanner(
      child: Scaffold(
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => Navigator.pop(context),
          backgroundColor: Colors.lightGreen[200],
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: const Icon(Icons.arrow_back),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (orientation == Orientation.portrait)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Hero(
                            tag: 'team_icon_${widget.team.dbkey}',
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${widget.team.name} - Game History',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Matchup history for the ${widget.team.name} across recent years. Tap column headings to sort.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
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
                          sort: _sortColumnIndex == null ? null
                              : AppSort(column: _sortColumnIndex!, ascending: _sortAscending),
                          onSort: _onSort,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
