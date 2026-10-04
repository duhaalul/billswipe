import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:billswipe/main.dart';
import 'package:billswipe/input_dialog.dart';
import 'package:billswipe/receipt_crop_page.dart';

final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('save and cancel keep controllers alive during dialog exit', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<List<String>>(
                  context: context,
                  builder: (_) => const InputDialog(
                    title: 'Item',
                    labels: ['Nama', 'Harga'],
                    values: ['', ''],
                    numeric: {1},
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Nasi');
    await tester.enterText(find.byType(TextField).at(1), '25000');
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(saved, ['Nasi', '25000']);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crop screen can cancel without waiting for image processing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReceiptCropPage(bytes: pixel),
                ),
              ),
              child: const Text('Open crop'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open crop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Open crop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chrome selected file renders and manual save remains usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BillHome(
          selectImage: (_) async =>
              XFile.fromData(pixel, name: 'receipt.png', mimeType: 'image/png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih foto struk'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tambah item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Nasi');
    await tester.enterText(find.byType(TextField).at(1), '25000');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Nasi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);
}
