import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'fun.dart';

/// 앱 색. 앱 아이콘(검정 바탕 위 흰 영수증, 검정 글씨)과 같은 흑백 계열이다.
const toongInk = Color(0xFF111111);

/// 아이콘 바탕색. 진한 강조가 필요할 때 쓴다.
const toongDark = Color(0xFF222222);

/// 화면 바탕. 영수증 종이처럼 흰색.
const toongCanvas = Color(0xFFFFFFFF);

/// 카드·안내 상자 바탕. 아주 옅은 회색.
const toongSoft = Color(0xFFF2F2F0);

/// 테두리·구분선.
const toongLine = Color(0xFFDDDDDA);

/// 보조 글씨.
const toongSub = Color(0xFF6B6B6B);

/// 주의가 필요한 안내 상자 바탕(삭제 임박, 금액 불일치, 예산 초과 직전).
const toongWarn = Color(0xFFFFF1E6);

/// 취소 버튼, 예산 초과처럼 위험을 알리는 색.
const toongDanger = Color(0xFFE5484D);

ThemeData toongTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: toongInk,
    primary: toongInk,
    onPrimary: Colors.white,
    secondaryContainer: const Color(0xFFE6E6E3),
    onSecondaryContainer: toongInk,
    surface: toongCanvas,
    error: toongDanger,
  ),
  scaffoldBackgroundColor: toongCanvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: toongCanvas,
    foregroundColor: toongInk,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  cardTheme: const CardThemeData(
    color: toongCanvas,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: toongLine),
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: toongInk,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: toongInk,
      side: const BorderSide(color: toongInk, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: toongInk),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: toongInk,
    foregroundColor: Colors.white,
  ),
  // 화면 전환: 오른쪽에서 살짝 밀려오며 나타난다. iOS는 밀어서 뒤로 가기를 그대로 쓴다.
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: SoftSlideTransitions(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: toongInk,
    linearTrackColor: toongSoft,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: toongLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: toongInk, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);
