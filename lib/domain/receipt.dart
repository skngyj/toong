/// 사진 종류. 영수증은 주문 내역·할인·총액을, 메뉴판은 메뉴명과 가격만 읽는다.
enum ScanMode { receipt, menu }

/// 영수증 인식 결과. 서버 함수(scan-receipt)가 돌려준 값을 담는다.
class ScannedItem {
  const ScannedItem({
    required this.name,
    required this.quantity,
    required this.amount,
    this.unitPrice,
  });
  final String name;
  final int quantity;
  final int? unitPrice;

  /// 그 줄의 합계 금액(단가 × 수량).
  final int amount;

  /// 지출 항목 이름. 수량이 2개 이상이면 `김치찌개 ×2`처럼 붙인다.
  String get label {
    if (quantity < 2) return name;
    final suffix = ' ×$quantity';
    final base = name.length + suffix.length > 40
        ? name.substring(0, 40 - suffix.length)
        : name;
    return '$base$suffix';
  }

  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
    name: json['name'] as String,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unitPrice: (json['unitPrice'] as num?)?.toInt(),
    amount: (json['amount'] as num).toInt(),
  );
}

class ScannedDiscount {
  const ScannedDiscount({required this.name, required this.amount});
  final String name;

  /// 할인 금액(양수).
  final int amount;

  factory ScannedDiscount.fromJson(Map<String, dynamic> json) =>
      ScannedDiscount(
        name: json['name'] as String,
        amount: (json['amount'] as num).toInt(),
      );
}

class ScannedReceipt {
  const ScannedReceipt({
    required this.items,
    this.discounts = const [],
    this.total,
    this.storeName,
  });
  final String? storeName;
  final List<ScannedItem> items;
  final List<ScannedDiscount> discounts;

  /// 영수증에 적힌 최종 결제 금액. 읽지 못하면 null.
  final int? total;

  int get itemsTotal => items.fold(0, (sum, item) => sum + item.amount);
  int get discountTotal => discounts.fold(0, (sum, d) => sum + d.amount);

  /// 할인을 반영한 메뉴 합계. 할인이 메뉴 합보다 크면 반영하지 않는다.
  int get netTotal =>
      discountTotal < itemsTotal ? itemsTotal - discountTotal : itemsTotal;

  /// 영수증 총액 − 할인 반영 메뉴 합. 0이면 일치, 총액을 못 읽었으면 null.
  int? get difference => total == null ? null : total! - netTotal;

  /// 지출 항목으로 쓸 이름과 금액.
  ///
  /// 할인은 메뉴 금액 비율대로 나눠 빼고, 나누어떨어지지 않는 나머지는 가장 비싼
  /// 메뉴에서 뺀다. 그래서 항목 합은 [netTotal]과 같고 모든 항목은 1원 이상이다.
  List<({String name, int amount})> toLines() {
    final discount = discountTotal < itemsTotal ? discountTotal : 0;
    final amounts = [
      for (final item in items)
        item.amount - item.amount * discount ~/ itemsTotal,
    ];
    var left = amounts.fold(0, (a, b) => a + b) - (itemsTotal - discount);
    while (left > 0) {
      var largest = 0;
      for (var i = 1; i < amounts.length; i++) {
        if (amounts[i] > amounts[largest]) largest = i;
      }
      final take = left < amounts[largest] - 1 ? left : amounts[largest] - 1;
      if (take <= 0) break;
      amounts[largest] -= take;
      left -= take;
    }
    return [
      for (var i = 0; i < items.length; i++)
        (name: items[i].label, amount: amounts[i]),
    ];
  }

  /// 메뉴판에서 고른 주문. [quantities]는 메뉴별 수량(0이면 빼기), [paid]는 실제 결제액.
  ///
  /// 메뉴판에는 결제 총액이 없으므로, 사용자가 적은 결제액을 총액으로 삼아 비교한다.
  ScannedReceipt order(List<int> quantities, {int? paid}) => ScannedReceipt(
    storeName: storeName,
    items: [
      for (var i = 0; i < items.length; i++)
        if (quantities[i] > 0)
          ScannedItem(
            name: items[i].name,
            quantity: quantities[i],
            unitPrice: items[i].amount,
            amount: items[i].amount * quantities[i],
          ),
    ],
    total: paid,
  );

  factory ScannedReceipt.fromJson(Map<String, dynamic> json) => ScannedReceipt(
    storeName: json['storeName'] as String?,
    items: [
      for (final item in json['items'] as List? ?? const [])
        ScannedItem.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    discounts: [
      for (final d in json['discounts'] as List? ?? const [])
        ScannedDiscount.fromJson(Map<String, dynamic>.from(d as Map)),
    ],
    total: (json['total'] as num?)?.toInt(),
  );
}
