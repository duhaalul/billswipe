import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billswipe/social/email_confirmation.dart';

void main() {
  testWidgets('invalid confirmation code stays on screen without submitting', (
    tester,
  ) async {
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EmailConfirmation(
          email: 'test@example.com',
          onBack: () => returned = true,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verifikasi email'));
    await tester.pump();
    expect(find.text('Masukkan kode angka dari email Anda.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(returned, isTrue);
  });
}
