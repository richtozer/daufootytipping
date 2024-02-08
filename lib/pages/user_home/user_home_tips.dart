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

/*   Widget build(BuildContext context) {
    return Consumer<DAUCompsViewModel>(
        builder: (context, daucompsViewModel, child) {
      return ChangeNotifierProvider(
        create: (context) => GamesViewModel(daucompsViewModel.currentDAUComp),
        child: _TipsPageBody(currentTipper, daucompsViewModel),
      );
    });
  } */
}

class _TipsPageBody extends StatefulWidget {
  final Tipper currentTipper;
  final DAUCompsViewModel daucompsViewModel;

  const _TipsPageBody(this.currentTipper, this.daucompsViewModel);

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
      future: widget.daucompsViewModel
          .getGamesForCombinedRoundNumberAndLeague(combinedRoundNumber, league),
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
                  currentDAUCompDBkey: widget.daucompsViewModel.currentDAUComp);
            },
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: widget.daucompsViewModel.getCombinedRoundNumbers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          //return const Center(child: Text('Wait..'));
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
          // see here for the need for singlescrollchildview wrapper
          // https://stackoverflow.com/questions/51536756/flutter-listview-jumps-to-top
          return SingleChildScrollView(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
            ),
          );
        }
      },
    );
  }
}
