import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/view_models/search_query_provider.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
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
  static const _columns = [
    AppColumn.text('Name', sortable: true),
    AppColumn.text('Role', sortable: true),
    AppColumn.text('Last login', sortable: true, descendingFirst: true),
    AppColumn.text('Logon', sortable: true),
    AppColumn.text('Paid', sortable: true, descendingFirst: true),
    AppColumn.navigation(),
  ];
  static const double _avatarSize = 40;

  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  // Most recent logon first, so the people using the app now are at the top.
  int _sortColumn = 2;
  bool _ascending = false;

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
                  '.',
                ),
                Text('\nUse "!" for negative search.'),
                SizedBox(height: 10),
                Text('Example searches:'),
                Text(
                  'mad_kiwi - returns all tippers with "mad_kiwi" in their name, logon or email addresses',
                ),
                Text(
                  '@gmail.com - returns all tippers with "@gmail.com" in their name, logon or email addresses',
                ),
                Text('tipper - returns all tippers with "tipper" role'),
                Text('!admin - returns all tippers without "admin" role'),
                Text(
                  '2025 - returns all tippers that paid for a comp with "2025" in its name',
                ),
                Text(
                  '!2025 - returns all tippers that did not pay for a comp with "2025" in its name',
                ),
                Text('godmode - returns the tipper record in god mode'),
                Text(
                  'id=abcd - returns the tipper records with abcd in their dbkey',
                ),
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
      child: AppAdminPage(
        title: 'Admin Tippers',
        scrollsUnderControls: true,
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
                              searchQueryProvider.updateSearchQuery(
                                value.toLowerCase(),
                              );
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
                  builder: (context, tipperViewModel, searchQueryProvider, child) {
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
                                  tipperViewModel.selectedTipper.dbkey;
                        }).toList();
                      } else {
                        tippers = tippers.where((tipper) {
                          // Check for id= prefix for dbkey search
                          if (query.startsWith('id=')) {
                            final idQuery = query.substring(3).toLowerCase();
                            return (tipper.dbkey?.toLowerCase().contains(
                                  idQuery,
                                ) ??
                                false);
                          }

                          bool matches =
                              (tipper.name.toLowerCase().contains(query)) ||
                              (tipper.email?.toLowerCase().contains(query) ??
                                  false) ||
                              (tipper.logon?.toLowerCase().contains(query) ??
                                  false) ||
                              (tipper.tipperRole.name.toLowerCase().contains(
                                query,
                              )) ||
                              tipper.compsPaidFor.any(
                                (comp) =>
                                    comp.name.toLowerCase().contains(query),
                              );
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
                          child: AppTable(
                            columns: _columns,
                            rows: _rows(tippers, tipperViewModel),
                            sort: AppSort(
                              column: _sortColumn,
                              ascending: _ascending,
                            ),
                            onSort: _onSort,
                            empty: const Center(child: Text('No tippers')),
                          ),
                        ),
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

  void _onSort(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _ascending = ascending;
    });
  }

  bool _paidForCurrentComp(Tipper tipper) =>
      tipper.paidForComp(di<DAUCompsViewModel>().activeDAUComp);

  List<Tipper> _sorted(List<Tipper> tippers) {
    int byName(Tipper a, Tipper b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final sorted = [...tippers]
      ..sort((a, b) {
        final primary = switch (_sortColumn) {
          1 => a.tipperRole.name.compareTo(b.tipperRole.name),
          2 =>
            (a.acctLoggedOnUTC ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  b.acctLoggedOnUTC ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
          3 => (a.logon ?? '').toLowerCase().compareTo(
            (b.logon ?? '').toLowerCase(),
          ),
          4 => (_paidForCurrentComp(a) ? 1 : 0).compareTo(
            _paidForCurrentComp(b) ? 1 : 0,
          ),
          _ => byName(a, b),
        };
        final ordered = primary != 0 ? primary : byName(a, b);
        return _ascending ? ordered : -ordered;
      });
    return sorted;
  }

  List<AppRow> _rows(List<Tipper> tippers, TippersViewModel tipperViewModel) =>
      [
        for (final tipper in _sorted(tippers))
          AppRow(
            key: ValueKey(tipper.dbkey),
            // A tipper in god mode is tinted red.
            colour:
                tipperViewModel.inGodMode &&
                    tipper.dbkey == tipperViewModel.selectedTipper.dbkey
                ? Colors.red[100]
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TipperAdminEditPage(tipperViewModel, tipper),
              ),
            ),
            cells: [
              AppCell.text(
                tipper.name,
                leadingSize: const Size.square(_avatarSize),
                leading: avatarPic(tipper),
              ),
              AppCell.text(tipper.tipperRole.name),
              AppCell.text(formatDateTime(tipper.acctLoggedOnUTC)),
              AppCell.text(tipper.logon ?? ''),
              AppCell.text(_paidForCurrentComp(tipper) ? '\$' : ''),
              AppCell.navigation(),
            ],
          ),
      ];

  String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return '?';
    }
    return DateFormat('dd MMM yy HH:mm').format(dateTime.toLocal());
  }

  Widget avatarPic(Tipper tipper) {
    final avatar = circleAvatarWithFallback(
      imageUrl: tipper.photoURL,
      text: tipper.name,
      radius: _avatarSize / 2,
    );
    final heroTag = tipper.dbkey;
    return heroTag == null ? avatar : Hero(tag: heroTag, child: avatar);
  }
}
