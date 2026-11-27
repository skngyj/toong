import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ledger.dart';
import 'room_store.dart' show newId;
import '../domain/subscription.dart';
import 'ledger_store.dart';

/// 정기 구독 목록. 이 기기에만 저장한다.
class SubscriptionStore {
  static const _key = 'toong_subscriptions';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Subscription>> list() async {
    final raw = (await _prefs).getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          Subscription.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Subscription> items) async => (await _prefs)
      .setString(_key, jsonEncode(items.map((s) => s.toJson()).toList()));

  Future<Subscription?> get(String id) async =>
      (await list()).where((s) => s.id == id).firstOrNull;

  /// 새 구독이면 알림 id 시작값을 정해 넣고, 있으면 바꾼다. 저장한 값을 돌려준다.
  Future<Subscription> save(Subscription sub) async {
    final items = await list();
    var saved = sub;
    final existing = items.where((s) => s.id == sub.id).firstOrNull;
    if (saved.notifyBase == 0 && existing != null) {
      saved = saved.copyWith(notifyBase: existing.notifyBase);
    }
    if (saved.notifyBase == 0) {
      final used = items
          .map((s) => s.notifyBase)
          .fold(0, (a, b) => a > b ? a : b);
      saved = saved.copyWith(notifyBase: used + 1);
    }
    final index = items.indexWhere((s) => s.id == sub.id);
    if (index < 0) {
      items.add(saved);
    } else {
      items[index] = saved;
    }
    await _write(items);
    return saved;
  }

  Future<void> remove(String id) async =>
      _write((await list()).where((s) => s.id != id).toList());

  /// 지난 결제일마다 내 몫을 가계부에 '구독'으로 넣는다. 달마다 한 번만 넣으므로 사용자가
  /// 지운 기록은 다시 생기지 않는다. 등록한 날 이전의 결제일은 넣지 않는다.
  /// 새로 넣은 줄 수를 돌려준다.
  Future<int> importToLedger({DateTime? now, LedgerStore? ledger}) async {
    final today = now ?? DateTime.now();
    final store = ledger ?? LedgerStore();
    final items = await list();
    var added = 0;
    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final sub = items[i];
      if (sub.myShare <= 0) continue;
      final months = [...sub.ledgerMonths];
      for (final date in billingsBetween(sub, sub.createdAt, today)) {
        final month = monthKey(date);
        if (months.contains(month)) continue;
        await store.put(
          LedgerEntry(
            id: newId(),
            date: date,
            title: sub.name,
            amount: sub.myShare,
            category: '구독',
          ),
        );
        months.add(month);
        added++;
      }
      if (months.length != sub.ledgerMonths.length) {
        items[i] = sub.copyWith(ledgerMonths: months);
        changed = true;
      }
    }
    if (changed) await _write(items);
    return added;
  }
}
