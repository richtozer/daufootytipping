import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class TipsPage extends StatelessWidget {
  final Tipper currentTipper;

  const TipsPage(this.currentTipper, {super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DAUCompsViewModel>(
        builder: (context, daucompsViewModel, child) {
      return _TipsPageBody(currentTipper, daucompsViewModel);
    });
  }
}

class _TipsPageBody extends StatefulWidget {
  final Tipper currentTipper;
  final DAUCompsViewModel daucompsViewModel;

  const _TipsPageBody(this.currentTipper, this.daucompsViewModel);

  @override
  State<_TipsPageBody> createState() => _TipsPageBodyState();
}

class _TipsPageBodyState extends State<_TipsPageBody> {
  ScrollController? controller;

  @override
  void initState() {
    super.initState();
    controller = ScrollController();

    /*WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        double itemHeight = 100; // Replace with your actual item height
        int index = 5; // Replace with your actual index

        controller.animateTo(
          index * itemHeight,
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
      }
    });
    */
  }

  Widget compHeaderListTile(DAUComp dauComp) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.fill,
          ),
        ),
        ListTile(
          trailing: SvgPicture.asset(League.afl.logo, width: 40, height: 40),
          leading: SvgPicture.asset(League.nrl.logo, width: 50, height: 50),
          title: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              children: [
                Text(
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    dauComp.name),
                Text(
                    'NRL: ${dauComp.consolidatedCompScores?.nrlCompScore} / ${dauComp.consolidatedCompScores?.nrlCompMaxScore}'),
                Text(
                    'AFL: ${dauComp.consolidatedCompScores?.aflCompScore} / ${dauComp.consolidatedCompScores?.aflCompMaxScore}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget roundLeagueHeaderListTile(
      League leagueHeader, double width, double height, DAURound dauRound) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.fill,
          ),
        ),
        ListTile(
          onTap: () async {
            // When the round header is clicked,
            // update the scoring for this round and tipper
            // TODO consider removing this functionality
            widget.daucompsViewModel.updateScoring(
                await widget.daucompsViewModel
                    .getCurrentDAUComp()
                    .then((DAUComp? dauComp) {
                  return dauComp!;
                }),
                widget.currentTipper);
          },
          trailing: SvgPicture.asset(
            leagueHeader.logo,
            width: width,
            height: height,
          ),
          title: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              children: [
                Text(
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    'R o u n d: ${dauRound.dAUroundNumber} ${leagueHeader.name.toUpperCase()}'),
                Text(
                    'Score: ${leagueHeader == League.afl ? dauRound.roundScores!.aflScore : dauRound.roundScores!.nrlScore} / ${leagueHeader == League.afl ? dauRound.roundScores!.aflMaxScore : dauRound.roundScores!.nrlMaxScore}'),
                Text(
                    'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginUPS : dauRound.roundScores!.nrlMarginUPS}'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Rank: ${dauRound.roundScores!.rank}  '),
                    dauRound.roundScores!.rankChange > 0
                        ? const Icon(color: Colors.green, Icons.arrow_upward)
                        : dauRound.roundScores!.rankChange < 0
                            ? const Icon(
                                color: Colors.red, Icons.arrow_downward)
                            : const Icon(
                                color: Colors.redAccent, Icons.sync_alt),
                    Text('${dauRound.roundScores!.rankChange}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget roundLeagueGameBuilder(DAURound dauRound, League league) {
    return FutureBuilder<List<Game>>(
      future: widget.daucompsViewModel.getGamesForCombinedRoundNumberAndLeague(
          dauRound.dAUroundNumber, league),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Text('Wait..'));
          //return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var games = snapshot.data;
          if (games!.isEmpty) {
            return Center(
              heightFactor: 2,
              child: Text(
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  'No ${league.name.toUpperCase()} games this round'),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games.length,
            itemBuilder: (context, index) {
              var game = games[index];
              return GameListItem(
                  roundGames: games,
                  game: game,
                  currentTipper: widget.currentTipper,
                  currentDAUCompDBkey:
                      widget.daucompsViewModel.selectedDAUCompDbKey);
            },
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DAUComp>(
      future: widget.daucompsViewModel.getScores(widget.currentTipper),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var dauComp = snapshot.data;
          if (dauComp!.daurounds!.isEmpty) {
            return const Center(
              child: Text('No Rounds Found'),
            );
          }
          return CustomScrollView(
            controller: controller,
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: compHeaderListTile(dauComp),
                ),
              ),
              ...dauComp.daurounds!.asMap().entries.map((entry) {
                int index = entry.key;
                DAURound dauRound = entry.value;
                return SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      roundLeagueHeaderListTile(League.nrl, 50, 50, dauRound),
                      roundLeagueGameBuilder(dauRound, League.nrl),
                      roundLeagueHeaderListTile(League.afl, 40, 40, dauRound),
                      roundLeagueGameBuilder(dauRound, League.afl),
                    ],
                  ),
                );
              }),
            ],
          );
        }
      },
    );
  }

  @override
  void dispose() {
    controller!.dispose();
    super.dispose();
  }
}
