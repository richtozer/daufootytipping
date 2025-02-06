import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:intl/intl.dart';

class TippersAdminPage extends StatefulWidget with WatchItStatefulWidgetMixin {
  const TippersAdminPage({super.key});

  @override
  State<TippersAdminPage> createState() => _TippersAdminPageState();
}

class _TippersAdminPageState extends State<TippersAdminPage> {
  late final ScrollController _scrollController;
  bool _showPaidCurrent = false;
  int paidCurrentCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  late final TippersViewModel tipperViewModel;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    tipperViewModel = di<TippersViewModel>();
    _calculatePaidCurrentCount();
  }

  Future<void> _calculatePaidCurrentCount() async {
    List<Tipper> tippers = await tipperViewModel.getAllTippers();
    setState(() {
      paidCurrentCount = tippers
          .where((tipper) =>
              tipper.paidForComp(di<DAUCompsViewModel>().activeDAUComp))
          .length;
    });
  }

  // Future<void> _addTipper(BuildContext context) async {
  //   Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (context) => TipperAdminEditPage(tipperViewModel, null),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
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
        // TODO only supprt editing tippers for now. In theory new tippers can register themselves via the app.
        // floatingActionButton: FloatingActionButton(
        //   onPressed: () async {
        //     await _addTipper(context);
        //   },
        //   child: const Icon(Icons.add),
        // ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    FilterChip(
                      label: Text('Paid current ($paidCurrentCount)'),
                      selected: _showPaidCurrent,
                      onSelected: (bool selected) {
                        setState(() {
                          _showPaidCurrent = selected;
                        });
                      },
                    ),
                  ],
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
                        var tippers = snapshot.data!;
                        if (_showPaidCurrent) {
                          tippers = tippers
                              .where((tipper) => tipper.paidForComp(
                                  di<DAUCompsViewModel>().activeDAUComp))
                              .toList();
                          paidCurrentCount = tippers.length;
                        }
                        return Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                //controller: _scrollController,
                                itemCount: tippers.length,
                                itemBuilder: (context, index) {
                                  var tipper = tippers[index];

                                  bool tipperActiveInCurrentComp =
                                      tipper.paidForComp(di<DAUCompsViewModel>()
                                          .activeDAUComp);

                                  // create the ListTile title by concatenating the tipper name and role. if the name is null, use 'new tipper'
                                  String title =
                                      '${tipper.name} - ${tipper.tipperRole.name}';

                                  return Card(
                                    child: ListTile(
                                      dense: true,
                                      isThreeLine: true,
                                      leading: tipper.photoURL != null
                                          ? avatarPic(tipper)
                                          : null,
                                      trailing: tipperActiveInCurrentComp
                                          ? const Icon(Icons.arrow_right)
                                          : const Icon(null),
                                      title: Text(title),
                                      subtitle: Text(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        '${formatDateTime(tipper.acctLoggedOnUTC)} - ${tipper.logon}',
                                      ),
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

  String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return '?';
    }
    return DateFormat('dd MMM yy HH:mm').format(dateTime.toLocal());
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
          imageUrl: tipper.photoURL, text: tipper.name, radius: 20),
    );
  }
}
