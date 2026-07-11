import 'package:daufootytipping/services/realtime_connection_service.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class OfflineConnectionBanner extends StatelessWidget {
  const OfflineConnectionBanner({
    super.key,
    required this.child,
    this.connectionService,
  });

  final Widget child;
  final RealtimeConnectionService? connectionService;

  @override
  Widget build(BuildContext context) {
    final service = connectionService ?? di<RealtimeConnectionService>();

    return AnimatedBuilder(
      animation: service,
      child: child,
      builder: (context, child) {
        if (!service.isOffline) {
          return child!;
        }

        return Banner(
          message: 'OFFLINE',
          textStyle: const TextStyle(color: Colors.black),
          location: BannerLocation.topStart,
          color: Colors.orange,
          child: child!,
        );
      },
    );
  }
}
