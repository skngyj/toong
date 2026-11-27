/// 영수증 인식 결과. 서버 함수(scan-receipt)가 돌려준 값을 담는다.
class ScannedItem {
  const ScannedItem({
    required this.name,
    required this.quantity,
    required this.amount,
    this.unitPrice,
    this.amountGuessed = false,
  });

  /// 메뉴 이름. 가려지거나 흐려 못 읽었으면 null.
  final String? name;
  final int quantity;
  final int? unitPrice;

  /// 그 줄의 합계 금액(단가 × 수량). 가려지거나 흐려 못 읽었으면 null.
  final int? amount;

  /// 금액을 못 읽어 영수증 총액에서 나머지 메뉴를 빼 계산한 값이면 true.
  final bool amountGuessed;

  /// 지출 항목 이름. 수량이 2개 이상이면 `김치찌개 ×2`처럼 붙인다.
  /// 이름을 못 읽었으면 [fallback]("메뉴 1" 등)을 쓴다.
  String label(String fallback) {
    final base0 = name ?? fallback;
    if (quantity < 2) return base0;
    final suffix = ' ×$quantity';
    final base = base0.length + suffix.length > 40
        ? base0.substring(0, 40 - suffix.length)
        : base0;
    return '$base$suffix';
  }

  ScannedItem withGuess(int value) => ScannedItem(
    name: name,
    quantity: quantity,
    unitPrice: unitPrice,
    amount: value,
    amountGuessed: true,
  );

  factory ScannedItem.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim();
    return ScannedItem(
      name: name == null || name.isEmpty ? null : name,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unitPrice'] as num?)?.toInt(),
      amount: (json['amount'] as num?)?.toInt(),
    );
  }
}

/// 지출 항목으로 옮길 한 줄. 가려져 못 읽은 칸을 표시한다.
typedef ScannedLine = ({
  String name,
  int? amount,
  bool nameHidden,
  bool amountHidden,
  bool amountGuessed,
});

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

  /// 금액을 읽은 메뉴의 합.
  int get itemsTotal => items.fold(0, (sum, item) => sum + (item.amount ?? 0));

  /// 이름이나 금액이 가려져 못 읽은 칸 수.
  int get hiddenCount => items.fold(
    0,
    (sum, i) => sum + (i.name == null ? 1 : 0) + (i.amount == null ? 1 : 0),
  );

  /// 금액을 못 읽은 메뉴가 딱 하나이고 영수증 총액을 읽었으면, 총액에 할인을 더하고
  /// 나머지 메뉴를 빼 그 금액을 채운다. 계산 결과가 1원 미만이면 채우지 않는다.
  ScannedReceipt withGuessedAmount() {
    final missing = [
      for (final (i, item) in items.indexed)
        if (item.amount == null) i,
    ];
    if (missing.length != 1 || total == null) return this;
    final guess = total! + discountTotal - itemsTotal;
    if (guess < 1) return this;
    return ScannedReceipt(
      storeName: storeName,
      discounts: discounts,
      total: total,
      items: [
        for (final (i, item) in items.indexed)
          i == missing.single ? item.withGuess(guess) : item,
      ],
    );
  }

  int get discountTotal => discounts.fold(0, (sum, d) => sum + d.amount);

  /// 할인을 반영한 메뉴 합계. 할인이 메뉴 합보다 크면 반영하지 않는다.
  int get netTotal =>
      discountTotal < itemsTotal ? itemsTotal - discountTotal : itemsTotal;

  /// 영수증 총액 − 할인 반영 메뉴 합. 0이면 일치, 총액을 못 읽었으면 null.
  int? get difference => total == null ? null : total! - netTotal;

  /// 지출 항목으로 쓸 이름과 금액.
  ///
  /// 할인은 금액을 읽은 메뉴의 금액 비율대로 나눠 빼고, 나누어떨어지지 않는 나머지는
  /// 가장 비싼 메뉴에서 뺀다. 그래서 금액을 읽은 항목의 합은 [netTotal]과 같고 모두
  /// 1원 이상이다. 이름을 못 읽은 메뉴는 "메뉴 1"부터 차례로 이름을 붙이고, 금액을
  /// 못 읽은 메뉴는 금액을 비워 둔다.
  List<ScannedLine> toLines() {
    final discount = discountTotal < itemsTotal ? discountTotal : 0;
    final amounts = <int?>[
      for (final item in items)
        item.amount == null
            ? null
            : item.amount! - item.amount! * discount ~/ itemsTotal,
    ];
    var left =
        amounts.fold(0, (a, b) => a + (b ?? 0)) - (itemsTotal - discount);
    while (left > 0) {
      int? largest;
      for (var i = 0; i < amounts.length; i++) {
        if (amounts[i] != null &&
            (largest == null || amounts[i]! > amounts[largest]!)) {
          largest = i;
        }
      }
      if (largest == null) break;
      final take = left < amounts[largest]! - 1 ? left : amounts[largest]! - 1;
      if (take <= 0) break;
      amounts[largest] = amounts[largest]! - take;
      left -= take;
    }
    var unnamed = 0;
    return [
      for (var i = 0; i < items.length; i++)
        (
          name: items[i].label(items[i].name == null ? '메뉴 ${++unnamed}' : ''),
          amount: amounts[i],
          nameHidden: items[i].name == null,
          amountHidden: items[i].amount == null,
          amountGuessed: items[i].amountGuessed,
        ),
    ];
  }

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
