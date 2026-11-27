import 'package:shared_preferences/shared_preferences.dart';

/// 이 기기에 저장한 내 닉네임. 방을 만들거나 들어갈 때 자동으로 채운다.
/// 로그인이 없으므로 앱을 지우면 함께 지워진다.
class NicknameStore {
  static const _key = 'toong_nickname';

  Future<String?> load() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(_key);
      return value == null || value.trim().isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// 빈 값이나 null이면 지운다.
  Future<void> save(String? nickname) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = nickname?.trim() ?? '';
    if (clean.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        clean.length > 12 ? clean.substring(0, 12) : clean,
      );
    }
  }
}

/// 시간에 따른 인사말. 5~11시 아침, 11~17시 점심, 그 밖은 저녁.
String greeting(DateTime now, String? nickname) {
  final hour = now.hour;
  final who = nickname == null ? '' : '$nickname 님, ';
  if (hour >= 5 && hour < 11) return '$who좋은 아침이에요 ☀️';
  if (hour >= 11 && hour < 17) return '$who점심은 맛있게 드셨나요? 🍚';
  return '$who오늘 하루도 수고했어요 🌙';
}
