import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/scheda.dart';
import '../services/api_esercizi.dart'; 
import '../services/dizionario_esercizi.dart';

class AiService {
  static const String _aiProxyBaseUrl = String.fromEnvironment('AI_PROXY_BASE_URL', defaultValue: '');

  static final RegExp _separatori = RegExp(r'[^a-z0-9àèéìòù]');
  static const Set<String> _stopWords = {
    'con', 'al', 'allo', 'alla', 'ai', 'agli', 'alle', 'a', 'da', 'di', 'del', 'della', 'dello',
    'dei', 'degli', 'delle', 'in', 'su', 'per', 'ed', 'e', 'the', 'of',
  };

  static String _normalizza(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
    return replaced.replaceAll(_separatori, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Set<String> _tokenizza(String input) {
    return _normalizza(input)
        .split(' ')
        .where((token) => token.isNotEmpty && !_stopWords.contains(token))
        .toSet();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (j) => j);
    final current = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      current[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (int j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static double _similaritaToken(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static String _risolviNomeEsercizio(String rawName, List<String> ufficiali) {
    final input = rawName.trim();
    if (input.isEmpty) return rawName;

    final normalizedInput = _normalizza(input);

    for (final nome in ufficiali) {
      if (_normalizza(nome) == normalizedInput) return nome;
    }

    final daDizionario = DizionarioEsercizi.daIngleseAItaliano[input] ??
        DizionarioEsercizi.daIngleseAItaliano.entries
            .where((e) => _normalizza(e.key) == normalizedInput || _normalizza(e.value) == normalizedInput)
            .map((e) => e.value)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    if (daDizionario != null) {
      final normalizedDict = _normalizza(daDizionario);
      for (final nome in ufficiali) {
        if (_normalizza(nome) == normalizedDict) return nome;
      }
    }

    final inputTokens = _tokenizza(input);
    String best = input;
    double bestScore = -1;

    for (final candidato in ufficiali) {
      final normCand = _normalizza(candidato);
      final candTokens = _tokenizza(candidato);

      double score = 0;

      if (normCand.contains(normalizedInput) || normalizedInput.contains(normCand)) {
        score += 0.25;
      }

      final tokenScore = _similaritaToken(inputTokens, candTokens);
      score += tokenScore * 0.45;

      final lev = _levenshtein(normalizedInput, normCand);
      final maxLen = normalizedInput.length > normCand.length ? normalizedInput.length : normCand.length;
      final levScore = maxLen == 0 ? 0 : (1 - (lev / maxLen));
      score += levScore * 0.30;

      if (score > bestScore) {
        bestScore = score;
        best = candidato;
      }
    }

    return bestScore >= 0.55 ? best : input;
  }

  static void _normalizzaEserciziJson(List<dynamic> jsonDecodificato, List<String> ufficiali) {
    for (final scheda in jsonDecodificato) {
      if (scheda is! Map<String, dynamic>) continue;
      final esercizi = scheda['esercizi'];
      if (esercizi is! List) continue;

      for (final esercizio in esercizi) {
        if (esercizio is! Map<String, dynamic>) continue;
        final nomeRaw = esercizio['nome']?.toString() ?? '';
        esercizio['nome'] = _risolviNomeEsercizio(nomeRaw, ufficiali);
      }
    }
  }

  static Future<Map<String, dynamic>?> _postProxy(String endpoint, Map<String, dynamic> payload) async {
    if (_aiProxyBaseUrl.isEmpty) {
      debugPrint('⚠️ AI_PROXY_BASE_URL non configurato.');
      return null;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ Utente non autenticato.');
      return null;
    }

    final idToken = await user.getIdToken();
    final uri = Uri.parse('$_aiProxyBaseUrl/$endpoint');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Errore proxy AI (${response.statusCode}): ${response.body}');
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }
  
  // FUNZIONE 1: ANALISI FOTO SCHEDA
  static Future<List<Scheda>?> analizzaFotoScheda(XFile foto) async {
    try {
      final imageBytes = await foto.readAsBytes();
      final database = await ApiEsercizi.ottieniEserciziTradotti();
      final List<String> nomiUfficiali = database.map((e) => e['nome'].toString()).toSet().toList();

      final risultato = await _postProxy('analyzeWorkoutPhoto', {
        'imageBase64': base64Encode(imageBytes),
        'nomiUfficiali': nomiUfficiali,
      });
      if (risultato == null) return null;

      final items = risultato['items'];
      if (items is! List) return null;

      _normalizzaEserciziJson(items, nomiUfficiali);
      return items.map((e) => Scheda.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('Errore AI Foto: $e'); 
      return null;
    }
  }

  // --- FUNZIONE 2: VALUTAZIONE SCHEDA ---
  static Future<String?> valutaCartella(String nomeCartella, List<Scheda> schede) async {
    try {
      final risultato = await _postProxy('reviewWorkoutFolder', {
        'nomeCartella': nomeCartella,
        'schede': schede.map((s) => s.toJson()).toList(),
      });
      if (risultato == null) {
        return 'Errore di connessione al servizio AI.';
      }

      final text = risultato['text']?.toString();
      if (text == null || text.trim().isEmpty) {
        return 'Errore: risposta AI non valida.';
      }
      return text;
    } catch (e) {
      debugPrint('Errore AI Valutazione: $e');
      return "Errore di connessione all'IA. Controlla la rete e riprova.";
    }
  }
}