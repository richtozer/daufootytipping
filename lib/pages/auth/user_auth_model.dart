import 'package:flutter/foundation.dart';

class AuthViewModel extends ChangeNotifier {
  bool _signingIn = false;
  bool get signingIn => _signingIn;

  Future<void> signIn() async {
    try {
      _signingIn = true;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 3), () {});
      // TODO: handle signing in
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }
}
