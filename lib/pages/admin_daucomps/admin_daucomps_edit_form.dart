import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

class AdminDaucompsEditForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final DAUComp? daucomp;
  final TextEditingController daucompNameController;
  final TextEditingController daucompAflJsonURLController;
  final TextEditingController daucompNrlJsonURLController;
  final TextEditingController nrlRegularCompEndDateController;
  final TextEditingController aflRegularCompEndDateController;
  final DAUCompsViewModel
      dauCompsViewModel; // This is the dauCompsViewModeconsumer from parent
  final VoidCallback onFormInteracted;
  final bool isLocallyMarkedActive; // New
  final Function(bool newValue) onActiveStatusChangedLocally; // New

  const AdminDaucompsEditForm({
    super.key,
    required this.formKey,
    required this.daucomp,
    required this.daucompNameController,
    required this.daucompAflJsonURLController,
    required this.daucompNrlJsonURLController,
    required this.nrlRegularCompEndDateController,
    required this.aflRegularCompEndDateController,
    required this.dauCompsViewModel,
    required this.onFormInteracted,
    required this.isLocallyMarkedActive, // New
    required this.onActiveStatusChangedLocally, // New
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: [
              if (daucomp != null)
                const Text('Active\nComp:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              if (daucomp != null)
                Switch(
                  value: isLocallyMarkedActive,
                  onChanged: (bool value) {
                    onActiveStatusChangedLocally(value);
                  },
                ),
              if (daucomp != null) const SizedBox(width: 10),
              const Text('Name: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: TextFormField(
                  controller: daucompNameController,
                  decoration: const InputDecoration(
                    hintText: 'DAU Comp name',
                    isDense: true,
                  ),
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a DAU Comp name';
                    }
                    return null;
                  },
                ),
              )
            ],
          ),
          const Text('NRL json URL:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'enter URL here',
                    isDense: true,
                  ),
                  controller: daucompNrlJsonURLController,
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a NRL fixture link';
                    }
                    return null;
                  },
                ),
              )
            ],
          ),
          const Text('AFL json URL:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'enter URL here',
                    isDense: true,
                  ),
                  controller: daucompAflJsonURLController,
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a AFL fixture link';
                    }
                    return null;
                  },
                ),
              )
            ],
          ),
          Row(
            children: [
              const Text('NRL Regular Comp Cutoff: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: TextFormField(
                  controller: nrlRegularCompEndDateController,
                  decoration: const InputDecoration(
                    hintText: 'not set',
                    isDense: true,
                  ),
                  onTap: () async {
                    FocusScope.of(context).requestFocus(FocusNode());
                    DateTime? date = await showDatePicker(
                      context: context,
                      initialDate:
                          daucomp?.nrlRegularCompEndDateUTC ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      nrlRegularCompEndDateController.text =
                          DateFormat('yyyy-MM-dd').format(date);
                      onFormInteracted();
                    }
                  },
                  validator: (String? value) {
                    if (value != null && value.isNotEmpty) {
                      try {
                        DateFormat('yyyy-MM-dd').parse(value);
                      } catch (e) {
                        return 'Invalid date format';
                      }
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  nrlRegularCompEndDateController.clear();
                  onFormInteracted();
                },
              ),
            ],
          ),
          Row(
            children: [
              const Text('AFL Regular Comp Cutoff: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: TextFormField(
                  controller: aflRegularCompEndDateController,
                  decoration: const InputDecoration(
                    hintText: 'not set',
                    isDense: true,
                  ),
                  onTap: () async {
                    FocusScope.of(context).requestFocus(FocusNode());
                    DateTime? date = await showDatePicker(
                      context: context,
                      initialDate:
                          daucomp?.aflRegularCompEndDateUTC ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      aflRegularCompEndDateController.text =
                          DateFormat('yyyy-MM-dd').format(date);
                      onFormInteracted();
                    }
                  },
                  validator: (String? value) {
                    if (value != null && value.isNotEmpty) {
                      try {
                        DateFormat('yyyy-MM-dd').parse(value);
                      } catch (e) {
                        return 'Invalid date format';
                      }
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  aflRegularCompEndDateController.clear();
                  onFormInteracted();
                },
              ),
            ],
          ),
          const SizedBox(height: 20.0),
          if (daucomp == null) ...[
            const Text(
                'After adding a new comp name and URLs, click the save button and then reopen this record to see the round details.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}
