import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class SelectedCompBanner extends StatelessWidget {
  const SelectedCompBanner({
    super.key,
    required this.child,
    this.dauCompsViewModel,
  });

  final Widget child;
  final DAUCompsViewModel? dauCompsViewModel;

  @override
  Widget build(BuildContext context) {
    final DAUCompsViewModel viewModel =
        dauCompsViewModel ?? di<DAUCompsViewModel>();

    return AnimatedBuilder(
      animation: viewModel,
      child: child,
      builder: (context, child) {
        final selectedComp = viewModel.selectedDAUComp;
        if (selectedComp == null || viewModel.isSelectedCompActiveComp()) {
          return child!;
        }

        return Banner(
          message: _extractCompYear(selectedComp.name),
          textStyle: const TextStyle(color: Colors.black),
          location: BannerLocation.bottomStart,
          color: Colors.orange,
          child: child!,
        );
      },
    );
  }

  String _extractCompYear(String compName) {
    final Match? match = RegExp(r'\d{4}').firstMatch(compName);
    return match?.group(0) ?? compName;
  }
}
