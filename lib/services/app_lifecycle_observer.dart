import 'dart:async';
import 'package:flutter/material.dart';

class AppLifecycleObserver with WidgetsBindingObserver {
  final _lifecycleController = StreamController<AppLifecycleState>.broadcast();

  AppLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  Stream<AppLifecycleState> get lifecycleStateStream =>
      _lifecycleController.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleController.add(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleController.close();
  }
}
