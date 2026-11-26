import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/receipt.dart';

/// 영수증 사진을 읽어 메뉴·금액을 돌려준다.
abstract class ReceiptScanner {
  Future<ScannedReceipt> scan(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  });
}

/// Supabase Edge Function `scan-receipt`(Gemini)로 영수증을 읽는다.
/// API 키는 서버 함수에만 있고 앱에는 없다.
class CloudReceiptScanner implements ReceiptScanner {
  CloudReceiptScanner(this.client);
  final SupabaseClient client;

  @override
  Future<ScannedReceipt> scan(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  }) async {
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final body = {'image': base64Encode(image), 'mimeType': mimeType};
    try {
      FunctionResponse response;
      try {
        response = await client.functions.invoke('scan-receipt', body: body);
      } on FunctionException catch (error) {
        // 서버가 정리한 익명 사용자의 세션이면 새 익명 사용자로 다시 로그인해 한 번 더
        // 시도한다. 다른 401에서 다시 로그인하면 참여 중인 방을 잃으므로 하지 않는다.
        final details = error.details;
        if (error.status != 401 ||
            details is! Map ||
            details['code'] != 'session_gone') {
          rethrow;
        }
        await client.auth.signOut(scope: SignOutScope.local);
        await client.auth.signInAnonymously();
        response = await client.functions.invoke('scan-receipt', body: body);
      }
      return ScannedReceipt.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : '영수증을 읽지 못했어요. 잠시 후 다시 시도하거나 직접 입력해주세요.';
      throw StateError(message);
    }
  }
}
