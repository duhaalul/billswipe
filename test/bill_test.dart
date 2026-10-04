import 'package:flutter_test/flutter_test.dart';
import 'package:billswipe/bill.dart';
import 'package:billswipe/receipt_parser.dart';

void main() {
  test('saving a bill preserves account links and the duplicate prevention reference', () {
    final bill = Bill(
      items: [],
      people: [Person(id: 'local', name: 'Teman', accountId: 'account-id')],
    );
    final restored = Bill.decode(bill.encode());
    expect(restored.id, bill.id);
    expect(restored.people.single.accountId, 'account-id');
  });
  test('ignores metadata and stops at total, including all footer numbers', () {
    final receipt = parseReceipt('''
MEMBER 12345678
No. Member 9876543
Telp 081234567890
Meja 12
Kasir 1000
Nasi Goreng 25.000
Es Teh 5.000
SUBTOTAL 30.000
PPN 3.000
TOTAL 33.000
Member 123456
Hadiah belanja 50.000
Ayam Goreng 20.000
Service 1.500
''');
    expect(receipt.items.map((item) => item.name), ['Nasi Goreng', 'Es Teh']);
    expect(receipt.tax, 3000);
    expect(receipt.service, 0);
  });

  test('grand total on its own line stops parsing but item count does not', () {
    final receipt = parseReceipt('''
TOTAL ITEM 2
Mie Level 2 15.000,00
Promo Paket 1 20.000
GRAND TOTAL
35000
Kupon 5000
Es Teh 5000
''');
    expect(receipt.items.map((item) => item.price), [15000, 20000]);
  });

  test('currency parsing rejects identifiers and handles decimal zeros', () {
    expect(parseRupiah('15.000,00'), 15000);
    expect(parseRupiah('15,000.00'), 15000);
    expect(parseRupiah('15000'), 15000);
    expect(parseRupiah('12.34.56'), isNull);
    expect(parseRupiah('0812-3456-7890'), isNull);
  });

  test('parses receipt items and separates charges', () {
    final receipt = parseReceipt('''
Nasi Goreng 25.000
Es Teh Rp5.000
PPN 3.000
Service 1.500
TOTAL 34.500
''');
    expect(receipt.items.map((item) => item.name), ['Nasi Goreng', 'Es Teh']);
    expect(receipt.items.map((item) => item.price), [25000, 5000]);
    expect(receipt.tax, 3000);
    expect(receipt.service, 1500);
  });

  test('splits every rupiah proportionally', () {
    final bill = Bill(
      items: [
        BillItem(id: 'a', name: 'A', price: 50000, ownerId: 'one'),
        BillItem(id: 'b', name: 'B', price: 20000, ownerId: 'two'),
      ],
      people: [
        Person(id: 'one', name: 'A'),
        Person(id: 'two', name: 'B'),
      ],
      tax: 7000,
      service: 3501,
      discount: 1001,
    );
    final totals = calculateTotals(bill);
    expect(totals[0].tax, 5000);
    expect(totals[1].tax, 2000);
    expect(totals.fold(0, (int sum, e) => sum + e.total), bill.total);
  });
}
