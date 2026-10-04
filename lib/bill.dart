import 'dart:convert';

class BillItem {
  BillItem({
    required this.id,
    required this.name,
    required this.price,
    this.ownerId,
  });

  final String id;
  String name;
  int price;
  String? ownerId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'ownerId': ownerId,
  };

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
    id: json['id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toInt(),
    ownerId: json['ownerId'] as String?,
  );
}

class Person {
  Person({required this.id, required this.name, this.accountId});
  final String id;
  String name;
  final String? accountId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'accountId': accountId,
  };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String,
    accountId: json['accountId'] as String?,
  );
}

class Bill {
  Bill({
    required this.items,
    required this.people,
    this.tax = 0,
    this.service = 0,
    this.discount = 0,
    this.title = 'Tagihan baru',
    String? id,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;

  List<BillItem> items;
  List<Person> people;
  int tax;
  int service;
  int discount;
  String title;

  int get subtotal => items.fold(0, (sum, item) => sum + item.price);
  int get total => subtotal + tax + service - discount;
  int get unclaimed => items.where((item) => item.ownerId == null).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((e) => e.toJson()).toList(),
    'people': people.map((e) => e.toJson()).toList(),
    'tax': tax,
    'service': service,
    'discount': discount,
    'title': title,
  };

  String encode() => jsonEncode(toJson());

  factory Bill.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return Bill(
      id: json['id'] as String?,
      items: (json['items'] as List<dynamic>)
          .map((e) => BillItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      people: (json['people'] as List<dynamic>)
          .map((e) => Person.fromJson(e as Map<String, dynamic>))
          .toList(),
      tax: (json['tax'] as num?)?.toInt() ?? 0,
      service: (json['service'] as num?)?.toInt() ?? 0,
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'Tagihan baru',
    );
  }
}

class PersonTotal {
  PersonTotal({
    required this.person,
    required this.subtotal,
    required this.tax,
    required this.service,
    required this.discount,
  });
  final Person person;
  final int subtotal;
  final int tax;
  final int service;
  final int discount;
  int get total => subtotal + tax + service - discount;
}

/// Largest-remainder allocation keeps every rupiah accounted for.
List<int> allocateProportionally(int amount, List<int> weights) {
  if (amount < 0) throw ArgumentError.value(amount, 'amount');
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (sum == 0) return List.filled(weights.length, 0);
  final base = <int>[for (final weight in weights) amount * weight ~/ sum];
  var remaining = amount - base.fold<int>(0, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final remainderA = amount * weights[a] % sum;
      final remainderB = amount * weights[b] % sum;
      final comparison = remainderB.compareTo(remainderA);
      return comparison == 0 ? a.compareTo(b) : comparison;
    });
  for (final index in order) {
    if (remaining == 0) break;
    base[index]++;
    remaining--;
  }
  return base;
}

List<PersonTotal> calculateTotals(Bill bill) {
  final subtotals = [
    for (final person in bill.people)
      bill.items
          .where((item) => item.ownerId == person.id)
          .fold(0, (int sum, item) => sum + item.price),
  ];
  final taxes = allocateProportionally(bill.tax, subtotals);
  final services = allocateProportionally(bill.service, subtotals);
  final discounts = allocateProportionally(bill.discount, subtotals);
  return [
    for (var i = 0; i < bill.people.length; i++)
      PersonTotal(
        person: bill.people[i],
        subtotal: subtotals[i],
        tax: taxes[i],
        service: services[i],
        discount: discounts[i],
      ),
  ];
}
