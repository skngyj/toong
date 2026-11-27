/// 송금받을 계좌와 은행·송금 앱 목록.
library;

/// 계좌를 만들 수 있는 은행. [code]는 서버(set_toong_account)가 받는 값과 같다.
typedef Bank = ({String code, String name});

const banks = <Bank>[
  (code: 'kb', name: 'KB국민은행'),
  (code: 'shinhan', name: '신한은행'),
  (code: 'woori', name: '우리은행'),
  (code: 'hana', name: '하나은행'),
  (code: 'nh', name: 'NH농협은행'),
  (code: 'nhlocal', name: '지역농·축협'),
  (code: 'ibk', name: 'IBK기업은행'),
  (code: 'kakao', name: '카카오뱅크'),
  (code: 'toss', name: '토스뱅크'),
  (code: 'kbank', name: '케이뱅크'),
  (code: 'sc', name: 'SC제일은행'),
  (code: 'citi', name: '한국씨티은행'),
  (code: 'suhyup', name: 'Sh수협은행'),
  (code: 'mg', name: '새마을금고'),
  (code: 'cu', name: '신협'),
  (code: 'epost', name: '우체국'),
  (code: 'busan', name: 'BNK부산은행'),
  (code: 'kyongnam', name: 'BNK경남은행'),
  (code: 'im', name: 'iM뱅크(대구)'),
  (code: 'kj', name: '광주은행'),
  (code: 'jb', name: '전북은행'),
  (code: 'jeju', name: '제주은행'),
  (code: 'kdb', name: 'KDB산업은행'),
  (code: 'sanlim', name: '산림조합'),
  (code: 'savings', name: '저축은행'),
];

/// 은행 코드로 이름을 찾는다. 모르는 코드면 코드를 그대로 쓴다.
String bankName(String code) =>
    banks.where((b) => b.code == code).firstOrNull?.name ?? code;

/// 송금에 쓸 수 있는 앱. [package]는 Android 앱 ID다.
/// 앱이 없거나 ID가 다르면 Play 스토어에서 [name]으로 검색한다.
typedef BankApp = ({String name, String package});

const bankApps = <BankApp>[
  (name: '토스', package: 'com.viva.republica.toss'),
  (name: '카카오뱅크', package: 'com.kakaobank.channel'),
  (name: '케이뱅크', package: 'com.kbankwith.smartbank'),
  (name: 'KB스타뱅킹', package: 'com.kbstar.kbbank'),
  (name: '신한 SOL뱅크', package: 'com.shinhan.sbanking'),
  (name: '우리WON뱅킹', package: 'com.wooribank.smart.npib'),
  (name: '하나원큐', package: 'com.kebhana.hanapush'),
  (name: 'NH올원뱅크', package: 'com.nonghyup.nhallonebank'),
  (name: 'NH스마트뱅킹', package: 'nh.smart.banking'),
  (name: 'IBK기업은행', package: 'com.ibk.android.ionebank'),
  (name: '카카오페이', package: 'com.kakaopay.app'),
  (name: '네이버페이', package: 'com.naverfin.payapp'),
  (name: 'SC제일은행', package: 'com.scbank.ma30'),
  (name: '새마을금고', package: 'com.smg.spbs'),
  (name: '신협', package: 'kr.co.cu.onbank'),
  (name: '우체국뱅킹', package: 'com.epost.psf.sdsi'),
  (name: 'Sh수협은행', package: 'com.suhyup.pesmb'),
  (name: 'BNK부산은행', package: 'kr.co.busanbank.mbp'),
  (name: 'BNK경남은행', package: 'com.knb.psb'),
  (name: 'iM뱅크', package: 'kr.co.dgb.dgbm'),
  (name: '광주은행', package: 'com.kjbank.asb.pbanking'),
  (name: '전북은행', package: 'com.jbbank.mbanking'),
  (name: 'KDB산업은행', package: 'com.kdb.mobilebank'),
];

/// 계좌번호 형식: 숫자와 하이픈, 숫자는 8~20자리. 서버와 같은 규칙.
bool isValidAccountNumber(String value) {
  final text = value.trim();
  final digits = text.replaceAll('-', '');
  return RegExp(r'^[0-9-]{8,24}$').hasMatch(text) &&
      digits.length >= 8 &&
      digits.length <= 20;
}

class BankAccount {
  const BankAccount({
    required this.bank,
    required this.number,
    required this.holder,
  });

  /// 은행 코드([banks]의 code).
  final String bank;
  final String number;
  final String holder;

  String get bankLabel => bankName(bank);

  /// "카카오뱅크 3333-01-1234567 김지수"
  String get label => '$bankLabel $number $holder';

  /// 은행 앱이 알아보기 쉽게 복사하는 글: "카카오뱅크 3333011234567".
  String get copyText => '$bankLabel ${number.replaceAll('-', '')}';

  Map<String, dynamic> toJson() => {
    'bank': bank,
    'number': number,
    'holder': holder,
  };

  /// 모양이 이상하면 null.
  static BankAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final bank = raw['bank'], number = raw['number'], holder = raw['holder'];
    if (bank is! String || number is! String || holder is! String) return null;
    return BankAccount(bank: bank, number: number, holder: holder);
  }

  @override
  bool operator ==(Object other) =>
      other is BankAccount &&
      other.bank == bank &&
      other.number == number &&
      other.holder == holder;

  @override
  int get hashCode => Object.hash(bank, number, holder);
}
