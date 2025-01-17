import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class TippersAdminPage extends StatefulWidget with WatchItStatefulWidgetMixin {
  const TippersAdminPage({super.key});

  @override
  State<TippersAdminPage> createState() => _TippersAdminPageState();
}

class _TippersAdminPageState extends State<TippersAdminPage> {
  late final ScrollController _scrollController;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  late TippersViewModel tipperViewModel;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  Future<void> _addTipper(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TipperAdminEditPage(tipperViewModel, null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    tipperViewModel = watchIt<TippersViewModel>();
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Admin Tippers'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await _addTipper(context);
          },
          child: const Icon(Icons.add),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Expanded(
                  child: FutureBuilder<List<Tipper>>(
                    future: tipperViewModel.getAllTippers(),
                    builder: (BuildContext context,
                        AsyncSnapshot<List<Tipper>> snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator(
                            color: League.afl
                                .colour); // Show a loading spinner while waiting
                      } else {
                        return Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                //controller: _scrollController,
                                itemCount: snapshot.data!.length,
                                itemBuilder: (context, index) {
                                  var tipper = snapshot.data![index];

                                  bool tipperActiveInCurrentComp =
                                      tipper.paidForComp(di<DAUCompsViewModel>()
                                          .activeDAUComp);

                                  return Card(
                                    child: ListTile(
                                      dense: true,
                                      isThreeLine: true,
                                      leading: tipper.photoURL != null
                                          ? avatarPic(tipper)
                                          : null,
                                      trailing: tipperActiveInCurrentComp
                                          ? const Icon(Icons.person)
                                          : const Icon(Icons.person_off),
                                      title: Text(tipper.name ??
                                          ''), // if a new tipper, name may be null until they update it
                                      subtitle: Text(
                                          '${tipper.tipperRole.name}\n${tipper.email}'),
                                      onTap: () async {
                                        // Trigger edit functionality
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                TipperAdminEditPage(
                                                    tipperViewModel, tipper),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            )));
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
          imageUrl: tipper.photoURL, text: tipper.name, radius: 30),
    );
  }
}
