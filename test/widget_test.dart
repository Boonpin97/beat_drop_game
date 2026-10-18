import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mariah_carey_rhythm/widgets/start_view.dart';

void main() {
  testWidgets('Play button calls onPlay', (tester) async {
    var played = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StartView(onPlay: () => played = true)),
      ),
    );
    await tester.tap(find.text('PLAY'));
    expect(played, isTrue);
  });
}
