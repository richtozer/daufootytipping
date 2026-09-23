// cspell:words Freo kagaroos colours Penrith Rabbitohs
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
  TipsTeamDisplay nrl(String name, String asset, {int? score, String? rank, bool winner = false}) =>
      TipsTeamDisplay(name, 'assets/teams/nrl/$asset.svg', score: score, rank: rank, winner: winner);
  TipsTeamDisplay afl(String name, String asset, {int? score, bool winner = false}) =>
      TipsTeamDisplay(name, 'assets/teams/afl/$asset.svg', score: score, winner: winner);
  TipsCardDisplay card(String id, League league, TipsTeamDisplay home, TipsTeamDisplay away, {
    TipsStatus status = TipsStatus.finalScore,
    GameResult selected = GameResult.e, GameResult? result = GameResult.d,
    bool load = false,
  }) => TipsCardDisplay(
    id: id, league: league, home: home, away: away,
    selected: selections[id] ?? selected, result: result, status: status,
    info: longNames
        ? 'Kickoff: Friday 25 September 7:50 pm 🏉 A very long stadium name in a regional sporting complex 🏉 Fixture: round 27, match 201'
        : 'Kickoff: Fri 25 Sep 19:50 🏉 Stadium Australia 🏉 Fixture: round 27, match 201',
    points: '1 / 2', average: '1.2 / 2',
    percentages: const [1.8, 42.1, 0, 54.4, 1.8],
    loading: loading || load, saving: saving.contains(id),
    canTip: status == TipsStatus.upcoming || status == TipsStatus.today,
  );
  return [
    card('24-1', League.afl, afl('Tigers', 'tigers', score: 22),
      afl('Dragons', 'swans', score: 24, winner: true)),
    card('24-2', League.afl, afl('Freo', 'dockers', score: 112, winner: true),
      afl('Crows', 'crows', score: 88), load: true, result: GameResult.b),
    card('24-3', League.afl, afl('Tigers', 'tigers', score: 45),
      afl('Saints', 'saints', score: 94, winner: true), result: GameResult.e),
    card('24-4', League.afl, afl('Norths', 'kagaroos', score: 110),
      afl('Cats', 'cats', score: 125, winner: true)),
    card('25-1', League.nrl, nrl('Storm', 'Melbourne_colours', score: 14),
      nrl('Panthers', 'Penrith_Panthers_square_flag_icon_with_2020_colours', score: 22, winner: true)),
    card('25-2', League.nrl, nrl('Raiders', 'Canberra_colours', score: 30),
      nrl('Broncos', 'Brisbane_colours', score: 34, winner: true)),
    card('25-3', League.nrl, nrl('Knights', 'Newcastle_colours', score: 0),
      nrl('Manly', 'Manly_Sea_Eagles_colours', score: 0), status: TipsStatus.live,
      result: GameResult.z, selected: GameResult.d),
    card('25-4', League.nrl, nrl('Rabbitohs', 'South_Sydney_colours', score: 0),
      nrl('Warriors', 'Auckland_colours', score: 0), status: TipsStatus.live, result: GameResult.z),
    card('27-1', League.nrl, nrl('Warriors', 'Auckland_colours', score: 31),
      nrl('Manly', 'Manly_Sea_Eagles_colours', score: 30), status: TipsStatus.interim,
      result: GameResult.b, selected: GameResult.a),
    card('27-2', League.nrl, nrl(longNames ? 'North Queensland Cowboys' : 'Cowboys',
      'North_Queensland_colours', score: 30), nrl('Raiders', 'Canberra_colours', score: 50),
      status: TipsStatus.interim, result: GameResult.e),
    card('27-3', League.nrl, nrl('Dragons', 'St._George_colours', rank: '17th'),
      nrl('Eels', 'Parramatta_colours', rank: '13th'),
      status: kickoff ? TipsStatus.live : TipsStatus.today, result: kickoff ? GameResult.z : null),
    card('27-4', League.nrl,
      nrl('Panthers', 'Penrith_Panthers_square_flag_icon_with_2020_colours', rank: '2nd'),
      nrl('Tigers', 'Wests_Tigers_colours', rank: '15th'), status: TipsStatus.upcoming, result: null),
  ];
}
