import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:billswipe/bill.dart';
import 'package:billswipe/history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'history preserves snapshots, updates by bill id, and isolates accounts',
    () async {
      final store = HistoryStore('account-a');
      final bill = Bill(
        id: 'one',
        title: 'Makan siang',
        items: [
          BillItem(id: 'food', name: 'Nasi', price: 10000, ownerId: 'me'),
        ],
        people: [Person(id: 'me', name: 'Saya')],
      );
      final saving = store.save(bill);
      bill.items.first.price = 20000;
      await saving;
      expect((await HistoryStore('account-a').read()).single.bill.total, 10000);
      expect(await HistoryStore('account-b').read(), isEmpty);
      expect(await HistoryStore(null).read(), isEmpty);
      await store.save(bill);
      expect((await store.read()).length, 1);
      expect((await store.read()).single.bill.total, 20000);
    },
  );
  test(
    'concurrent saves preserve both bills and empty bills are omitted',
    () async {
      final store = HistoryStore(null);
      await Future.wait([
        for (final id in ['a', 'b'])
          store.save(
            Bill(
              id: id,
              items: [BillItem(id: id, name: 'Item', price: 100)],
              people: [],
            ),
          ),
      ]);
      await store.save(Bill(items: [], people: []));
      expect((await store.read()).map((e) => e.bill.id).toSet(), {'a', 'b'});
    },
  );
}
