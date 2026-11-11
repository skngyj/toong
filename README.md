# 퉁 (Toong)

친구들과 쓴 비용을 각자의 메뉴에 맞게 나누고, 여러 결제자의 금액을 상계하는 Flutter 앱입니다. [기획서](docs/product-plan.md)의 **1단계 수동 입력 첫 버전**을 구현합니다.

현재 포함된 흐름: 방 생성·코드 입장, 참여 중인 방 목록, 메뉴와 비용 수동 입력, 항목별 부담자 선택, 잔돈 부담자 직접 지정, 최종 송금 안내, 참여자의 정산 복제, 48시간 동안 입력이 없는 방 자동 삭제(삭제까지 남은 시간 표시). 영수증·메뉴판 인식과 잔돈 추첨은 후속 단계입니다. 앱 내 송금 기능은 없습니다.

## 계획 중인 기능 (미구현)

아래 내용은 기획만 정했고 아직 코드에 넣지 않았습니다. 자세한 정책은 [기획서](docs/product-plan.md) 6.1·6.8절을 따릅니다.

| 기능 | 내용 |
| --- | --- |
| 방 링크 공유로 입장 | 방 코드 입장은 그대로 유지하고, 방 링크를 복사·공유해 그 링크로 바로 입장하는 방법을 추가 |
| 미완료 방 자동 삭제 | 정산을 완료하지 않은 채 마지막 입력 후 48시간 동안 입력이 없으면 서버에서 방 삭제 |
| 방 얼리기 | 얼린 방은 삭제 시간이 멈춤. 동시에 얼릴 수 있는 방 수를 계정당 또는 기기당으로 제한 |
| 방 연장 | 남은 시간을 다시 48시간으로 되돌림. 연장 횟수 제한 |
| 정산 완료 기록 | `정산 완료` 시 그 방의 모든 거래(지출·결제자·부담자·잔돈·최종 송금)를 텍스트로 기록 |

## 실행

Flutter SDK가 설치되어 있다면:

```powershell
flutter pub get
flutter run
```

서버 정보 없이 실행하면 **체험 모드**입니다. 방과 지출은 실행 기기에만 저장되고, 같은 기기에서만 방 코드 입장이 가능합니다. 앱 삭제·데이터 초기화 시 저장 내용이 사라질 수 있습니다. 친구의 다른 기기와 연결하려면 아래 Supabase 설정이 필요합니다.

## 친구 기기와 연결하기

1. Supabase 프로젝트를 만들고 **Anonymous Sign-Ins**를 활성화합니다.
2. SQL Editor에서 [`supabase/migrations/202610020001_first_version.sql`](supabase/migrations/202610020001_first_version.sql), [`supabase/migrations/202611080001_room_expiry.sql`](supabase/migrations/202611080001_room_expiry.sql)을 순서대로 실행합니다. 두 번째 파일은 `pg_cron` 확장을 켜고 기한이 지난 방을 1시간마다 지우는 작업을 등록합니다. 확장 생성 권한 오류가 나면 Dashboard > Database > Extensions에서 `pg_cron`을 먼저 켠 뒤 다시 실행합니다.
3. 프로젝트 URL과 **publishable key**를 아래처럼 빌드 인자로 넘깁니다.

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

실제 키 값은 저장소에 기록하지 마세요. `service_role` 키나 secret key를 앱에 넣으면 안 됩니다. 방 코드로 다른 기기에서 참여하려면 양쪽 앱이 **같은 Supabase 프로젝트**에 연결되어 있어야 합니다. Supabase 설정을 하지 않은 체험 모드의 데이터는 서버로 자동 이전되지 않습니다.

서버에서는 익명 인증 사용자에게만 방 생성·참여 함수를 허용하고, 방 데이터 조회를 실제 참여자에게 제한합니다. 방장만 지출·잔돈 부담자를 수정하며, 다른 참여자도 읽을 수 있는 원본 방을 복제해 새 방장이 될 수 있습니다. 복제본의 미연결 과거 참여자 금액은 유지됩니다.

## 확인

```powershell
dart analyze lib test
flutter test
```

Android 실행·APK 빌드에는 Android SDK가 필요합니다. 이 저장소에는 Android와 iOS 프로젝트가 생성되어 있지만, iOS 빌드에는 macOS/Xcode가 필요합니다. 앱 식별자와 아이콘은 배포 전에 정해야 합니다.

Supabase 익명 인증은 로그인 화면 없이 사용자별 세션을 발급합니다. 게스트가 앱을 삭제하거나 기기를 바꾸면 이전 세션으로 다시 로그인할 수 없습니다. 앱은 방 생성·입장 전에 이 점을 안내합니다.
