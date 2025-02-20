import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/view_models/search_query_provider.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  void _showSearchHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Search Help'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Filter tippers by name, email, logon, role, competition name or \'godmode\''
                    '.'),
                Text('\nUse "!" for negative search.'),
                SizedBox(height: 10),
                Text('Example searches:'),
                Text(
                    'mad_kiwi - returns all tippers with "mad_kiwi" in their name, logon or email addresses'),
                Text(
                    '@gmail.com - returns all tippers with "@gmail.com" in their name, logon or email addresses'),
                Text('tipper - returns all tippers with "tipper" role'),
                Text('!admin - returns all tippers without "admin" role'),
                Text(
                    '2025 - returns all tippers that paid for a comp with "2025" in its name'),
                Text(
                    '!2025 - returns all tippers that did not pay for a comp with "2025" in its name'),
                Text('godmode - returns the tipper record in god mode'),
                Text('etc'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TippersViewModel>.value(
      value: di<TippersViewModel>(),
      child: Scaffold(
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Consumer<SearchQueryProvider>(
                        builder: (context, searchQueryProvider, child) {
                          _searchController.text =
                              searchQueryProvider.searchQuery;
                          return TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'Filter tippers',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              searchQueryProvider
                                  .updateSearchQuery(value.toLowerCase());
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer2<TippersViewModel, SearchQueryProvider>(
                  builder:
                      (context, tipperViewModel, searchQueryProvider, child) {
                    var tippers = tipperViewModel.tippers;
                    int totalTippers = tippers.length;
                    String searchQuery = searchQueryProvider.searchQuery;
                    if (searchQuery.isNotEmpty) {
                      bool isNegativeSearch = searchQuery.startsWith('!');
                      String query = isNegativeSearch
                          ? searchQuery.substring(1)
                          : searchQuery;

                      // Add godmode filter
                      if (query == 'godmode') {
                        tippers = tippers.where((tipper) {
                          return tipperViewModel.inGodMode &&
                              tipper.dbkey ==
                                  tipperViewModel.selectedTipper!.dbkey;
                        }).toList();
                      } else {
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
                                  .contains(query)) ||
                              tipper.compsPaidFor.any((comp) =>
                                  comp.name.toLowerCase().contains(query));
                          return isNegativeSearch ? !matches : matches;
                        }).toList();
                      }
                    }
                    int filteredTippers = tippers.length;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Showing $filteredTippers of $totalTippers tippers',
                                style: TextStyle(fontSize: 16),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline),
                                onPressed: () {
                                  _showSearchHelpDialog(context);
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: tippers.length,
                            itemBuilder: (context, index) {
                              var tipper = tippers[index];

                              bool tipperPaidForCurrentComp =
                                  tipper.paidForComp(
                                      di<DAUCompsViewModel>().activeDAUComp);

                              // create the ListTile title by concatenating the tipper name and role. if the name is null, use 'new tipper'
                              String title =
                                  '${tipper.name} - ${tipper.tipperRole.name}';

                              return Card(
                                child: ListTile(
                                  //if this tipper is in godmode then tint this ListTile in red
                                  tileColor: tipperViewModel.inGodMode &&
                                          tipper.dbkey ==
                                              tipperViewModel
                                                  .selectedTipper!.dbkey
                                      ? Colors.red[100]
                                      : null,
                                  dense: true,
                                  isThreeLine: true,
                                  leading: tipper.photoURL != null
                                      ? avatarPic(tipper)
                                      : null,
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (tipperPaidForCurrentComp)
                                        const Text('\$',
                                            style: TextStyle(fontSize: 20)),
                                    ],
                                  ),
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
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
