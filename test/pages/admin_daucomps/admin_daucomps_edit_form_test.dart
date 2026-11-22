import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_form.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  Future<void> pumpForm(WidgetTester tester, DAUComp? comp) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminDaucompsEditForm(
              formKey: GlobalKey<FormState>(),
              daucomp: comp,
              daucompNameController: TextEditingController(),
              daucompAflJsonURLController: TextEditingController(),
              daucompNrlJsonURLController: TextEditingController(),
              nrlRegularCompEndDateController: TextEditingController(),
              aflRegularCompEndDateController: TextEditingController(),
              dauCompsViewModel: _MockDAUCompsViewModel(),
              onFormInteracted: () {},
              isLocallyMarkedActive: false,
              onActiveStatusChangedLocally: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('creating a comp asks for no cutoffs: the first download sets '
      'them from the fixture', (tester) async {
    await pumpForm(tester, null);

    expect(find.textContaining('Regular Comp Cutoff'), findsNothing);
  });

  testWidgets('an existing comp still has both cutoffs to edit', (
    tester,
  ) async {
    await pumpForm(
      tester,
      DAUComp(
        dbkey: 'comp-2027',
        name: 'DAU 2027',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: [],
      ),
    );

    expect(find.textContaining('Regular Comp Cutoff'), findsNWidgets(2));
  });
}
