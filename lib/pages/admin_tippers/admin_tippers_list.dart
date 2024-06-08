import 'package:cached_network_image/cached_network_image.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
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
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // _scrollController.addListener(() {
    //   // Save the scroll position in your state management solution
    //   di<TippersViewModel>().tipperListScrollPosition =
    //       _scrollController.offset;
    // });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TippersViewModel tipperViewModel = watchIt<TippersViewModel>();
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
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                OutlinedButton(
                  onPressed: () async {
                    if (tipperViewModel.isLegacySyncing) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Colors.red,
                          content:
                              Text('Legacy Tipper sync already in progress')));
                      return;
                    }
                    try {
                      String res = await tipperViewModel.syncTippers();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: Colors.green,
                        content: Text(res),
                        duration: const Duration(seconds: 10),
                      ));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red,
                          content: Text('An error occurred: $e'),
                          duration: const Duration(seconds: 10),
                        ),
                      );
                    }
                  },
                  child: Text(!tipperViewModel.isLegacySyncing
                      ? 'Sync Legacy Tippers'
                      : 'Sync processing...'),
                ),
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

                                  bool tipperActiveInCurrentComp = tipper
                                      .activeInComp(di<DAUCompsViewModel>()
                                          .defaultDAUCompDbKey);

                                  return Card(
                                    child: ListTile(
                                      dense: true,
                                      isThreeLine: true,
                                      leading: tipper.photoURL != null
                                          ? avatarPic(tipper.photoURL!)
                                          : null,
                                      trailing: tipperActiveInCurrentComp
                                          ? const Icon(Icons.person)
                                          : const Icon(Icons.person_off),
                                      title: Text(tipper.name),
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

  CircleAvatar avatarPic(String url) {
    return CircleAvatar(
      radius: 15,
      backgroundImage: url != '' ? CachedNetworkImageProvider(url) : null,
    );
  }
}
