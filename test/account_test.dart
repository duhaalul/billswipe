import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billswipe/social/account_gate.dart';

void main() {
  testWidgets(
    'without configuration account actions are disabled and offline remains available',
    (tester) async {
      var offline = false;
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(onOffline: () => offline = true)),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Masuk'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Lanjutkan dengan Google'),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Gunakan tanpa akun'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Gunakan tanpa akun'));
      expect(offline, isTrue);
    },
  );
}
