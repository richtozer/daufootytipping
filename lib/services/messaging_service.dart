import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';

abstract class MessagingService {
  Future<void> deleteStaleTokens(TippersViewModel tippersViewModel);
}

class FirebaseMessagingServiceAdapter implements MessagingService {
  FirebaseMessagingService? _inner;

  @override
  Future<void> deleteStaleTokens(TippersViewModel tippersViewModel) async {
    _inner ??= FirebaseMessagingService();
    await _inner!.deleteStaleTokens(tippersViewModel);
  }
}

class NoopMessagingService implements MessagingService {
  @override
  Future<void> deleteStaleTokens(TippersViewModel tippersViewModel) async {}
}

