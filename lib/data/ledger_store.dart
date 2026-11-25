import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ledger.dart';
import '../domain/models.dart';

/// 개인 가계부와 월 예산을 이 기기에만 저장한다. 서버에는 보내지 않는다.
class LedgerStore {
  static const _entriesKey = 'toong_ledger';
  static const _roomsKey = 'toong_ledger_rooms';
  static const _budgetKey = 'toong_budget';
  static const _alertKey = 'toong_budget_alert';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 최근 날짜부터 돌려준다.
  Future<List<LedgerEntry>> list() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_entriesKey) ?? [])
        .map(LedgerEntry.decode)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _write(List<LedgerEntry> entries) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _entriesKey,
      entries.map((e) => e.encode()).toList(),
    );
  }

  /// 새 기록을 넣거나 같은 id의 기록을 바꾼다.
  Future<void> put(LedgerEntry entry) async {
    final entries = await list();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _write(entries);
  }

  Future<void> remove(String id) async =>
      _write((await list()).where((e) => e.id != id).toList());

  /// 완료된 방에서 내 부담액을 지출 한 건당 한 줄로 넣는다. 방마다 한 번만 넣으므로
  /// 사용자가 지운 기록이 다시 생기지 않는다. 새로 넣었으면 true.
  Future<bool> importRoom(Room room, String actorId) async {
    if (!room.isCompleted) return false;
    final me = room.actorMember(actorId);
    if (me == null) return false;
    final prefs = await _prefs;
    final imported = prefs.getStringList(_roomsKey) ?? [];
    if (imported.contains(room.id)) return false;
    final entries = await list();
    entries.addAll(entriesFromRoom(room, me.id));
    await _write(entries);
    await prefs.setStringList(_roomsKey, [...imported, room.id]);
    return true;
  }

  /// 한 달 예산. 정하지 않았으면 null.
  Future<int?> budget() async {
    final value = (await _prefs).getInt(_budgetKey);
    return value != null && value > 0 ? value : null;
  }

  /// 예산을 정한다. null이나 0이면 예산을 없앤다.
  Future<void> setBudget(int? value) async {
    final prefs = await _prefs;
    if (value == null || value <= 0) {
      await prefs.remove(_budgetKey);
    } else {
      await prefs.setInt(_budgetKey, value);
    }
    await prefs.remove(_alertKey);
  }

  /// 이번 달 사용액이 예산의 80%나 100%를 처음 넘었으면 알림 문구를 돌려준다.
  /// 같은 달에 같은 단계는 한 번만 알린다.
  Future<String?> budgetAlert({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final limit = await budget();
    final spent = sumOf(inMonth(await list(), today));
    final level = budgetLevel(spent, limit);
    final prefs = await _prefs;
    final month = '${today.year}-${today.month}';
    final saved = (prefs.getString(_alertKey) ?? '').split(':');
    final shown = saved.first == month && saved.length == 2
        ? int.tryParse(saved.last) ?? 0
        : 0;
    if (level <= shown) return null;
    await prefs.setString(_alertKey, '$month:$level');
    return budgetMessage(spent, limit!);
  }
}

/// 예산 알림 문구.
String budgetMessage(int spent, int budget) {
  String won(int v) =>
      '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';
  final percent = spent * 100 ~/ budget;
  return spent >= budget
      ? '이번 달 예산 ${won(budget)}을 넘었어요. 지금까지 ${won(spent)}($percent%)을 썼어요.'
      : '이번 달 예산의 $percent%를 썼어요. 예산 ${won(budget)} 중 ${won(budget - spent)} 남았어요.';
}
