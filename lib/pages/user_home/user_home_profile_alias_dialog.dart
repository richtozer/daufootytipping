import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_placement.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Asks for the name other tippers will see, to create it or to change it. It
/// cannot be dismissed without saving a name while the tipper has none.
Future<void> showEditAliasDialog(BuildContext context, Tipper tipper) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => EditAliasDialog(tipper: tipper),
  );
}

class EditAliasDialog extends StatefulWidget {
  const EditAliasDialog({super.key, required this.tipper});

  final Tipper tipper;

  @override
  State<EditAliasDialog> createState() => _EditAliasDialogState();
}

class _EditAliasDialogState extends State<EditAliasDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.tipper.name,
  );
  late final bool _isNewTipper = widget.tipper.name.isEmpty;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String newName = _nameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _errorMessage = 'Alias cannot be empty.');
      return;
    }
    if (newName.length < 2) {
      setState(
        () => _errorMessage = 'Alias must be at least 2 characters long.',
      );
      return;
    }
    try {
      await di<TippersViewModel>().setTipperName(widget.tipper.dbkey!, newName);
      if (!mounted) return;
      // A new tipper goes on to the home page, otherwise the dialog just closes.
      if (_isNewTipper) {
        Navigator.of(context)
            .pushReplacement(appPageRoute((context) => const HomePage()));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Short, as in landscape with the keyboard up, there is little height to
    // share: the dialog scrolls, so the field can always be brought into view,
    // and gives up some of its own padding.
    final bool short = MediaQuery.sizeOf(context).height < kShortPaneHeight;
    return AlertDialog(
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 40,
        vertical: short ? 8 : 24,
      ),
      titlePadding: EdgeInsets.fromLTRB(24, short ? 16 : 24, 24, 0),
      contentPadding: EdgeInsets.fromLTRB(
        24,
        short ? 8 : 16,
        24,
        short ? 8 : 24,
      ),
      title: Text(_isNewTipper ? 'Create Tipper Alias' : 'Edit Tipper Alias'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This is the name other tippers will see you as in the '
            'competition. It must be unique.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tipper Alias',
              hintText: 'e.g. The Oracle',
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      // The same two buttons as everywhere a choice is asked for: the quiet one
      // to back out, the green one to go ahead.
      actions: [
        if (!_isNewTipper)
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
