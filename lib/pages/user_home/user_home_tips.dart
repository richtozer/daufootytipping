import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class TipsPage extends StatelessWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;

  const TipsPage(this.currentTipper, this.currentDAUCompDBkey, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => GamesViewModel(currentDAUCompDBkey),
      child: Consumer<GamesViewModel>(
        builder: (context, gamesViewModel, child) {
          return _TipsPageBody(
              currentTipper, gamesViewModel, currentDAUCompDBkey);
        },
      ),
    );
  }
}

class _TipsPageBody extends StatefulWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;
  final GamesViewModel gamesViewModel;

  const _TipsPageBody(
      this.currentTipper, this.gamesViewModel, this.currentDAUCompDBkey);

  @override
  State<_TipsPageBody> createState() => _TipsPageBodyState();
}

class _TipsPageBodyState extends State<_TipsPageBody> {
  final ScrollController controller = ScrollController();

  @override
  void initState() {
    super.initState();

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

  Widget roundLeagueHeaderListTile(
      String logo, double width, double height, int combinedRoundNumber) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.none,
          ),
        ),
        ListTile(
          trailing: SvgPicture.asset(
            logo,
            width: width,
            height: height,
          ),
          title: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text('R o u n d: $combinedRoundNumber'),
          ),
        ),
      ],
    );
  }

  Widget roundLeagueGameBuilder(int combinedRoundNumber, League league) {
    return FutureBuilder<List<Game>>(
      future: widget.gamesViewModel
          .getGamesForCombinedRoundNumberAndLeague(combinedRoundNumber, league),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var games = snapshot.data;
          if (games!.isEmpty) {
            return Center(
              heightFactor: 2,
              child: Text('No ${league.name.toUpperCase()} games this round'),
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
                  currentDAUCompDBkey: widget.currentDAUCompDBkey);
            },
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: widget.gamesViewModel.getCombinedRoundNumbers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var combinedRoundNumbers = snapshot.data;
          if (combinedRoundNumbers!.isEmpty) {
            return const Center(
              child: Text('No Rounds Found'),
            );
          }
          return ListView.builder(
            controller: controller,
            itemCount: combinedRoundNumbers.length,
            itemBuilder: (context, index) {
              var combinedRoundNumber = combinedRoundNumbers[index];
              return Column(
                children: [
                  roundLeagueHeaderListTile(
                      League.nrl.logo, 50, 50, combinedRoundNumber),
                  roundLeagueGameBuilder(combinedRoundNumber, League.nrl),
                  roundLeagueHeaderListTile(
                      League.afl.logo, 40, 40, combinedRoundNumber),
                  roundLeagueGameBuilder(combinedRoundNumber, League.afl),
                ],
              );
            },
          );
        }
      },
    );
  }
}
