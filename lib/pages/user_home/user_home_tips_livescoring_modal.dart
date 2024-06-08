import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class LiveScoringModal extends StatefulWidget {
  final TipGame tipGame;

  const LiveScoringModal(this.tipGame, {super.key});

  @override
  State<LiveScoringModal> createState() => _LiveScoringModalState();
}

class _LiveScoringModalState extends State<LiveScoringModal> {
  late String homeScore;
  late String awayScore;
  late String originalHomeScore;
  late String originalAwayScore;

  bool enableKeypad = false;
  bool? isUpdatingHomeScore;

  int positionHomeScore = 0;
  int positionAwayScore = 0;

  @override
  void initState() {
    super.initState();
    homeScore =
        (widget.tipGame.game.scoring?.currentScore(ScoringTeam.home) ?? 0)
            .toString();
    awayScore =
        (widget.tipGame.game.scoring?.currentScore(ScoringTeam.away) ?? 0)
            .toString();

    // keep track of the original scores. if scores change enable the submit button
    originalHomeScore = homeScore;
    originalAwayScore = awayScore;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
          defaultColumnWidth: const FlexColumnWidth(1.0),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: const [
            TableRow(children: [
              Text(
                'Edit Live Scoring',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ]),
          ],
        ),
        // 2
        Container(
          //width: 300,
          padding: const EdgeInsets.all(10.0),
          child: Table(
            defaultColumnWidth: const FlexColumnWidth(1.0),
            columnWidths: const {
              0: FlexColumnWidth(2.0),
              1: FlexColumnWidth(1.0),
              2: FlexColumnWidth(2.0),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                _buildElevatedButton(
                  widget.tipGame.game.homeTeam.name,
                  homeScore,
                  () {
                    setState(() {
                      enableKeypad = true;
                      isUpdatingHomeScore = true;
                      //positionHomeScore = 0;
                    });
                  },
                  isUpdatingHomeScore ?? false
                      ? ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightGreen)
                      : null,
                ),
                const Center(
                    child: Text('◀Select▶︎',
                        style: TextStyle(fontWeight: FontWeight.w900))),
                _buildElevatedButton(
                    widget.tipGame.game.awayTeam.name, awayScore, () {
                  setState(() {
                    enableKeypad = true;
                    isUpdatingHomeScore = false;
                    //positionAwayScore = 0;
                  });
                },
                    isUpdatingHomeScore ?? true
                        ? null
                        : ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightGreen)),
              ]),
            ],
          ),
        ),
        const Text('Enter latest score:',
            style: TextStyle(fontWeight: FontWeight.w900)),
        // 3 - keypad
        Container(
          padding: const EdgeInsets.fromLTRB(30.0, 0.0, 30.0, 30.0),
          child: Table(
            defaultColumnWidth: const FlexColumnWidth(1.0),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  _buildButton("1"),
                  _buildButton("2"),
                  _buildButton("3"),
                ],
              ),
              TableRow(
                children: [
                  _buildButton("4"),
                  _buildButton("5"),
                  _buildButton("6"),
                ],
              ),
              TableRow(
                children: [
                  _buildButton("7"),
                  _buildButton("8"),
                  _buildButton("9"),
                ],
              ),
              TableRow(
                children: [
                  Container(),
                  _buildButton("0"),
                  GestureDetector(
                    onTap: () {
                      // if isUpdatingHomeScore is true and positionHomeScore is 0, then we are at the start of the text
                      // dont allow backspace
                      isUpdatingHomeScore == true && positionHomeScore == 0 ||
                              isUpdatingHomeScore == false &&
                                  positionAwayScore == 0
                          ? null
                          : _backspace();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.backspace,
                        size: 40,
                        color: isUpdatingHomeScore != null
                            ? Colors.lightGreen
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        // close the modal without saving
                        Navigator.pop(context);
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  Container(),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed:
                          // if the scores have not changed then disable Submit button
                          (homeScore == originalHomeScore &&
                                  awayScore == originalAwayScore)
                              ? null
                              : () {
                                  // if home score changed then update the home score
                                  if (homeScore != originalHomeScore) {
                                    liveScoreUpdated(
                                        homeScore,
                                        ScoringTeam.home,
                                        di<DAUCompsViewModel>()
                                            .selectedDAUComp!);
                                  }
                                  // if away score changed then update the away score
                                  if (awayScore != originalAwayScore) {
                                    liveScoreUpdated(
                                        awayScore,
                                        ScoringTeam.away,
                                        di<DAUCompsViewModel>()
                                            .selectedDAUComp!);
                                  }

                                  // close the modal
                                  Navigator.pop(context);
                                },
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildElevatedButton(
      String team, String score, VoidCallback onPressed, ButtonStyle? style) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: style,
        child: Column(
          children: [
            Text(
              team,
              textAlign: TextAlign.center,
            ),
            SizedBox(
              width: 100,
              child: Text(
                score,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String text, {VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.lightGreen,
          shape: const RoundedRectangleBorder(
            //borderRadius: BorderRadius.circular(20),
            borderRadius: BorderRadius.zero, //Rectangular border
          ),
        ),
        onPressed: enableKeypad
            ? onPressed ??
                () {
                  isUpdatingHomeScore == null ? null : _input(text);
                }
            : null,
        child: Text(text,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      ),
    );
  }

  void _input(String text) {
    if (isUpdatingHomeScore == null) return;
    if (isUpdatingHomeScore!) {
      homeScore = _updateScore(homeScore, text, positionHomeScore);
      positionHomeScore = homeScore == '0' ? 0 : positionHomeScore + 1;
    } else {
      awayScore = _updateScore(awayScore, text, positionAwayScore);
      positionAwayScore = awayScore == '0' ? 0 : positionAwayScore + 1;
    }
    setState(() {});
  }

  String _updateScore(String score, String text, int position) {
    if (position == 0) {
      return text;
    } else if (score == '0' && text == '0') {
      return score;
    } else if (score == '0') {
      return text;
    } else {
      var prefix = score.substring(0, position);
      return prefix + text;
    }
  }

  void _backspace() {
    if (isUpdatingHomeScore == null) return;
    if (isUpdatingHomeScore!) {
      homeScore = _deleteDigit(homeScore, positionHomeScore);
      positionHomeScore = homeScore == '0' ? 0 : positionHomeScore - 1;
    } else {
      awayScore = _deleteDigit(awayScore, positionAwayScore);
      positionAwayScore = awayScore == '0' ? 0 : positionAwayScore - 1;
    }
    setState(() {});
  }

  String _deleteDigit(String score, int position) {
    if (position == 1) {
      return '0';
    } else {
      var prefix = score.substring(0, position - 1);
      var suffix = score.substring(position, score.length);
      return prefix + suffix;
    }
  }

  void liveScoreUpdated(
      dynamic score, ScoringTeam scoreTeam, DAUComp selectedDAUComp) {
    // prepare the crowd sourced score
    CrowdSourcedScore croudSourcedScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        scoreTeam,
        widget.tipGame.tipper.dbkey!,
        int.tryParse(score)!,
        false);

    di<ScoresViewModel>().addLiveScore(widget.tipGame.game, croudSourcedScore);
  }
}
