import 'package:daufootytipping/models/leaderboard.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  late final AllScoresViewModel allScoresViewModel;
  final String currentCompDbKey;

  StatsPage(this.currentCompDbKey, {super.key}) {
    // load an instance of AllScoresViewModel from the database
    allScoresViewModel = AllScoresViewModel(currentCompDbKey);
  }
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<Leaderboard>(
        future: allScoresViewModel.getLeaderboardForComp(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            var players = [
              {
                "Name": "Josh",
                "AFL": "323",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Rick",
                "AFL": "223",
                "NRL": "223",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Michael",
                "AFL": "123",
                "NRL": "323",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Sander",
                "AFL": "223",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Josh",
                "AFL": "323",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Rick",
                "AFL": "223",
                "NRL": "223",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Michael",
                "AFL": "123",
                "NRL": "323",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Sander",
                "AFL": "223",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Josh",
                "AFL": "323",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Rick",
                "AFL": "223",
                "NRL": "223",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Michael",
                "AFL": "123",
                "NRL": "323",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Sander",
                "AFL": "223",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Josh",
                "AFL": "323",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Rick",
                "AFL": "223",
                "NRL": "223",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Michael",
                "AFL": "123",
                "NRL": "323",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Sander",
                "AFL": "223",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Josh",
                "AFL": "323",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Rick",
                "AFL": "223",
                "NRL": "223",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Michael",
                "AFL": "123",
                "NRL": "323",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
              {
                "Name": "Sander",
                "AFL": "223",
                "NRL": "123",
                "Total": "446",
                "Margins": "2",
                "UPS": "1"
              },
            ];

            return InteractiveViewer(
              constrained: false,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(
                    label: Text(
                      'Name',
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'AFL',
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'NRL',
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Total',
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Margins',
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'UPS',
                    ),
                  ),
                ],
                rows: players
                    .map<DataRow>((player) => DataRow(
                          cells: <DataCell>[
                            DataCell(Text(player['Name']!)),
                            DataCell(Text(player['AFL']!)),
                            DataCell(Text(player['NRL']!)),
                            DataCell(Text(player['Total']!)),
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
