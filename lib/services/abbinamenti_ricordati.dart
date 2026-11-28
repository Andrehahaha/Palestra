import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Nomi corretti a mano dopo un import: "nome nel documento" -> "nome
/// nell'app". Al prossimo import valgono prima dell'AI.
abstract final class AbbinamentiRicordati {
  static const _chiave = 'abbinamenti_nomi_v1';

  /// Chiave del nome del documento: senza maiuscole e spazi in più.
  static String chiave(String originale) => originale.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Future<Map<String, String>> carica() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chiave);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<void> ricorda(Map<String, String> scelte) async {
    if (scelte.isEmpty) return;
    final tutti = await carica();
    for (final e in scelte.entries) {
      tutti[chiave(e.key)] = e.value;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chiave, jsonEncode(tutti));
  }
}
