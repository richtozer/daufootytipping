import 'package:daufootytipping/services/tipping_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absent and invalid grace use two minutes; zero disables grace', () {
    for (final value in [null, '120', -1, 0.5, double.infinity]) {
      expect(parseTipGracePeriodSeconds(value), 120);
    }
    expect(parseTipGracePeriodSeconds(0), 0);
    expect(parseTipGracePeriodSeconds(300), 300);
  });

  test('tipping closes exactly at kickoff plus the configured grace', () {
    final kickoff = DateTime.utc(2027, 3, 1, 10);
    expect(tippingIsOpen(kickoff, now: kickoff), isTrue);
    expect(tippingIsOpen(kickoff, now: kickoff.add(const Duration(seconds: 119))), isTrue);
    expect(tippingIsOpen(kickoff, now: kickoff.add(const Duration(seconds: 120))), isFalse);
    expect(tippingIsOpen(kickoff, now: kickoff, graceSeconds: 0), isFalse);
    expect(tippingIsOpen(kickoff, now: kickoff.add(const Duration(seconds: 150)), graceSeconds: 300), isTrue);
  });
}
