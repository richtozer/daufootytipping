import 'dart:async';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<Object?> values;
  late TeamLogosViewModel logos;

  setUp(() {
    values = StreamController<Object?>();
    logos = TeamLogosViewModel(source: () => values.stream);
  });

  tearDown(() async {
    logos.dispose();
    await values.close();
  });

  Future<void> emit(Object? value) async {
    values.add(value);
    await pumpEventQueue();
  }

  test('has no logos before the first value arrives', () {
    expect(logos.svgFor('nrl-Broncos'), isNull);
  });

  test('returns each team\'s svg, matching keys case-insensitively', () async {
    await emit({
      'nrl-Broncos': {'svg': '<svg id="b"/>', 'updatedUtc': 'x'},
      'afl-Carlton': {'svg': '<svg id="c"/>', 'updatedUtc': 'x'},
    });

    expect(logos.svgFor('nrl-Broncos'), '<svg id="b"/>');
    expect(logos.svgFor('NRL-broncos'), '<svg id="b"/>');
    expect(logos.svgFor('afl-Carlton'), '<svg id="c"/>');
    expect(logos.svgFor('nrl-Perth Bears'), isNull);
  });

  test('ignores malformed entries', () async {
    await emit({
      'nrl-Empty': {'svg': ''},
      'nrl-Number': {'svg': 42},
      'nrl-Leaf': 'not a map',
      'nrl-Good': {'svg': '<svg/>'},
    });

    expect(logos.svgFor('nrl-Empty'), isNull);
    expect(logos.svgFor('nrl-Number'), isNull);
    expect(logos.svgFor('nrl-Leaf'), isNull);
    expect(logos.svgFor('nrl-Good'), '<svg/>');
  });

  test('replaces the logos and notifies on every change', () async {
    var notifications = 0;
    logos.addListener(() => notifications++);

    await emit({
      'nrl-Broncos': {'svg': '<svg id="old"/>'},
    });
    await emit({
      'nrl-Broncos': {'svg': '<svg id="new"/>'},
    });
    expect(logos.svgFor('nrl-Broncos'), '<svg id="new"/>');

    await emit(null);
    expect(logos.svgFor('nrl-Broncos'), isNull);
    expect(notifications, 3);
  });
}
