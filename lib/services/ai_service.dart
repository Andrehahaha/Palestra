import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/scheda.dart';
import '../services/api_esercizi.dart'; 
import '../services/dizionario_esercizi.dart';
import '../services/workload_calculator.dart';

class AiProxyException implements Exception {
  final String message;
  final int? statusCode;
  final String? details;

  const AiProxyException(this.message, {this.statusCode, this.details});

  @override
  String toString() => 'AiProxyException(status: $statusCode, message: $message, details: $details)';
}

class AiService {
  static const String _aiProxyBaseUrl = String.fromEnvironment(
    'AI_PROXY_BASE_URL',
    defaultValue: '',
  );
  static String? _lastError;

  static String? consumeLastError() {
    final value = _lastError;
    _lastError = null;
    return value;
  }

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

  static double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = value.toString().replaceAll(',', '.').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  static int _toIntOrDefault(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static bool _isBigThreeLift(String name) {
    final n = _normalizza(name);
    final isPancaBilancierePresaMedia = n.contains('panca') && n.contains('bilanciere') && n.contains('presa media');
    final isSquatCompletoBilanciere = n.contains('squat') && n.contains('completo') && n.contains('bilanciere');
    return n.contains('panca piana') ||
        n.contains('bench press') ||
        isPancaBilancierePresaMedia ||
        n == 'squat' ||
        n.contains('back squat') ||
      isSquatCompletoBilanciere ||
        n.contains('stacco da terra') ||
        n.contains('deadlift');
  }

  static String _canonicalBigThreeKey(String name) {
    final n = _normalizza(name);
    final isPancaBilancierePresaMedia = n.contains('panca') && n.contains('bilanciere') && n.contains('presa media');
    final isSquatCompletoBilanciere = n.contains('squat') && n.contains('completo') && n.contains('bilanciere');
    if (n.contains('panca piana') || n.contains('bench press') || isPancaBilancierePresaMedia) return 'panca piana';
    if (n == 'squat' || n.contains('back squat') || isSquatCompletoBilanciere) return 'squat';
    if (n.contains('stacco da terra') || n.contains('deadlift')) return 'stacco da terra';
    return '';
  }

  static double? _findOneRmFromPersonalRecords(Map<String, dynamic> personalRecords, String exerciseName) {
    final canonical = _canonicalBigThreeKey(exerciseName);
    if (canonical.isEmpty) return null;

    for (final entry in personalRecords.entries) {
      final key = _normalizza(entry.key);
      final value = _toDoubleOrNull(entry.value);
      if (value == null || value <= 0) continue;

      if (key == canonical || key.contains(canonical) || canonical.contains(key)) {
        return value;
      }
    }

    return null;
  }

  static List<Map<String, dynamic>> applyPersonalRecordsFallbackForTest(
    List<Map<String, dynamic>> normalizedSchede,
    Map<String, dynamic> personalRecords,
  ) {
    return normalizedSchede.map((scheda) {
      final eserciziRaw = scheda['esercizi'];
      if (eserciziRaw is! List) return scheda;

      final esercizi = eserciziRaw.whereType<Map>().map((eRaw) {
        final e = Map<String, dynamic>.from(eRaw.cast<String, dynamic>());
        final modalita = (e['modalitaIntensita'] ?? '').toString().toLowerCase();
        if (modalita != 'percentuale') return e;

        final percentuale = _toDoubleOrNull(e['percentualeMassimale']);
        var massimale = _toDoubleOrNull(e['massimaleKg']);

        if ((massimale == null || massimale <= 0) && _isBigThreeLift((e['nome'] ?? '').toString())) {
          massimale = _findOneRmFromPersonalRecords(personalRecords, (e['nome'] ?? '').toString());
          if (massimale != null) {
            e['massimaleKg'] = massimale;
          }
        }

        if (percentuale != null && massimale != null && massimale > 0) {
          e['caricoTargetKg'] = WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: massimale,
            percentage: percentuale,
          );
        }

        return e;
      }).toList();

      return {
        ...scheda,
        'esercizi': esercizi,
      };
    }).toList();
  }

  static Future<Map<String, dynamic>> _loadPersonalRecordsFromDb() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data == null) return {};

      final pr = data['personal_records'];
      if (pr is Map<String, dynamic>) return pr;
      if (pr is Map) return Map<String, dynamic>.from(pr);
      return {};
    } catch (_) {
      return {};
    }
  }

  static double? _extractPercentFromText(String text) {
    final candidates = <RegExp>[
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*%'),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*percento', caseSensitive: false),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*per\s*cento', caseSensitive: false),
      RegExp(r'al\s*(\d{1,3}(?:[\.,]\d+)?)\b', caseSensitive: false),
      RegExp(r'at\s*(\d{1,3}(?:[\.,]\d+)?)\b', caseSensitive: false),
    ];

    for (final regex in candidates) {
      final match = regex.firstMatch(text);
      if (match == null) continue;
      final parsed = _toDoubleOrNull(match.group(1));
      if (parsed != null && parsed > 0 && parsed <= 110) {
        return parsed;
      }
    }

    return null;
  }

  static double? _extractOneRmFromText(String text) {
    final rmMatch = RegExp(
      r'(?:1\s*rm|1rm|massimale|max)\D{0,10}(\d{1,4}(?:[\.,]\d+)?)\s*kg?',
      caseSensitive: false,
    ).firstMatch(text);
    if (rmMatch != null) {
      return _toDoubleOrNull(rmMatch.group(1));
    }
    return null;
  }

  static List<Map<String, dynamic>> _normalizzaSchemaSchede(List<dynamic> rawItems) {
    return rawItems
        .whereType<Map>()
        .map((rawScheda) {
          final scheda = Map<String, dynamic>.from(rawScheda.cast<String, dynamic>());
          final rawId = scheda['id']?.toString();
          final hasStableId = rawId != null && rawId.trim().isNotEmpty;

          final eserciziRaw = scheda['esercizi'];
          final esercizi = (eserciziRaw is List ? eserciziRaw : <dynamic>[])
              .whereType<Map>()
              .map((rawEs) {
                final es = Map<String, dynamic>.from(rawEs.cast<String, dynamic>());

                final percentuale = _toDoubleOrNull(es['percentualeMassimale'] ?? es['percentuale']);
                final massimale = _toDoubleOrNull(es['massimaleKg'] ?? es['massimale']);
                final infoTestuale = [
                  es['ripetizioni'],
                  es['note'],
                  es['descrizione'],
                ].where((v) => v != null).map((v) => v.toString()).join(' ');

                final bigThree = _isBigThreeLift((es['nome'] ?? '').toString());
                final percentualeDaTesto = _extractPercentFromText(infoTestuale);
                final massimaleDaTesto = _extractOneRmFromText(infoTestuale);
                final percentualeFinale = percentuale ?? (bigThree ? percentualeDaTesto : null);
                final massimaleFinale = massimale ?? (bigThree ? massimaleDaTesto : null);

                String modalita = (es['modalitaIntensita'] ?? '').toString().trim().toLowerCase();
                if (modalita != 'rir' && modalita != 'percentuale') {
                  modalita = (percentualeFinale != null || massimaleFinale != null) ? 'percentuale' : 'rir';
                }

                final tecnicheValue = es['tecniche'];
                final metodo = es['metodo']?.toString().trim();
                final tecniche = tecnicheValue is List
                    ? tecnicheValue.map((t) => t.toString()).where((t) => t.trim().isNotEmpty).toList()
                    : (metodo != null && metodo.isNotEmpty)
                        ? <String>[metodo]
                        : <String>['Classico'];

                final rirDaInput = es['rirTarget'] ?? es['rir'] ?? es['rpe'];

                return {
                  'nome': es['nome']?.toString().trim().isNotEmpty == true ? es['nome'] : 'Esercizio',
                  'avvicinamento': _toIntOrDefault(es['avvicinamento'], 0),
                  'workingSet': _toIntOrDefault(es['workingSet'], 3),
                  'ripetizioni': (es['ripetizioni'] ?? '').toString(),
                  'recupero': (es['recupero'] ?? '').toString(),
                  'note': es['note']?.toString(),
                  'tecniche': tecniche,
                  'modalitaIntensita': modalita,
                  'rirTarget': modalita == 'rir' && rirDaInput != null
                      ? rirDaInput.toString().trim()
                      : null,
                  'percentualeMassimale': modalita == 'percentuale' ? percentualeFinale : null,
                  'massimaleKg': modalita == 'percentuale' ? massimaleFinale : null,
                  'caricoTargetKg': _toDoubleOrNull(es['caricoTargetKg']),
                  'serieAttive': es['serieAttive'] is List ? es['serieAttive'] : <dynamic>[],
                };
              })
              .toList();

          return {
            'id': hasStableId ? rawId : null,
            'nome': scheda['nome']?.toString().trim().isNotEmpty == true ? scheda['nome'] : 'Scheda Importata',
            'livello': scheda['livello']?.toString().trim().isNotEmpty == true ? scheda['livello'] : 'Intermedio',
            'categoria': scheda['categoria']?.toString().trim().isNotEmpty == true ? scheda['categoria'] : 'Importata AI',
            'continuativa': scheda['continuativa'] ?? true,
            'settimanaCorrente': hasStableId ? _toIntOrDefault(scheda['settimanaCorrente'], 1) : 1,
            'esercizi': esercizi,
          };
        })
        .toList();
  }

  // Helper pubblico per test/debug locale della normalizzazione import AI.
  static List<Map<String, dynamic>> normalizeImportedSchedeForTest(
    List<dynamic> rawItems, {
    List<String> nomiUfficiali = const [],
  }) {
    final cloned = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();

    if (nomiUfficiali.isNotEmpty) {
      _normalizzaEserciziJson(cloned, nomiUfficiali);
    }

    return _normalizzaSchemaSchede(cloned);
  }

  static Future<Map<String, dynamic>?> _postProxy(String endpoint, Map<String, dynamic> payload) async {
    if (_aiProxyBaseUrl.isEmpty) {
      throw const AiProxyException('AI proxy non configurato. Imposta AI_PROXY_BASE_URL.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AiProxyException('Utente non autenticato.', statusCode: 401);
    }

    try {
      final idToken = await user.getIdToken(true);
      final base = _aiProxyBaseUrl.endsWith('/') ? _aiProxyBaseUrl.substring(0, _aiProxyBaseUrl.length - 1) : _aiProxyBaseUrl;
      final parsedBase = Uri.tryParse(base);
      final candidates = <Uri>[];

      void addCandidate(Uri uri) {
        if (!candidates.contains(uri)) {
          candidates.add(uri);
        }
      }

      if (base.endsWith('/$endpoint')) {
        addCandidate(Uri.parse(base));
      } else {
        addCandidate(Uri.parse('$base/$endpoint'));
      }

      if (parsedBase != null && parsedBase.hasAuthority) {
        addCandidate(parsedBase.replace(path: '/$endpoint', query: null, fragment: null));
      }

      final tried = <String>[];
      for (final uri in candidates) {
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          throw const AiProxyException('Risposta proxy non valida (JSON atteso).');
        }

        String backendError = 'Errore sconosciuto';
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body['error'] != null) {
            backendError = body['error'].toString();
          } else {
            backendError = response.body;
          }
        } catch (_) {
          backendError = response.body;
        }

        tried.add('${uri.toString()} -> ${response.statusCode}');

        if (response.statusCode == 404) {
          continue;
        }

        throw AiProxyException(
          'Proxy AI errore ${response.statusCode}',
          statusCode: response.statusCode,
          details: backendError,
        );
      }

      throw AiProxyException(
        'Endpoint AI non trovato',
        statusCode: 404,
        details: 'URL provati: ${tried.join(' | ')}',
      );
    } on TimeoutException {
      throw const AiProxyException('Timeout durante la connessione al proxy AI.', statusCode: 408);
    } on SocketException {
      throw const AiProxyException('Nessuna connessione di rete verso il proxy AI.');
    }
  }

  static String _friendlyProxyError(AiProxyException e) {
    final code = e.statusCode;
    final details = e.details?.trim();

    if (code == 401 || code == 403) {
      return 'Sessione scaduta o non autorizzata. Esci e rientra nell\'app, poi riprova.';
    }
    if (code == 404) {
      if (details != null && details.isNotEmpty) {
        return 'Endpoint AI non trovato. Base URL attuale: ${_aiProxyBaseUrl.isEmpty ? '(vuoto)' : _aiProxyBaseUrl}. $details';
      }
      return 'Endpoint AI non trovato. Base URL attuale: ${_aiProxyBaseUrl.isEmpty ? '(vuoto)' : _aiProxyBaseUrl}. Verifica AI_PROXY_BASE_URL e deploy del proxy.';
    }
    if (code == 408) {
      return 'Il servizio AI non risponde in tempo. Controlla la rete e riprova.';
    }
    if (code == 429) {
      return 'Limite richieste Gemini raggiunto. Attendi qualche minuto e riprova.';
    }
    if (code != null && code >= 500) {
      return details != null && details.isNotEmpty
          ? 'Errore server AI: $details'
          : 'Errore interno del servizio AI. Riprova tra poco.';
    }

    if (details != null && details.isNotEmpty) {
      return 'Errore AI: $details';
    }
    return e.message;
  }
  
  // FUNZIONE 1: ANALISI FOTO SCHEDA
  static Future<List<Scheda>?> analizzaFotoScheda(XFile foto) async {
    try {
      _lastError = null;
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
      final compatibiliBase = _normalizzaSchemaSchede(items);
      final prDb = await _loadPersonalRecordsFromDb();
      final compatibili = applyPersonalRecordsFallbackForTest(compatibiliBase, prDb);
      return compatibili.map((e) => Scheda.fromJson(e)).toList();
    } on AiProxyException catch (e) {
      _lastError = _friendlyProxyError(e);
      debugPrint('Errore AI Foto: $e');
      return null;
    } catch (e) {
      _lastError = 'Errore imprevisto durante la connessione all\'IA.';
      debugPrint('Errore AI Foto: $e');
      return null;
    }
  }

  // --- FUNZIONE 2: VALUTAZIONE SCHEDA ---
  static Future<String?> valutaCartella(String nomeCartella, List<Scheda> schede) async {
    try {
      _lastError = null;
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
    } on AiProxyException catch (e) {
      final msg = _friendlyProxyError(e);
      _lastError = msg;
      debugPrint('Errore AI Valutazione: $e');
      return msg;
    } catch (e) {
      _lastError = "Errore di connessione all'IA. Controlla la rete e riprova.";
      debugPrint('Errore AI Valutazione: $e');
      return "Errore di connessione all'IA. Controlla la rete e riprova.";
    }
  }
}