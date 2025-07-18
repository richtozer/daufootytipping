import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Added import
import 'package:watch_it/watch_it.dart';

import 'user_home_header.dart'; // Import HeaderWidget

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

  @override
  void initState() {
    super.initState();
    _fetchGameHistory(); // Call the actual fetch method
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
      final history = await gamesViewModel!.getTeamGameHistory(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: Colors.lightGreen[200],
        foregroundColor: Colors.white70,
        child: const Icon(Icons.arrow_back),
      ),
      body: Column(
        children: [
          HeaderWidget(
            text: '${widget.team.name} - Game History',
            leadingIconAvatar: SizedBox(
              width: 40,
              height: 40,
              child:
                  widget.team.logoURI != null && widget.team.logoURI!.isNotEmpty
                  ? SvgPicture.asset(
                      widget.team.logoURI!,
                      placeholderBuilder: (context) =>
                          const Icon(Icons.shield), // Fallback during load
                    )
                  : const Icon(Icons.shield), // Fallback if no URI
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _gameHistory.isEmpty &&
                      !_isLoading // Check after loading is done
                ? const Center(
                    child: Text('No game history available for this team.'),
                  )
                : ListView.builder(
                    itemCount: _gameHistory.length,
                    itemBuilder: (context, index) {
                      final item = _gameHistory[index];
                      Color resultColor = Colors.black;
                      if (item.result == "Won") {
                        resultColor = Colors.green;
                      }
                      if (item.result == "Lost") {
                        resultColor = Colors.red;
                      }
                      if (item.result == "Draw") {
                        resultColor = Colors.grey.shade700;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: ListTile(
                          leading: SizedBox(
                            width: 40,
                            height: 40,
                            child:
                                item.opponentLogoUri != null &&
                                    item.opponentLogoUri!.isNotEmpty
                                ? SvgPicture.asset(
                                    item.opponentLogoUri!,
                                    placeholderBuilder: (context) => const Icon(
                                      Icons.shield,
                                    ), // Fallback during load
                                    // Consider adding errorBuilder for production apps
                                    // errorBuilder: (context, error, stackTrace) => Icon(Icons.error_outline, color: Colors.red),
                                  )
                                : const Icon(
                                    Icons.shield,
                                  ), // Fallback if no URI
                          ),
                          title: Text(
                            'Vs ${item.opponentName}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Round ${item.roundNumber} | ${item.gameDate.toLocal().toString().split(' ')[0]}',
                              ),
                              Text(
                                'Score: ${item.teamScore} - ${item.opponentScore} (${item.result})',
                                style: TextStyle(
                                  color: resultColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('Ladder Points: ${item.ladderPoints}'),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
