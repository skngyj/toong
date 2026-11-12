import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/record.dart';

/// 완료된 정산 기록을 이 기기에만 저장한다. 서버에는 보내지 않는다.
class RecordStore {
  static const _key = 'toong_records';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 최근에 완료한 기록부터 돌려준다.
  Future<List<SettlementRecord>> list() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_key) ?? [])
        .map(SettlementRecord.decode)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  /// 완료된 방의 기록을 저장한다. 이미 저장한 방이나 완료되지 않은 방은 건너뛴다.
  Future<void> keep(Room room) async {
    if (!room.isCompleted) return;
    final prefs = await _prefs;
    final raw = prefs.getStringList(_key) ?? [];
    if (raw.map(SettlementRecord.decode).any((r) => r.roomId == room.id)) {
      return;
    }
    await prefs.setStringList(_key, [
      ...raw,
      SettlementRecord.fromRoom(room).encode(),
    ]);
  }

  Future<void> remove(String roomId) async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_key) ?? [];
    await prefs.setStringList(
      _key,
      raw.where((s) => SettlementRecord.decode(s).roomId != roomId).toList(),
    );
  }
}
