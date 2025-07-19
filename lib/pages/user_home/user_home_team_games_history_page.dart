import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

import 'user_home_header.dart';

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
  final ScrollController _scrollController = ScrollController();
  String _currentYear = '';
  final Map<String, double> _yearPositions = {};

  @override
  void initState() {
    super.initState();
    _fetchGameHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_yearPositions.isEmpty) return;

    final scrollOffset = _scrollController.offset;
    String newYear = _currentYear;

    // Add offset to switch earlier - when we're about 1 card height before the next section
    const double switchOffset = 88.0; // ~1 card height (80px) + spacing (8px)

    // Find which year section we're currently in
    for (final entry in _yearPositions.entries.toList().reversed) {
      if (scrollOffset >= (entry.value - switchOffset)) {
        newYear = entry.key;
        break;
      }
    }

    if (newYear != _currentYear && mounted) {
      setState(() {
        _currentYear = newYear;
      });
    }
  }

  Future<void> _fetchGameHistory() async {
    // Ensure widget is still mounted before calling setState
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null; // Clear previous errors
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
          if (history.isNotEmpty) {
            _currentYear = history.first.gameDate.year.toString();
            _calculateYearPositions();
          }
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

  Map<String, List<TeamGameHistoryItem>> _groupGamesByYear() {
    final Map<String, List<TeamGameHistoryItem>> groupedGames = {};

    for (final item in _gameHistory) {
      final year = item.gameDate.year.toString();
      if (!groupedGames.containsKey(year)) {
        groupedGames[year] = [];
      }
      groupedGames[year]!.add(item);
    }

    return groupedGames;
  }

  void _calculateYearPositions() {
    final groupedGames = _groupGamesByYear();
    final sortedYears = groupedGames.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    double currentPosition = 0.0;
    const double gameCardHeight = 80.0; // Approximate game card height
    const double spacing = 8.0; // Spacing between cards
    const double sectionSpacing = 40.0; // Spacing between year sections
    const double headerHeight =
        60.0; // Year header height (only for non-first years)
    const double firstYearSpacing = 12.0; // Top spacing for first year

    for (int index = 0; index < sortedYears.length; index++) {
      final year = sortedYears[index];
      final isFirstYear = index == 0;

      _yearPositions[year] = currentPosition;
      final gameCount = groupedGames[year]!.length;

      if (isFirstYear) {
        // First year: just top spacing + games
        currentPosition +=
            firstYearSpacing +
            (gameCount * (gameCardHeight + spacing)) +
            sectionSpacing;
      } else {
        // Subsequent years: header + games
        currentPosition +=
            headerHeight +
            (gameCount * (gameCardHeight + spacing)) +
            sectionSpacing;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final groupedGames = _groupGamesByYear();
    final sortedYears = groupedGames.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: Colors.lightGreen[200],
        foregroundColor: Colors.white70,
        child: const Icon(Icons.arrow_back),
      ),
      body: Column(
        children: [
          if (orientation == Orientation.portrait)
            HeaderWidget(
              text: '${widget.team.name} - Game History',
              leadingIconAvatar: Hero(
                tag: "team_icon_${widget.team.dbkey}",
                child: SizedBox(
                  width: 40,
                  height: 40,
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
            ),
          if (orientation == Orientation.portrait)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'This is the matchup history for the ${widget.team.name} across recent years.  ',
                textAlign: TextAlign.left,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _gameHistory.isEmpty && !_isLoading
                ? const Center(
                    child: Text('No game history available for this team.'),
                  )
                : Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(
                          top: 60.0,
                          left: 16.0,
                          right: 16.0,
                          bottom: 16.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildYearSections(
                            groupedGames,
                            sortedYears,
                          ),
                        ),
                      ),
                      // Sticky header
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 50.0,
                          margin: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4.0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _currentYear,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildYearSections(
    Map<String, List<TeamGameHistoryItem>> groupedGames,
    List<String> sortedYears,
  ) {
    List<Widget> sections = [];

    for (int yearIndex = 0; yearIndex < sortedYears.length; yearIndex++) {
      final year = sortedYears[yearIndex];
      final games = groupedGames[year]!;
      final isFirstYear = yearIndex == 0;

      // Year header - only show for years after the first one (since sticky header shows current year)
      if (!isFirstYear) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
            child: Text(
              year,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        );
      } else {
        // Just add some top spacing for the first year
        sections.add(const SizedBox(height: 12.0));
      }

      // Games for this year
      for (TeamGameHistoryItem game in games) {
        sections.add(_buildGameCard(game));
        sections.add(const SizedBox(height: 8.0));
      }

      // Spacing between years
      sections.add(const SizedBox(height: 16.0));
    }

    return sections;
  }

  Widget _buildGameCard(TeamGameHistoryItem game) {
    Color? resultColor;
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

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Result icon and label
            Column(
              children: [
                Icon(resultIcon, color: resultColor, size: 24),
                const SizedBox(height: 2),
                Text(
                  game.result,
                  style: TextStyle(
                    color: resultColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Round and Home/Away info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Round ${game.roundNumber}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: game.isHomeGame
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: game.isHomeGame
                          ? Colors.blue.withValues(alpha: 0.3)
                          : Colors.purple.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    game.isHomeGame ? 'Home' : 'Away',
                    style: TextStyle(
                      color: game.isHomeGame
                          ? Colors.blue[700]
                          : Colors.purple[700],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Opponent name
            Expanded(
              flex: 2,
              child: Text(
                'v. ${game.opponentName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),

            // Opponent logo
            if (game.opponentLogoUri != null &&
                game.opponentLogoUri!.isNotEmpty)
              SizedBox(
                width: 20,
                height: 20,
                child: SvgPicture.asset(
                  game.opponentLogoUri!,
                  placeholderBuilder: (context) =>
                      Icon(Icons.shield, size: 20, color: Colors.grey[400]),
                ),
              )
            else
              Icon(Icons.shield, size: 20, color: Colors.grey[400]),
            const SizedBox(width: 12),

            // Score and points
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${game.teamScore} - ${game.opponentScore}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${game.ladderPoints} pts',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Date
            Text(
              _formatDate(game.gameDate),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
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

    String day = date.day.toString().padLeft(2, '0');
    String month = monthNames[date.month - 1];

    return '$day-$month';
  }
}
