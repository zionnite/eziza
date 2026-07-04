import 'package:supabase_flutter/supabase_flutter.dart';

class Bank {
  final String name;
  final String code;
  const Bank({required this.name, required this.code});

  @override
  bool operator ==(Object other) => other is Bank && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class BankService {
  // Session-level cache — survives re-renders, cleared on app restart
  static List<Bank>? _cache;

  static Future<List<Bank>> fetchBanks() async {
    if (_cache != null) return _cache!;

    try {
      final res = await Supabase.instance.client.functions
          .invoke('list-banks', method: HttpMethod.get);

      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['banks'] == null) return _fallback;

      _cache = (data['banks'] as List)
          .map((b) => Bank(
                name: b['name'] as String,
                code: b['code'] as String,
              ))
          .toList();

      return _cache!;
    } catch (_) {
      return _fallback;
    }
  }

  static void clearCache() => _cache = null;

  // Fallback used when the edge function is unreachable
  static const _fallback = [
    Bank(name: 'Access Bank', code: '044'),
    Bank(name: 'Citibank', code: '023'),
    Bank(name: 'Ecobank', code: '050'),
    Bank(name: 'Fidelity Bank', code: '070'),
    Bank(name: 'First Bank', code: '011'),
    Bank(name: 'FCMB', code: '214'),
    Bank(name: 'GTBank', code: '058'),
    Bank(name: 'Heritage Bank', code: '030'),
    Bank(name: 'Keystone Bank', code: '082'),
    Bank(name: 'Kuda Bank', code: '090267'),
    Bank(name: 'Moniepoint', code: '090405'),
    Bank(name: 'Opay', code: '999992'),
    Bank(name: 'Palmpay', code: '999991'),
    Bank(name: 'Polaris Bank', code: '076'),
    Bank(name: 'Providus Bank', code: '101'),
    Bank(name: 'Stanbic IBTC', code: '039'),
    Bank(name: 'Sterling Bank', code: '232'),
    Bank(name: 'UBA', code: '033'),
    Bank(name: 'Union Bank', code: '032'),
    Bank(name: 'Unity Bank', code: '215'),
    Bank(name: 'Wema Bank', code: '035'),
    Bank(name: 'Zenith Bank', code: '057'),
  ];
}
