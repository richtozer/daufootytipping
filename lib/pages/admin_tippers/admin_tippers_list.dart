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
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  late final TippersViewModel tipperViewModel;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    tipperViewModel = di<TippersViewModel>();
  }

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
        // TODO only support editing tippers for now. In theory new tippers can register themselves via the app.
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 8),
                      Tooltip(
                        message:
                            'Search tipers by name, email, logon, role, or competition name. Use "!" for negative search.\n\nExample searches:'
                            '\nmad_kiwi - returns all tippers with "mad_kiwi" in their name, logon or email addresses'
                            '\n@gmail.com - returns all tippers with "@gmail.com" in their name, logon or email adresses'
                            '\ntipper - returns all tippers with "tipper" role'
                            '\n!admin - returns all tippers without "admin" role'
                            '\n2025 - returns all tippers that paid for a comp with "2025" in its name'
                            '\n!2025 - returns all tippers that did not pay for a comp with "2025" in its name'
                            '\netc',
                        child: Icon(Icons.info_outline),
                      ),
                    ],
                  ),
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
                        int totalTippers = tippers.length;
                        if (_searchQuery.isNotEmpty) {
                          bool isNegativeSearch = _searchQuery.startsWith('!');
                          String query = isNegativeSearch
                              ? _searchQuery.substring(1)
                              : _searchQuery;

                          tippers = tippers.where((tipper) {
                            bool matches = (tipper
                                        .name
                                        ?.toLowerCase()
                                        .contains(query) ??
                                    false) ||
                                (tipper.email?.toLowerCase().contains(query) ??
                                    false) ||
                                (tipper.logon?.toLowerCase().contains(query) ??
                                    false) ||
                                (tipper.tipperRole.name
                                        .toLowerCase()
                                        .contains(query) ??
                                    false) ||
                                tipper.compsPaidFor.any((comp) =>
                                    comp.name.toLowerCase().contains(query));
                            return isNegativeSearch ? !matches : matches;
                          }).toList();
                        }
                        int filteredTippers = tippers.length;
                        return Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                'Showing $filteredTippers of $totalTippers tippers',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
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
