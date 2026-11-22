// cspell:words Freo Penrith Rabbitohs
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';

/// Synthetic equivalents of the supplied screenshots. No personal/live data.
List<TipsCardDisplay> tipsSamples({
  required Map<String, GameResult> selections,
  required Set<String> saving,
  bool loading = false,
  bool longNames = false,
  bool kickoff = false,
}) {
  TipsTeamDisplay nrl(
    String name,
    String dbTeamName, {
    int? score,
    String? rank,
    bool winner = false,
  }) => TipsTeamDisplay(
    name,
    'nrl-$dbTeamName',
    score: score,
    rank: rank,
    winner: winner,
  );
  TipsTeamDisplay afl(
    String name,
    String dbTeamName, {
    int? score,
    bool winner = false,
  }) => TipsTeamDisplay(name, 'afl-$dbTeamName', score: score, winner: winner);
  TipsCardDisplay card(
    String id,
    League league,
    TipsTeamDisplay home,
    TipsTeamDisplay away, {
    TipsStatus status = TipsStatus.finalScore,
    GameResult selected = GameResult.e,
    GameResult? result = GameResult.d,
    bool load = false,
  }) => TipsCardDisplay(
    id: id,
    league: league,
    home: home,
    away: away,
    selected: selections[id] ?? selected,
    result: result,
    status: status,
    info: longNames
        ? 'Kickoff: Friday 25 September 7:50 pm 🏉 A very long stadium name in a regional sporting complex 🏉 Fixture: round 27, match 201'
        : 'Kickoff: Fri 25 Sep 19:50 🏉 Stadium Australia 🏉 Fixture: round 27, match 201',
    points: '1 / 2',
    average: '1.2 / 2',
    percentages: const [1.8, 42.1, 0, 54.4, 1.8],
    loading: loading || load,
    saving: saving.contains(id),
    canTip: status == TipsStatus.upcoming || status == TipsStatus.today,
  );
  return [
    card(
      '24-1',
      League.afl,
      afl('Tigers', 'Richmond', score: 22),
      afl('Dragons', 'Sydney Swans', score: 24, winner: true),
    ),
    card(
      '24-2',
      League.afl,
      afl('Freo', 'Fremantle', score: 112, winner: true),
      afl('Crows', 'Adelaide Crows', score: 88),
      load: true,
      result: GameResult.b,
    ),
    card(
      '24-3',
      League.afl,
      afl('Tigers', 'Richmond', score: 45),
      afl('Saints', 'St Kilda', score: 94, winner: true),
      result: GameResult.e,
    ),
    card(
      '24-4',
      League.afl,
      afl('Norths', 'North Melbourne', score: 110),
      afl('Cats', 'Geelong Cats', score: 125, winner: true),
    ),
    card(
      '25-1',
      League.nrl,
      nrl('Storm', 'Storm', score: 14),
      nrl('Panthers', 'Panthers', score: 22, winner: true),
    ),
    card(
      '25-2',
      League.nrl,
      nrl('Raiders', 'Raiders', score: 30),
      nrl('Broncos', 'Broncos', score: 34, winner: true),
    ),
    card(
      '25-3',
      League.nrl,
      nrl('Knights', 'Knights', score: 0),
      nrl('Manly', 'Sea Eagles', score: 0),
      status: TipsStatus.live,
      result: GameResult.z,
      selected: GameResult.d,
    ),
    card(
      '25-4',
      League.nrl,
      nrl('Rabbitohs', 'Rabbitohs', score: 0),
      nrl('Warriors', 'Warriors', score: 0),
      status: TipsStatus.live,
      result: GameResult.z,
    ),
    card(
      '27-1',
      League.nrl,
      nrl('Warriors', 'Warriors', score: 31),
      nrl('Manly', 'Sea Eagles', score: 30),
      status: TipsStatus.interim,
      result: GameResult.b,
      selected: GameResult.a,
    ),
    card(
      '27-2',
      League.nrl,
      nrl(
        longNames ? 'North Queensland Cowboys' : 'Cowboys',
        'Cowboys',
        score: 30,
      ),
      nrl('Raiders', 'Raiders', score: 50),
      status: TipsStatus.interim,
      result: GameResult.e,
    ),
    card(
      '27-3',
      League.nrl,
      nrl('Dragons', 'Dragons', rank: '17th'),
      nrl('Eels', 'Eels', rank: '13th'),
      status: kickoff ? TipsStatus.live : TipsStatus.today,
      result: kickoff ? GameResult.z : null,
    ),
    card(
      '27-4',
      League.nrl,
      nrl('Panthers', 'Panthers', rank: '2nd'),
      nrl('Tigers', 'Wests Tigers', rank: '15th'),
      status: TipsStatus.upcoming,
      result: null,
    ),
  ];
}
