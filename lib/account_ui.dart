import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/bank.dart';
import 'theme.dart';

/// 이 기기에 저장한 내 계좌. 다음 방을 만들거나 들어갈 때 자동으로 채운다.
class MyAccountStore {
  static const _key = 'toong_my_account';

  Future<BankAccount?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? null : BankAccount.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(BankAccount? account) async {
    final prefs = await SharedPreferences.getInstance();
    if (account == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(account.toJson()));
    }
  }
}

/// 은행·계좌번호·예금주 입력 칸. [controller]로 값을 읽고 채운다.
class AccountFields extends StatefulWidget {
  const AccountFields({super.key, required this.controller});
  final AccountController controller;
  @override
  State<AccountFields> createState() => _AccountFieldsState();
}

/// [AccountFields]의 값. 모두 비었으면 [isEmpty].
class AccountController {
  AccountController([BankAccount? initial])
    : bank = initial?.bank,
      number = TextEditingController(text: initial?.number),
      holder = TextEditingController(text: initial?.holder);
  String? bank;
  final TextEditingController number;
  final TextEditingController holder;

  bool get isEmpty =>
      bank == null && number.text.trim().isEmpty && holder.text.trim().isEmpty;

  /// 입력이 맞으면 계좌, 아니면 이유를 담은 [StateError]를 던진다.
  BankAccount read() {
    final holderText = holder.text.trim();
    if (bank == null) throw StateError('은행을 골라주세요.');
    if (!isValidAccountNumber(number.text)) {
      throw StateError('계좌번호는 숫자 8~20자리로 입력해주세요. 하이픈(-)은 넣어도 돼요.');
    }
    if (holderText.isEmpty || holderText.length > 20) {
      throw StateError('예금주를 20자 이내로 입력해주세요.');
    }
    return BankAccount(
      bank: bank!,
      number: number.text.trim(),
      holder: holderText,
    );
  }

  void fill(BankAccount account) {
    bank = account.bank;
    number.text = account.number;
    holder.text = account.holder;
  }

  void dispose() {
    number.dispose();
    holder.dispose();
  }
}

class _AccountFieldsState extends State<AccountFields> {
  AccountController get c => widget.controller;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        initialValue: c.bank,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '은행'),
        items: [
          for (final b in banks)
            DropdownMenuItem(value: b.code, child: Text(b.name)),
        ],
        onChanged: (value) => setState(() => c.bank = value),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: c.number,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
          LengthLimitingTextInputFormatter(24),
        ],
        decoration: const InputDecoration(
          labelText: '계좌번호',
          hintText: '숫자만 또는 하이픈(-) 포함',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: c.holder,
        maxLength: 20,
        decoration: const InputDecoration(labelText: '예금주'),
      ),
    ],
  );
}

/// 계좌 입력 창의 결과. 지우기를 누르면 [account]가 null이다. 취소하면 창 자체가 null을 돌려준다.
typedef AccountEdit = ({BankAccount? account});

/// 계좌를 등록·수정하는 창.
Future<AccountEdit?> showAccountDialog(
  BuildContext context, {
  required String title,
  BankAccount? initial,
  String? help,
}) => showDialog<AccountEdit>(
  context: context,
  builder: (_) => _AccountDialog(title: title, initial: initial, help: help),
);

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.title, this.initial, this.help});
  final String title;
  final BankAccount? initial;
  final String? help;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final controller = AccountController(widget.initial);
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    try {
      Navigator.pop<AccountEdit>(context, (account: controller.read()));
    } on StateError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.help != null) ...[
            Text(
              widget.help!,
              style: const TextStyle(fontSize: 13, color: toongSub),
            ),
            const SizedBox(height: 12),
          ],
          AccountFields(controller: controller),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(color: toongDanger, fontSize: 13),
            ),
          if (widget.initial != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    Navigator.pop<AccountEdit>(context, (account: null)),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('계좌 지우기'),
              ),
            ),
        ],
      ),
    ),
    actions: [
      Row(
        children: [
          Expanded(
            child: FilledButton(onPressed: submit, child: const Text('확인')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: toongDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 은행 앱을 연다. 결과: 'opened'(앱을 열었음), 'store'(Play 스토어 검색을 열었음), 'none'.
/// 위젯 테스트에서 바꿔 끼울 수 있게 변수로 둔다.
Future<String> Function(BankApp app) openBankApp = _openWithChannel;

const _bankChannel = MethodChannel('toong/bank_app');

Future<String> _openWithChannel(BankApp app) async {
  try {
    return await _bankChannel.invokeMethod<String>('open', {
          'package': app.package,
          'name': app.name,
        }) ??
        'none';
  } on MissingPluginException {
    return 'none';
  } on PlatformException {
    return 'none';
  }
}

/// 송금 창. 받는 사람 계좌와 금액을 보여주고, 은행 앱을 고르면 계좌를 복사한 뒤 그 앱을 연다.
/// 은행 앱을 열었으면 true를 돌려준다(돌아왔을 때 송금 완료를 물어보기 위해).
Future<bool> showSendSheet(
  BuildContext context, {
  required String to,
  required int amount,
  required String amountText,
  required BankAccount account,
}) async {
  final opened = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: toongCanvas,
    builder: (context) => _SendSheet(
      to: to,
      amount: amount,
      amountText: amountText,
      account: account,
    ),
  );
  return opened ?? false;
}

class _SendSheet extends StatelessWidget {
  const _SendSheet({
    required this.to,
    required this.amount,
    required this.amountText,
    required this.account,
  });
  final String to;
  final int amount;
  final String amountText;
  final BankAccount account;

  Future<void> copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$what을 복사했어요.')));
    }
  }

  Future<void> open(BuildContext context, BankApp app) async {
    await Clipboard.setData(ClipboardData(text: account.copyText));
    final result = await openBankApp(app);
    if (!context.mounted) return;
    if (result == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${app.name} 앱을 열 수 없어요. 계좌는 복사해 뒀어요.')),
      );
      return;
    }
    Navigator.pop(context, result == 'opened');
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$to 님에게 $amountText 보내기',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: toongSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.bankLabel,
                    style: const TextStyle(color: toongSub),
                  ),
                  Text(
                    account.number,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text('예금주 ${account.holder}'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              copy(context, account.copyText, '계좌번호'),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('계좌 복사'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => copy(context, '$amount', '금액'),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('금액 복사'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '송금할 앱을 고르세요',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              '계좌번호를 복사한 뒤 앱을 열어요. 앱에서 붙여넣거나, 앱이 복사한 계좌를 알아서 띄워 줄 거예요. '
              '앱이 없으면 Play 스토어에서 찾아줘요.',
              style: TextStyle(fontSize: 12.5, color: toongSub),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final app in bankApps)
                  ActionChip(
                    avatar: const Icon(Icons.account_balance, size: 16),
                    label: Text(app.name),
                    onPressed: () => open(context, app),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
