import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  //appstate for tiles in user_home_tips.dart
  List<bool> _expandedStates = List<bool>.filled(120,
      false); //TODO consider using a calculation here for max number of tiles to track
  List<bool> get expandedStates => _expandedStates;
  void setExpandedState(int index, bool isExpanded) {
    _expandedStates[index] = isExpanded;
    notifyListeners();
  }
}
