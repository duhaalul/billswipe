import 'bill.dart';

class ParsedReceipt {
  ParsedReceipt({
    required this.items,
    this.tax = 0,
    this.service = 0,
    this.discount = 0,
  });
  final List<BillItem> items;
  final int tax;
  final int service;
  final int discount;
}

int? parseRupiah(String value) {
  var amount = value.trim().replaceFirst(
    RegExp(r'^rp\.?\s*', caseSensitive: false),
    '',
  );
  // Recognize currency formatting, rather than stripping every non-digit.
  // Decimal cents must not turn 15.000,00 into 1.500.000 rupiah.
  if (RegExp(r'^\d{1,3}(?:\.\d{3})+(?:,00)?$').hasMatch(amount)) {
    amount = amount.replaceFirst(RegExp(r',00$'), '').replaceAll('.', '');
  } else if (RegExp(r'^\d{1,3}(?:,\d{3})+(?:\.00)?$').hasMatch(amount)) {
    amount = amount.replaceFirst(RegExp(r'\.00$'), '').replaceAll(',', '');
  } else if (RegExp(r'^\d+(?:[.,]00)?$').hasMatch(amount)) {
    amount = amount.replaceFirst(RegExp(r'[.,]00$'), '');
  } else {
    return null;
  }
  return int.tryParse(amount);
}

final _metadata = RegExp(
  r'^(?:(?:no\.?|nomor|id|kode)\s*[:#-]?\s*)?'
  r'(?:member(?:ship)?|mernber|m3mber|anggota|customer|pelanggan|loyalty|poin|point[s]?|'
  r'telp(?:on)?|telepon|phone|hp|wa|whatsapp|fax|npwp|'
  r'tanggal|date|waktu|time|jam|kasir|cashier|operator|staff|'
  r'transaksi|transaction|invoice|faktur|nota|struk|receipt|ref(?:erence)?|referensi|'
  r'order|pesanan|antrian|antrean|meja|table|guest|tamu|pax|'
  r'cabang|branch|outlet|store|alamat|address|jl\.?|jalan|rt|rw|'
  r'approval|auth|edc|terminal|merchant|mid|tid|saldo|balance|voucher|kupon)\b',
  caseSensitive: false,
);

final _settlement = RegExp(
  r'^(?:(?:grand|sub)\s*)?total\b|'
  r'^(?:jumlah\s*(?:item|barang|belanja|bayar)|tunai|cash|kembali(?:an)?|change|'
  r'(?:uang\s*)?bayar|payment|paid|debit|credit|kredit|visa|mastercard|qris|'
  r'pembulatan|rounding|hemat|anda\s*hemat|terima\s*kasih)\b',
  caseSensitive: false,
);

ParsedReceipt parseReceipt(String text) {
  final items = <BillItem>[];
  var tax = 0;
  var service = 0;
  var discount = 0;
  var sequence = 0;
  final priceAtEnd = RegExp(
    r'^(.+?)\s+(?:Rp\.?\s*)?([\d][\d.,]*)\s*$',
    caseSensitive: false,
  );
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    // The receipt footer can contain member IDs, points and promotions with
    // numbers. Nothing after the final-total label belongs to the item list.
    final totalLabel = line.replaceFirst(RegExp(r'^[\s*=\-:]+'), '');
    if (RegExp(
          r'^(?:grand\s*total|total)\b',
          caseSensitive: false,
        ).hasMatch(totalLabel) &&
        !RegExp(
          r'^total\s+(?:item|barang|qty|quantity|porsi)\b',
          caseSensitive: false,
        ).hasMatch(totalLabel)) {
      break;
    }
    if (_metadata.hasMatch(line) || _settlement.hasMatch(line)) continue;
    if (RegExp(r'\b\d{1,4}[/:-]\d{1,2}[/:-]\d{1,4}\b').hasMatch(line)) continue;
    final match = priceAtEnd.firstMatch(line);
    if (match == null) continue;
    final name = match.group(1)!.trim();
    final price = parseRupiah(match.group(2)!);
    if (price == null || price <= 0 || name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (RegExp(
      r'^(total|grand total|subtotal|sub total|tunai|cash|kembali|change|bayar|payment|debit|credit|visa|mastercard|qris|pembulatan|rounding)\b',
    ).hasMatch(lower)) {
      continue;
    }
    if (RegExp(r'^(pajak|ppn|pb1|tax)\b').hasMatch(lower)) {
      tax += price;
    } else if (RegExp(r'^(service|layanan|svc|biaya layanan)\b')
        .hasMatch(lower)) {
      service += price;
    } else if (RegExp(r'^(discount|diskon|potongan)\b').hasMatch(lower)) {
      discount += price;
    } else {
      final normalized = name
          .replaceFirst(RegExp(r'^\d+\s*[xX*]\s*'), '')
          .trim();
      // Bare quantities and long identifiers are not plausible item prices.
      if (price < 100 || price > 100000000) continue;
      if (RegExp(r'[a-zA-Z]').allMatches(normalized).length < 2) continue;
      if (RegExp(r'[:/@#]').hasMatch(normalized)) continue;
      items.add(
        BillItem(id: 'ocr-${sequence++}', name: normalized, price: price),
      );
    }
  }
  return ParsedReceipt(
    items: items,
    tax: tax,
    service: service,
    discount: discount,
  );
}
