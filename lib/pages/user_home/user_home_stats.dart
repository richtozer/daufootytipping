import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/leaderboard.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:flutter/material.dart';

class StatsPage extends StatefulWidget {
  late final AllScoresViewModel allScoresViewModel;
  final String currentCompDbKey;

  StatsPage(this.currentCompDbKey, {super.key}) {
    // load an instance of AllScoresViewModel from the database
    allScoresViewModel = AllScoresViewModel(currentCompDbKey);
  }

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int? sortColumnIndex;
  bool isAscending = false;

  var players = [
    {
      "Rank": "1",
      "Name": "Josh",
      "AFL": "323",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "2",
      "Name": "Rick",
      "AFL": "223",
      "NRL": "223",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "3",
      "Name": "Michael",
      "AFL": "123",
      "NRL": "323",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "4",
      "Name": "Sander",
      "AFL": "223",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "5",
      "Name": "Josh",
      "AFL": "323",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "2"
    },
    {
      "Rank": "6",
      "Name": "Rick",
      "AFL": "223",
      "NRL": "223",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "7",
      "Name": "Michael",
      "AFL": "123",
      "NRL": "323",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "8",
      "Name": "Sander",
      "AFL": "223",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "9",
      "Name": "Josh",
      "AFL": "323",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "10",
      "Name": "Rick",
      "AFL": "223",
      "NRL": "223",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "11",
      "Name": "Michael",
      "AFL": "123",
      "NRL": "323",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "12",
      "Name": "Sander",
      "AFL": "223",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "13",
      "Name": "Josh",
      "AFL": "323",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "14",
      "Name": "Rick",
      "AFL": "223",
      "NRL": "223",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "15",
      "Name": "Michael",
      "AFL": "123",
      "NRL": "323",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "16",
      "Name": "Sander",
      "AFL": "223",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "17",
      "Name": "Josh",
      "AFL": "323",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "18",
      "Name": "Rick",
      "AFL": "223",
      "NRL": "223",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "1"
    },
    {
      "Rank": "19",
      "Name": "Michael",
      "AFL": "123",
      "NRL": "323",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
    {
      "Rank": "20",
      "Name": "Sander",
      "AFL": "223",
      "NRL": "123",
      "Total": "446",
      "Margins": "2",
      "UPS": "1",
      "# rounds won": "0"
    },
  ];

  var columns = [
    "Rank",
    'Name',
    'Total',
    'NRL',
    'AFL',
    '#\nrounds\nwon',
    'Margins',
    'UPS'
  ];

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            size: column == 'Rank' ? ColumnSize.S : ColumnSize.L,
            numeric: true,
            label: Text(
              column,
            ),
            //onSort: onSort,
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<Leaderboard?>(
        future: widget.allScoresViewModel.getLeaderboardForComp(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            /*              void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      users.sort((user1, user2) =>
          compareString(ascending, user1.firstName, user2.firstName));
    } else if (columnIndex == 1) {
      users.sort((user1, user2) =>
          compareString(ascending, user1.lastName, user2.lastName));
    } else if (columnIndex == 2) {
      users.sort((user1, user2) =>
          compareString(ascending, '${user1.age}', '${user2.age}'));
    }

    setState(() {
      this.sortColumnIndex = columnIndex;
      this.isAscending = ascending;
    });
  } */

            return Padding(
              padding: const EdgeInsets.all(0.0),
              child: DataTable2(
                columnSpacing: 0,
                horizontalMargin: 0,
                minWidth: 300,
                fixedTopRows: 1,
                fixedLeftColumns: 2,
                columns: getColumns(columns),
                rows: players
                    .map<DataRow>((player) => DataRow(
                          cells: <DataCell>[
                            DataCell(Text(player['Rank']!)),
                            DataCell(Text(player['Name']!)),
                            DataCell(Text(player['Total']!)),
                            DataCell(Text(player['NRL']!)),
                            DataCell(Text(player['AFL']!)),
                            DataCell(Text(player['# rounds won']!)),
                            DataCell(Text(player['Margins']!)),
                            DataCell(Text(player['UPS']!)),
                          ],
                        ))
                    .toList(),
              ),
            );
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            return const CircularProgressIndicator();
          }
        },
      ),
    );
  }
}
