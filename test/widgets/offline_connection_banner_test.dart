import 'package:daufootytipping/services/realtime_connection_service.dart';
import 'package:daufootytipping/widgets/offline_connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRealtimeConnectionService extends Mock
    implements RealtimeConnectionService {}

void main() {
  testWidgets('shows offline banner at top start when disconnected', (tester) async {
    final service = MockRealtimeConnectionService();
    when(() => service.isOffline).thenReturn(true);
    when(() => service.addListener(any())).thenReturn(null);
    when(() => service.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OfflineConnectionBanner(
          connectionService: service,
          child: const Text('content'),
        ),
      ),
    );

    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'OFFLINE');
    expect(banner.location, BannerLocation.topStart);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('does not show offline banner when connected', (tester) async {
    final service = MockRealtimeConnectionService();
    when(() => service.isOffline).thenReturn(false);
    when(() => service.addListener(any())).thenReturn(null);
    when(() => service.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OfflineConnectionBanner(
          connectionService: service,
          child: const Text('content'),
        ),
      ),
    );

    expect(find.byType(Banner), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });
}
