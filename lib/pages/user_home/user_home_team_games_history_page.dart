import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
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

  Widget _buildResultCell(TeamGameHistoryItem game) {
    Color resultColor;
    IconData resultIcon;

    switch (game.result) {
      case 'Won':
        resultColor = Colors.green;
        resultIcon = Icons.check_circle;
        break;
      case 'Lost':
        resultColor = Colors.red;
        resultIcon = Icons.cancel;
        break;
      case 'Draw':
        resultColor = Colors.orange;
        resultIcon = Icons.remove_circle;
        break;
      default:
        resultColor = Colors.grey;
        resultIcon = Icons.help;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(resultIcon, color: resultColor, size: 14),
        const SizedBox(width: 4),
        Text(
          game.result,
          style: TextStyle(color: resultColor, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildOpponentCell(TeamGameHistoryItem game) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (game.opponentLogoUri != null && game.opponentLogoUri!.isNotEmpty)
          SvgPicture.asset(
            game.opponentLogoUri!,
            width: 20,
            height: 20,
            placeholderBuilder: (context) =>
                const Icon(Icons.shield, size: 20, color: Colors.grey),
          )
        else
          const Icon(Icons.shield, size: 20, color: Colors.grey),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            game.opponentName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
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

    return Scaffold(
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
                            child: widget.team.logoURI != null &&
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
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Matchup history for the ${widget.team.name} across recent years. Tap column headings to sort.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
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
                    child: DataTable2(
                      border: TableBorder.all(
                        width: 1.0,
                        color: Colors.grey.shade300,
                      ),
                      columnSpacing: 0,
                      horizontalMargin: 0,
                      minWidth: 520,
                      fixedTopRows: 1,
                      fixedLeftColumns: orientation == Orientation.portrait
                          ? 1
                          : 0,
                      showCheckboxColumn: false,
                      isHorizontalScrollBarVisible: true,
                      isVerticalScrollBarVisible: true,
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      dataRowHeight: 48.0,
                      headingRowHeight: 40.0,
                      columns: [
                        DataColumn2(
                          fixedWidth: 90,
                          label: const Text(
                            'Date',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onSort: _onSort,
                        ),
                        DataColumn2(
                          fixedWidth: 80,
                          label: const Text(
                            'Result',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onSort: _onSort,
                        ),
                        DataColumn2(
                          size: ColumnSize.L,
                          label: const Text(
                            'Opponent',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onSort: _onSort,
                        ),
                        DataColumn2(
                          fixedWidth: 80,
                          label: const Text(
                            'Score',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onSort: _onSort,
                        ),
                        DataColumn2(
                          fixedWidth: 100,
                          label: const Text(
                            'Round',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onSort: _onSort,
                        ),
                      ],
                      rows: _gameHistory.map((game) {
                        return DataRow2(
                          cells: [
                            DataCell(Text(_formatDate(game.gameDate))),
                            DataCell(_buildResultCell(game)),
                            DataCell(_buildOpponentCell(game)),
                            DataCell(
                              Text(
                                '${game.teamScore} - ${game.opponentScore}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildHomeAwayBadge(game),
                                  const SizedBox(width: 6),
                                  Text('R${game.roundNumber}'),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
          ],
        ),
      ),
    );
  }
}
