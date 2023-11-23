import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:flutter/material.dart';

class AdminHomePage extends StatelessWidget {
  static const String route = '/Admin';
  const AdminHomePage({super.key});

  Future<void> _adminTippers(BuildContext context) async {
    await Navigator.of(context).pushNamed(TippersAdminPage.route);
  }

  Future<void> _adminDAUComps(BuildContext context) async {
    await Navigator.of(context).pushNamed(DAUCompsListPage.route);
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
          title: const Text('Admin Home'),
        ),
        body: ListView(
          children: [
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.people),
                title: const Text('Admin Tippers'),
                onTap: () async {
                  // Trigger edit functionality
                  await _adminTippers(context);
                },
              ),
            ),
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.sports_rugby),
                title: const Text('Admin DAU Comps'),
                onTap: () async {
                  // Trigger edit functionality
                  await _adminDAUComps(context);
                },
              ),
            ),
          ],
        ));
  }
}
