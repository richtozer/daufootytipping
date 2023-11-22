import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:provider/provider.dart';

class TipperAdminEditPage extends StatefulWidget {
  static const String route = '/AdminTippersEdit';

  //final TippersViewModel tipperViewModel;
  final Tipper tipper;

  //constructor
  //const TipperAdminEditPage(this.tipperViewModel, this.tipper, {super.key});
  const TipperAdminEditPage(this.tipper, {super.key});

  @override
  State<TipperAdminEditPage> createState() => _FormEditTipperState();
}

class _FormEditTipperState extends State<TipperAdminEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _tipperNameController;
  late TextEditingController _tipperEmailController;
  final FocusNode _emailFocusNode = FocusNode();
  late Tipper tipper;
  late bool active;
  late bool admin;

  @override
  void initState() {
    super.initState();
    tipper = widget.tipper;
    active = tipper.active;
    admin = (tipper.tipperRole == TipperRole.admin) ? true : false;
    _tipperNameController = TextEditingController(text: tipper.name);
    _tipperEmailController = TextEditingController(text: tipper.email);
  }

  @override
  void dispose() {
    _tipperNameController.dispose();
    _tipperEmailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveTipper(BuildContext context, TippersViewModel model) async {
    try {
      //create a new temp Tipper object to pass the changes to the viewmodel
      Tipper tipperEdited = Tipper(
          name: _tipperNameController.text,
          email: _tipperEmailController.text,
          dbkey: tipper.dbkey,
          authuid: tipper.authuid,
          active: active,
          tipperRole: admin == true ? TipperRole.admin : TipperRole.tipper);

      await model.editTipper(tipperEdited);

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
      //}
    } on Exception {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('Failed to update the tipper'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Tipper'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: [
                  const Text('Name:'),
                  Expanded(
                    child: TextFormField(
                      controller: _tipperNameController,
                      decoration: const InputDecoration(
                        hintText: 'Tipper name',
                      ),
                      onFieldSubmitted: (_) {
                        // move focus to next field
                        _emailFocusNode.requestFocus();
                      },
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a tipper name';
                        }
                        return null;
                      },
                    ),
                  )
                ],
              ),
              Row(
                children: [
                  const Text('Email:'),
                  Expanded(
                    child: TextFormField(
                      controller: _tipperEmailController,
                      decoration: const InputDecoration(
                        hintText: 'Tipper email',
                      ),
                      validator: (String? value) {
                        if (value == null || !EmailValidator.validate(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              Row(children: [
                const Text('Active:'),
                Switch(
                  value: active,
                  activeColor: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      active = value;
                    });
                  },
                ),
              ]),
              Row(
                children: [
                  const Text('DAU Admin:'),
                  Switch(
                    value: admin,
                    activeColor: Colors.yellow,
                    onChanged: (value) {
                      setState(() {
                        admin = value;
                      });
                    },
                  ),
                ],
              ),
              Consumer<TippersViewModel>(
                  builder: (context, tipperViewModel, child) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: ElevatedButton(
                        onPressed:
                            // swallow any double presses of Save button
                            // if the saving flag is set
                            tipperViewModel.savingTipper
                                ? null
                                : () async {
                                    // Validate will return true if the form is valid, or false if
                                    // the form is invalid.
                                    final isValid =
                                        _formKey.currentState!.validate();
                                    if (isValid) {
                                      print('saving');
                                      await _saveTipper(
                                          context, tipperViewModel);
                                    }
                                  },
                        child: const Text('Save'),
                      ),
                    ),
                    if (tipperViewModel.savingTipper) ...const <Widget>[
                      SizedBox(height: 32),
                      CircularProgressIndicator(),
                    ]
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
