import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/ai_structured_plan.dart';
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
  String toString() =>
      'AiProxyException(status: $statusCode, message: $message, details: $details)';
}

class AiImportWeeklyResolution {
  final List<Scheda> schedeVisibili;
  final Map<String, Map<String, dynamic>> weekHistoryStoreEntries;

  const AiImportWeeklyResolution({
    required this.schedeVisibili,
    required this.weekHistoryStoreEntries,
  });
}

class AiService {
  static const String _defaultWorkerProxyBaseUrl =
      'https://tiger-ai-proxy.andreapalestra03.workers.dev';
  static const String _defaultFirebaseProxyBaseUrl =
      'https://europe-west1-palestrai-5856f.cloudfunctions.net';

  static const String _aiProxyBaseUrl = String.fromEnvironment(
    'AI_PROXY_BASE_URL',
    defaultValue: _defaultWorkerProxyBaseUrl,
  );
  static const String _aiProxyFallbackBaseUrl = String.fromEnvironment(
    'AI_PROXY_FALLBACK_BASE_URL',
    defaultValue: '',
  );
  static String? _lastError;
  static AiStructuredPlan? _lastStructuredPlan;
  static Map<String, dynamic>? _lastDebugJson;

  static String? consumeLastError() {
    final value = _lastError;
    _lastError = null;
    return value;
  }

  static AiStructuredPlan? consumeLastStructuredPlan() {
    final value = _lastStructuredPlan;
    _lastStructuredPlan = null;
    return value;
  }

  static Map<String, dynamic>? consumeLastDebugJson() {
    final value = _lastDebugJson;
    _lastDebugJson = null;
    return value;
  }

  static void _captureStructuredPlan(Map<String, dynamic> responsePayload) {
    final raw = responsePayload['structuredPlan'];
    if (raw is Map<String, dynamic>) {
      try {
        _lastStructuredPlan = AiStructuredPlan.fromJson(raw);
      } catch (_) {
        _lastStructuredPlan = null;
      }
      return;
    }

    if (raw is Map) {
      try {
        _lastStructuredPlan = AiStructuredPlan.fromJson(
          Map<String, dynamic>.from(raw),
        );
      } catch (_) {
        _lastStructuredPlan = null;
      }
      return;
    }

    _lastStructuredPlan = null;
  }

  static String _truncateForDebug(String value, {int max = 6000}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...';
  }

  static void _logJsonReadDebug(String sourceLabel, dynamic debugPayload) {
    if (!kDebugMode || debugPayload == null) return;
    try {
      final encoded = jsonEncode(debugPayload);
      debugPrint(
        'AI JSON READ DEBUG [$sourceLabel] ${_truncateForDebug(encoded)}',
      );
    } catch (_) {
      debugPrint(
        'AI JSON READ DEBUG [$sourceLabel] payload non serializzabile',
      );
    }
  }

  static final RegExp _separatori = RegExp(r'[^a-z0-9àèéìòù]');
  static const Set<String> _stopWords = {
    'con',
    'al',
    'allo',
    'alla',
    'ai',
    'agli',
    'alle',
    'a',
    'da',
    'di',
    'del',
    'della',
    'dello',
    'dei',
    'degli',
    'delle',
    'in',
    'su',
    'per',
    'ed',
    'e',
    'the',
    'of',
  };

  static final RegExp _weekSuffixNamePattern = RegExp(
    r'\s*(?:[-|:]\s*)?(?:w|week|settimana)\s*[-_ ]*\d+\b.*$',
    caseSensitive: false,
  );

  static final RegExp _weekPrefixNamePattern = RegExp(
    r'^\s*(?:w|week|settimana)\s*[-_ ]*\d+\s*(?:[-|:]\s*)?',
    caseSensitive: false,
  );

  static String _normalizza(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
    return replaced
        .replaceAll(_separatori, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

    final daDizionario =
        DizionarioEsercizi.daIngleseAItaliano[input] ??
        DizionarioEsercizi.daIngleseAItaliano.entries
            .where(
              (e) =>
                  _normalizza(e.key) == normalizedInput ||
                  _normalizza(e.value) == normalizedInput,
            )
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

      if (normCand.contains(normalizedInput) ||
          normalizedInput.contains(normCand)) {
        score += 0.25;
      }

      final tokenScore = _similaritaToken(inputTokens, candTokens);
      score += tokenScore * 0.45;

      final lev = _levenshtein(normalizedInput, normCand);
      final maxLen = normalizedInput.length > normCand.length
          ? normalizedInput.length
          : normCand.length;
      final levScore = maxLen == 0 ? 0 : (1 - (lev / maxLen));
      score += levScore * 0.30;

      if (score > bestScore) {
        bestScore = score;
        best = candidato;
      }
    }

    return bestScore >= 0.55 ? best : input;
  }

  static void _normalizzaEserciziJson(
    List<dynamic> jsonDecodificato,
    List<String> ufficiali,
  ) {
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

  static int _parseWeekOrDefault(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value > 0 ? value : fallback;
    if (value is num) {
      final parsed = value.toInt();
      return parsed > 0 ? parsed : fallback;
    }

    final text = value.toString().trim();
    if (text.isEmpty) return fallback;

    final direct = int.tryParse(text);
    if (direct != null && direct > 0) return direct;

    final lower = text.toLowerCase();
    final patterns = <RegExp>[
      RegExp(
        r'(?:\bweek\b|\bsettimana\b)\s*[:#\-]?\s*(\d{1,2})',
        caseSensitive: false,
      ),
      RegExp(r'\bw\s*(\d{1,2})\b', caseSensitive: false),
      RegExp(r'(\d{1,2})\s*(?:\bweek\b|\bsettimana\b)', caseSensitive: false),
    ];

    RegExpMatch? match;
    for (final pattern in patterns) {
      match = pattern.firstMatch(lower);
      if (match != null) break;
    }

    if (match?.group(1) != null) {
      final parsed = int.tryParse(match!.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    return fallback;
  }

  static int _resolveWeekNumber({
    dynamic rawWeek,
    String? categoria,
    String? nome,
  }) {
    final fromRaw = _parseWeekOrDefault(rawWeek, -1);
    if (fromRaw > 0) return fromRaw;

    final fromCategoria = _parseWeekOrDefault(categoria, -1);
    if (fromCategoria > 0) return fromCategoria;

    final fromNome = _parseWeekOrDefault(nome, -1);
    if (fromNome > 0) return fromNome;

    return 1;
  }

  static bool _isBigThreeLift(String name) {
    final n = _normalizza(name);
    final isPancaBilancierePresaMedia =
        n.contains('panca') &&
        n.contains('bilanciere') &&
        n.contains('presa media');
    final isSquatCompletoBilanciere =
        n.contains('squat') &&
        n.contains('completo') &&
        n.contains('bilanciere');
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
    final isPancaBilancierePresaMedia =
        n.contains('panca') &&
        n.contains('bilanciere') &&
        n.contains('presa media');
    final isSquatCompletoBilanciere =
        n.contains('squat') &&
        n.contains('completo') &&
        n.contains('bilanciere');
    if (n.contains('panca piana') ||
        n.contains('bench press') ||
        isPancaBilancierePresaMedia) {
      return 'panca piana';
    }
    if (n == 'squat' || n.contains('back squat') || isSquatCompletoBilanciere) {
      return 'squat';
    }
    if (n.contains('stacco da terra') || n.contains('deadlift')) {
      return 'stacco da terra';
    }
    return '';
  }

  static double? _findOneRmFromPersonalRecords(
    Map<String, dynamic> personalRecords,
    String exerciseName,
  ) {
    final canonical = _canonicalBigThreeKey(exerciseName);
    if (canonical.isEmpty) return null;

    for (final entry in personalRecords.entries) {
      final key = _normalizza(entry.key);
      final value = _toDoubleOrNull(entry.value);
      if (value == null || value <= 0) continue;

      if (key == canonical ||
          key.contains(canonical) ||
          canonical.contains(key)) {
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
        final modalita = (e['modalitaIntensita'] ?? '')
            .toString()
            .toLowerCase();
        if (modalita != 'percentuale') return e;

        final percentuale = _toDoubleOrNull(e['percentualeMassimale']);
        var massimale = _toDoubleOrNull(e['massimaleKg']);

        if ((massimale == null || massimale <= 0) &&
            _isBigThreeLift((e['nome'] ?? '').toString())) {
          massimale = _findOneRmFromPersonalRecords(
            personalRecords,
            (e['nome'] ?? '').toString(),
          );
          if (massimale != null) {
            e['massimaleKg'] = massimale;
          }
        }

        if (percentuale != null && massimale != null && massimale > 0) {
          e['caricoTargetKg'] =
              WorkloadCalculator.calculateFromMaxAndPercentage(
                oneRepMax: massimale,
                percentage: percentuale,
              );
        }

        return e;
      }).toList();

      return {...scheda, 'esercizi': esercizi};
    }).toList();
  }

  static Future<Map<String, dynamic>> _loadPersonalRecordsFromDb() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
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

  static int? _toPositiveIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final parsed = value.toInt();
      return parsed > 0 ? parsed : null;
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final direct = int.tryParse(raw);
    if (direct != null && direct > 0) return direct;

    return null;
  }

  static int? _firstPositiveInt(List<dynamic> values) {
    for (final value in values) {
      final parsed = _toPositiveIntOrNull(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int? _extractSetCountFromText(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return null;

    final patterns = <RegExp>[
      RegExp(r'\b(\d{1,2})\s*[x×]\s*\d{1,3}\b'),
      RegExp(r'\b(\d{1,2})\s*(?:set|sets|serie)\b'),
      RegExp(r'(?:set|sets|serie)\s*[:=\-]?\s*(\d{1,2})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match?.group(1) == null) continue;
      final parsed = int.tryParse(match!.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    return null;
  }

  static ({int? sets, String? reps}) _extractSetRepFromText(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return (sets: null, reps: null);

    final patterns = <RegExp>[
      RegExp(r'\b(\d{1,2})\s*[x×]\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)\b'),
      RegExp(
        r'\b(\d{1,2})\s*(?:set|sets|serie)\s*(?:x|da)?\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)\b',
      ),
      RegExp(
        r'(?:set|sets|serie)\s*[:=\-]?\s*(\d{1,2})\D{0,10}(?:reps?|rip(?:etizioni)?|x)\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final sets = int.tryParse(match.group(1) ?? '');
      final repsRaw = (match.group(2) ?? '').trim();
      final reps = repsRaw.isEmpty
          ? null
          : repsRaw.replaceAll(RegExp(r'\s+'), '');

      if ((sets != null && sets > 0) || (reps != null && reps.isNotEmpty)) {
        return (sets: (sets != null && sets > 0) ? sets : null, reps: reps);
      }
    }

    return (sets: null, reps: null);
  }

  static bool _looksDefaultSingleRep(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return compact == '1' ||
        compact == '1rep' ||
        compact == '1reps' ||
        compact == 'x1' ||
        compact == '1x1';
  }

  static bool _isSimpleRepText(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^\d{1,3}(?:[-/]\d{1,3})?$').hasMatch(compact);
  }

  static String _bumpRepValue(String value, int offset) {
    final text = value.trim();
    if (text.isEmpty || offset <= 0) return text;

    final rangeMatch = RegExp(
      r'^(\d{1,3})\s*[-/]\s*(\d{1,3})$',
    ).firstMatch(text);
    if (rangeMatch != null) {
      final low = int.tryParse(rangeMatch.group(1) ?? '');
      final high = int.tryParse(rangeMatch.group(2) ?? '');
      if (low != null && high != null) {
        return '${low + offset}-${high + offset}';
      }
      return text;
    }

    final single = int.tryParse(text);
    if (single != null) {
      return (single + offset).toString();
    }

    return text;
  }

  static double _roundToHalf(double value) {
    return (value * 2).roundToDouble() / 2;
  }

  static String _compactNumberString(double value, {int fractionDigits = 1}) {
    final fixed = value.toStringAsFixed(fractionDigits);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  static void _applyWeekOffsetToExerciseMap(
    Map<String, dynamic> exercise,
    int weekOffset,
  ) {
    if (weekOffset <= 0) return;

    var progressedByLoad = false;

    final carico = _toDoubleOrNull(exercise['caricoTargetKg']);
    if (carico != null && carico > 0) {
      exercise['caricoTargetKg'] = _roundToHalf(carico * (1 + 0.025 * weekOffset));
      progressedByLoad = true;
    }

    var modalita = (exercise['modalitaIntensita'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
    if (modalita != 'percentuale' && modalita != 'rir') {
      final hasPercentSignal =
        _toDoubleOrNull(exercise['percentualeMassimale']) != null;
      modalita = hasPercentSignal ? 'percentuale' : 'rir';
    }
    if (modalita == 'percentuale') {
      final percentuale = _toDoubleOrNull(exercise['percentualeMassimale']);
      if (percentuale != null && percentuale > 0) {
        final bumped = percentuale + (2.5 * weekOffset);
        exercise['percentualeMassimale'] =
            double.parse(bumped.toStringAsFixed(1));
        progressedByLoad = true;
      }
    }

    if (modalita == 'rir') {
      final rirBase = _toDoubleOrNull(exercise['rirTarget']);
      if (rirBase != null && rirBase >= 0) {
        final evolvedRir = (rirBase - (0.5 * weekOffset)).clamp(0.0, 10.0)
            .toDouble();
        exercise['rirTarget'] = _compactNumberString(evolvedRir);
      }
    }

    final serieAttive = exercise['serieAttive'];
    if (!progressedByLoad && serieAttive is List) {
      for (final rawRow in serieAttive) {
        if (rawRow is! Map) continue;

        final row = rawRow is Map<String, dynamic>
            ? rawRow
            : Map<String, dynamic>.from(rawRow);
        final tipo = (row['tipo'] ?? '').toString().toLowerCase();
        if (tipo.contains('avvicin')) continue;

        final rowLoad = _toDoubleOrNull(row['peso']);
        if (rowLoad != null && rowLoad > 0) {
          progressedByLoad = true;
          break;
        }
      }
    }

    // Keep progression visible also in set x reps text across generated weeks.
    final repsRaw =
        (exercise['ripetizioni'] ?? exercise['reps'] ?? exercise['rep'] ?? '')
            .toString();
    final bumpedReps = _bumpRepValue(repsRaw, weekOffset);
    if (bumpedReps.isNotEmpty && bumpedReps != repsRaw.trim()) {
      exercise['ripetizioni'] = bumpedReps;
    }

    if (!progressedByLoad) {
      // No explicit load signal: reps progression is already applied above.
    }

    if (serieAttive is! List) return;

    for (var i = 0; i < serieAttive.length; i += 1) {
      final rawRow = serieAttive[i];
      if (rawRow is! Map) continue;

      final row = rawRow is Map<String, dynamic>
          ? rawRow
          : Map<String, dynamic>.from(rawRow);
      if (rawRow is! Map<String, dynamic>) {
        serieAttive[i] = row;
      }

      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      if (tipo.contains('avvicin')) continue;

      if (progressedByLoad) {
        final rowLoad = _toDoubleOrNull(row['peso']);
        if (rowLoad != null && rowLoad > 0) {
          final bumpedLoad = _roundToHalf(rowLoad * (1 + 0.025 * weekOffset));
          row['peso'] = _compactNumberString(bumpedLoad);
        }

        if (modalita == 'percentuale') {
          final rowPercent = _toDoubleOrNull(row['percentualeTarget']);
          final exercisePercent = _toDoubleOrNull(
            exercise['percentualeMassimale'],
          );

          if (rowPercent != null && rowPercent > 0) {
            row['percentualeTarget'] = _compactNumberString(
              rowPercent + (2.5 * weekOffset),
            );
          } else if (exercisePercent != null && exercisePercent > 0) {
            row['percentualeTarget'] = _compactNumberString(exercisePercent);
          }
        }
      } else {
        final repsDone = (row['ripetizioniFatte'] ?? '').toString().trim();
        if (repsDone.isNotEmpty) {
          row['ripetizioniFatte'] = _bumpRepValue(repsDone, weekOffset);
        }
      }

      if (modalita == 'rir') {
        final evolvedRir = _toDoubleOrNull(exercise['rirTarget']);
        if (evolvedRir != null) {
          final evolvedRpe = (10.0 - evolvedRir).clamp(0.0, 10.0).toDouble();
          row['rpe'] = _compactNumberString(evolvedRpe);
        }
      }
    }
  }

  static void _applyWeekOffsetToSchedaMap(
    Map<String, dynamic> scheda,
    int weekOffset,
  ) {
    if (weekOffset <= 0) return;

    final esercizi = scheda['esercizi'];
    if (esercizi is! List) return;

    for (var i = 0; i < esercizi.length; i += 1) {
      final rawExercise = esercizi[i];
      if (rawExercise is! Map) continue;

      final exercise = rawExercise is Map<String, dynamic>
          ? rawExercise
          : Map<String, dynamic>.from(rawExercise);

      if (rawExercise is! Map<String, dynamic>) {
        esercizi[i] = exercise;
      }

      _applyWeekOffsetToExerciseMap(exercise, weekOffset);
    }
  }

  static bool _hasProgressionTableHint(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return false;

    final patterns = <RegExp>[
      RegExp(r'(?:tabella|table).{0,24}(?:progress|progression)'),
      RegExp(r'(?:progress|progression).{0,24}(?:tabella|table)'),
      RegExp(r'(?:guarda|vedi|see|consulta).{0,20}(?:tabella|table)'),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) return true;
    }

    return false;
  }

  static bool _looksLikeProgressionTableLabel(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return false;

    final hasTable = RegExp(r'\b(?:tabella|table)\b').hasMatch(text);
    final hasProgress = RegExp(r'\bprogress(?:ione|ion)?\b').hasMatch(text);
    return hasTable && hasProgress;
  }

  static bool _isLikelyIntentionalSingleSet({
    required String repsRaw,
    required String fullContext,
  }) {
    if (_looksDefaultSingleRep(repsRaw)) return true;

    final lowerContext = fullContext.toLowerCase();
    return RegExp(
      r'\b(top\s*single|single|max|1\s*rm|test\s*pr|amrap)\b',
      caseSensitive: false,
    ).hasMatch(lowerContext);
  }

  static String _exerciseAnchorKey(Map<String, dynamic> exercise) {
    return (exercise['nome'] ?? '').toString().trim().toLowerCase();
  }

  static bool _isSetRepTechniqueLabel(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return false;

    final patterns = <RegExp>[
      RegExp(
        r'^\d{1,2}\s*[x×]\s*\d{1,3}(?:\s*[-/]\s*\d{1,3})?(?:\s*(?:@|al|at).*)?$',
      ),
      RegExp(r'^\d{1,2}\s*(?:set|sets|serie)\b'),
      RegExp(r'^(?:set|sets|serie)\s*[:=\-]?\s*\d{1,2}\b'),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) return true;
    }

    return false;
  }

  static List<String> _sanitizeTechniqueLabels(Iterable<String> labels) {
    final cleaned = <String>[];
    for (final raw in labels) {
      final label = raw.trim();
      if (label.isEmpty) continue;
      if (_isSetRepTechniqueLabel(label)) continue;
      final alreadyPresent = cleaned.any(
        (existing) => existing.toLowerCase() == label.toLowerCase(),
      );
      if (!alreadyPresent) cleaned.add(label);
    }
    return cleaned;
  }

  static const _tecnicheKeywords = <String, List<String>>{
    'Superset':       ['superset', 'super set', 'ss'],
    'Drop Set':       ['drop set', 'dropset', 'stripping', 'scalata'],
    'Stripping':      ['stripping'],
    'Rest Pause':     ['rest pause', 'rest-pause', 'restpause'],
    'Myo-reps':       ['myo-rep', 'myorep', 'myo rep'],
    'Giant Set':      ['giant set', 'giantset'],
    'Cluster Set':    ['cluster set', 'clusterset'],
    'Top Set':        ['top set', 'topset'],
    'Feeder Set':     ['feeder set', 'feederset'],
    'AMRAP':          ['amrap'],
    'EMOM':           ['emom'],
    'Piramidale':     ['piramidale', 'piramidale', 'pyramid'],
    'Back off':       ['back off', 'backoff', 'back-off'],
    'Negative':       ['negativa', 'negative', 'eccentrica'],
    'Isometria':      ['isometri', 'iso hold'],
    'Trisets':        ['triset', 'tri-set'],
    'Pre-stancaggio': ['pre-stanc', 'pre stanc', 'pre-exhaust'],
    'Burnouts':       ['burnout'],
    'Monopodalico':   ['monopod', 'unilateral', 'singola gamba', 'singolo braccio'],
    'Warm Up':        ['warm up', 'warmup', 'riscaldamento'],
  };

  static List<String> _extractTechniqueFromText(String text) {
    final lower = text.toLowerCase();
    final found = <String>[];
    for (final entry in _tecnicheKeywords.entries) {
      if (entry.value.any((kw) => lower.contains(kw))) {
        found.add(entry.key);
      }
    }
    return found;
  }

  static String _buildSetRepContext(
    Map<String, dynamic> exercise, {
    bool tagsOnly = false,
  }) {
    final tecnicheValue = exercise['tecniche'];
    final tecnicheText = tecnicheValue is List
        ? tecnicheValue.map((t) => t.toString()).join(' ')
        : tecnicheValue?.toString() ?? '';

    final tagsValue = exercise['tags'] ?? exercise['tag'];
    final tagsText = tagsValue is List
        ? tagsValue.map((t) => t.toString()).join(' ')
        : tagsValue?.toString() ?? '';

    final parts = <String>[
      (exercise['metodo'] ?? '').toString(),
      tecnicheText,
      tagsText,
    ];

    if (!tagsOnly) {
      parts.addAll([
        (exercise['schema'] ??
                exercise['setsReps'] ??
                exercise['sets_reps'] ??
                '')
            .toString(),
        (exercise['ripetizioni'] ?? exercise['reps'] ?? exercise['rep'] ?? '')
            .toString(),
        (exercise['note'] ?? '').toString(),
        (exercise['descrizione'] ?? '').toString(),
        (exercise['nome'] ?? '').toString(),
      ]);
    }

    return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' ');
  }

  static void _enrichSetRepFromTagsInPlace(List<Map<String, dynamic>> maps) {
    if (maps.isEmpty) return;

    final setAnchorByExerciseKey = <String, int>{};

    for (final scheda in maps) {
      final exercisesRaw = scheda['esercizi'];
      if (exercisesRaw is! List) continue;

      for (final raw in exercisesRaw) {
        if (raw is! Map) continue;
        final exercise = Map<String, dynamic>.from(raw.cast<String, dynamic>());

        final fullContext = _buildSetRepContext(exercise);
        final fullSetRep = _extractSetRepFromText(fullContext);
        final setsFromFull =
            _extractSetCountFromText(fullContext) ?? fullSetRep.sets;
        final serieRows = (exercise['serieAttive'] is List)
          ? List<dynamic>.from(exercise['serieAttive'] as List)
          : const <dynamic>[];
        final setsFromSeries = serieRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row.cast<String, dynamic>()))
          .where((row) {
            final tipo = (row['tipo'] ?? '').toString().toLowerCase();
            return !tipo.contains('avvicin');
          })
          .length;
        final currentWorking = _toPositiveIntOrNull(exercise['workingSet']);
        final candidateAnchor =
          setsFromFull ??
          (setsFromSeries > 0 ? setsFromSeries : null) ??
            ((currentWorking != null && currentWorking > 1)
                ? currentWorking
                : null);

        if (candidateAnchor != null && candidateAnchor > 1) {
          final anchorKey = _exerciseAnchorKey(exercise);
          if (anchorKey.isNotEmpty) {
            final existing = setAnchorByExerciseKey[anchorKey];
            if (existing == null || candidateAnchor > existing) {
              setAnchorByExerciseKey[anchorKey] = candidateAnchor;
            }
          }
        }
      }
    }

    for (final scheda in maps) {
      final exercisesRaw = scheda['esercizi'];
      if (exercisesRaw is! List) continue;

      for (final raw in exercisesRaw) {
        if (raw is! Map) continue;
        final exercise = Map<String, dynamic>.from(raw.cast<String, dynamic>());

        final fullContext = _buildSetRepContext(exercise);
        final fullSetRep = _extractSetRepFromText(fullContext);
        final setsFromFull =
            _extractSetCountFromText(fullContext) ?? fullSetRep.sets;
        final serieRows = (exercise['serieAttive'] is List)
          ? List<dynamic>.from(exercise['serieAttive'] as List)
          : const <dynamic>[];
        final workingSerieRows = serieRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row.cast<String, dynamic>()))
          .where((row) {
            final tipo = (row['tipo'] ?? '').toString().toLowerCase();
            return !tipo.contains('avvicin');
          })
          .toList();
        final setsFromSeries = workingSerieRows.isNotEmpty
          ? workingSerieRows.length
          : null;

        final tagsContext = _buildSetRepContext(exercise, tagsOnly: true);
        final tagsSetRep = _extractSetRepFromText(tagsContext);
        final setsFromTags =
            _extractSetCountFromText(tagsContext) ?? tagsSetRep.sets;

        final currentWorking = _toPositiveIntOrNull(exercise['workingSet']);
        final inferredWorking = setsFromTags ?? setsFromFull ?? setsFromSeries;
        final exerciseAnchor =
            setAnchorByExerciseKey[_exerciseAnchorKey(exercise)];
        final hasProgressionHint = _hasProgressionTableHint(fullContext);

        if (inferredWorking != null && inferredWorking > 0) {
          final shouldOverrideWorking =
              currentWorking == null ||
              currentWorking <= 0 ||
              currentWorking == 1 ||
              (setsFromTags != null && currentWorking != setsFromTags);

          if (shouldOverrideWorking) {
            exercise['workingSet'] = inferredWorking;
          }
        } else if (currentWorking == 1 &&
            !_isLikelyIntentionalSingleSet(
              repsRaw:
                  (exercise['ripetizioni'] ??
                          exercise['reps'] ??
                          exercise['rep'] ??
                          '')
                      .toString(),
              fullContext: fullContext,
            )) {
          if (exerciseAnchor != null && exerciseAnchor > 1) {
            exercise['workingSet'] = exerciseAnchor;
          } else if (hasProgressionHint) {
            exercise['workingSet'] = 3;
          }
        }

        final repsRaw =
            (exercise['ripetizioni'] ??
                    exercise['reps'] ??
                    exercise['rep'] ??
                    '')
                .toString();
        final repsFromSeries = workingSerieRows
          .map((row) => (row['ripetizioniFatte'] ?? '').toString().trim())
          .firstWhere((r) => r.isNotEmpty && !_looksDefaultSingleRep(r), orElse: () => '');
        final inferredReps =
          tagsSetRep.reps ??
          fullSetRep.reps ??
          (repsFromSeries.isNotEmpty ? repsFromSeries : null);

        if ((repsRaw.trim().isEmpty || _looksDefaultSingleRep(repsRaw)) &&
            inferredReps != null &&
            inferredReps.trim().isNotEmpty &&
            inferredReps != '1') {
          exercise['ripetizioni'] = inferredReps;
        }

        final repsAfterInference =
            (exercise['ripetizioni'] ??
                    exercise['reps'] ??
                    exercise['rep'] ??
                    '')
                .toString()
                .trim();
        if (_looksLikeProgressionTableLabel(repsAfterInference) ||
            (hasProgressionHint &&
                (repsAfterInference.isEmpty ||
                    _looksDefaultSingleRep(repsAfterInference)))) {
          exercise['ripetizioni'] = 'Guarda tabella progressione';
        }

        final tecnicheValue = exercise['tecniche'];
        final tecnicheInput = tecnicheValue is List
            ? tecnicheValue.map((t) => t.toString()).toList()
            : tecnicheValue is String
            ? <String>[tecnicheValue]
            : <String>[];

        var cleanedTecniche = _sanitizeTechniqueLabels(tecnicheInput);
        final metodo = (exercise['metodo'] ?? '').toString().trim();
        if (cleanedTecniche.isEmpty &&
            metodo.isNotEmpty &&
            !_isSetRepTechniqueLabel(metodo)) {
          cleanedTecniche = <String>[metodo];
        }
        if (cleanedTecniche.isEmpty) {
          cleanedTecniche = const <String>['Classico'];
        }
        exercise['tecniche'] = cleanedTecniche;

        final tagsValue = exercise['tags'];
        if (tagsValue is List) {
          exercise['tags'] = _sanitizeTechniqueLabels(
            tagsValue.map((t) => t.toString()),
          );
        } else if (tagsValue is String) {
          final cleanedTags = _sanitizeTechniqueLabels(<String>[tagsValue]);
          if (cleanedTags.isEmpty) {
            exercise.remove('tags');
          } else {
            exercise['tags'] = cleanedTags;
          }
        }

        final rawDynamic = raw as dynamic;
        for (final entry in exercise.entries) {
          rawDynamic[entry.key] = entry.value;
        }
      }
    }
  }

  static List<Map<String, dynamic>> _normalizeSerieAttiveForImport({
    required List<dynamic> rawSerieAttive,
    required int avvicinamento,
    required int workingSet,
    required String modalita,
    required double? percentualeMassimale,
  }) {
    final existing = rawSerieAttive
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s.cast<String, dynamic>()))
        .toList();

    if (existing.isEmpty) {
      // Let Esercizio.fromJson generate default rows from avvicinamento/workingSet.
      return <Map<String, dynamic>>[];
    }

    final avvExisting = <Map<String, dynamic>>[];
    final workExisting = <Map<String, dynamic>>[];

    for (final serie in existing) {
      final tipo = (serie['tipo'] ?? '').toString().toLowerCase();
      if (tipo.contains('avvicin')) {
        avvExisting.add(serie);
      } else {
        workExisting.add(serie);
      }
    }

    final normalized = <Map<String, dynamic>>[];

    for (int i = 0; i < avvicinamento; i++) {
      final source = i < avvExisting.length
          ? avvExisting[i]
          : const <String, dynamic>{};
      normalized.add({
        'tipo': 'Avvicinamento',
        'peso': (source['peso'] ?? '').toString(),
        'ripetizioniFatte': (source['ripetizioniFatte'] ?? '').toString(),
        'isCompletata': false,
        'rpe': (source['rpe'] ?? '').toString(),
        'percentualeTarget': (source['percentualeTarget'] ?? '').toString(),
      });
    }

    final defaultPercent =
        (modalita == 'percentuale' && percentualeMassimale != null)
        ? percentualeMassimale.toStringAsFixed(
            percentualeMassimale % 1 == 0 ? 0 : 1,
          )
        : '';

    for (int i = 0; i < workingSet; i++) {
      final source = i < workExisting.length
          ? workExisting[i]
          : const <String, dynamic>{};
      final sourceTipo = (source['tipo'] ?? '').toString();
      final tipo =
          sourceTipo.trim().isEmpty ||
              sourceTipo.toLowerCase().contains('avvicin')
          ? 'Working Set'
          : sourceTipo;
      final sourcePercent = (source['percentualeTarget'] ?? '')
          .toString()
          .trim();

      normalized.add({
        'tipo': tipo,
        'peso': (source['peso'] ?? '').toString(),
        'ripetizioniFatte': (source['ripetizioniFatte'] ?? '').toString(),
        'isCompletata': false,
        'rpe': (source['rpe'] ?? '').toString(),
        'percentualeTarget': sourcePercent.isNotEmpty
            ? sourcePercent
            : defaultPercent,
      });
    }

    return normalized;
  }

  static List<Map<String, dynamic>> _flattenRawSchede(List<dynamic> rawItems) {
    final flattened = <Map<String, dynamic>>[];

    void pushCandidate(
      Map<String, dynamic> candidate, {
      int? inheritedWeek,
      String? inheritedCategory,
      String? inheritedSeduta,
    }) {
      final normalized = Map<String, dynamic>.from(candidate);

      final hasWeek =
          normalized['settimanaCorrente'] != null ||
          normalized['settimana'] != null ||
          normalized['week'] != null;
      if (!hasWeek && inheritedWeek != null) {
        normalized['settimanaCorrente'] = inheritedWeek;
      }

      final categoria = normalized['categoria']?.toString().trim();
      if ((categoria == null || categoria.isEmpty) &&
          inheritedCategory != null &&
          inheritedCategory.isNotEmpty) {
        normalized['categoria'] = inheritedCategory;
      }

      final hasSeduta =
          normalized['seduta'] != null ||
          normalized['sessione'] != null ||
          normalized['session'] != null ||
          normalized['day'] != null;
      if (!hasSeduta && inheritedSeduta != null && inheritedSeduta.isNotEmpty) {
        normalized['seduta'] = inheritedSeduta;
      }

      flattened.add(normalized);
    }

    void walkNode(
      dynamic node, {
      int? inheritedWeek,
      String? inheritedCategory,
      String? inheritedSeduta,
    }) {
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node.cast<String, dynamic>());

      final ownWeekRaw =
          map['settimanaCorrente'] ?? map['settimana'] ?? map['week'];
      final ownWeek = ownWeekRaw != null
          ? _parseWeekOrDefault(ownWeekRaw, inheritedWeek ?? 1)
          : inheritedWeek;

      final ownCategoryRaw = map['categoria']?.toString().trim();
      final ownCategory = (ownCategoryRaw != null && ownCategoryRaw.isNotEmpty)
          ? ownCategoryRaw
          : (ownWeek != null ? 'Week $ownWeek' : inheritedCategory);

      final ownSedutaRaw =
          (map['seduta'] ?? map['sessione'] ?? map['session'] ?? map['day'])
              ?.toString()
              .trim();
      final ownSeduta = (ownSedutaRaw != null && ownSedutaRaw.isNotEmpty)
          ? ownSedutaRaw
          : inheritedSeduta;

      if (map['esercizi'] is List) {
        pushCandidate(
          map,
          inheritedWeek: ownWeek,
          inheritedCategory: ownCategory,
          inheritedSeduta: ownSeduta,
        );
        return;
      }

      var expandedAnyNested = false;

      for (final key in const [
        'settimane',
        'schede',
        'items',
        'giorni',
        'days',
        'sessions',
        'sedute',
        'workouts',
      ]) {
        final nested = map[key];

        if (nested is List) {
          expandedAnyNested = true;
          for (final child in nested) {
            walkNode(
              child,
              inheritedWeek: ownWeek,
              inheritedCategory: ownCategory,
              inheritedSeduta: ownSeduta,
            );
          }
        } else if (nested is Map) {
          expandedAnyNested = true;
          for (final entry in nested.entries) {
            final child = entry.value;
            if (child is! Map) continue;
            final childMap = Map<String, dynamic>.from(
              child.cast<String, dynamic>(),
            );

            final hasSeduta =
                childMap['seduta'] != null ||
                childMap['sessione'] != null ||
                childMap['session'] != null ||
                childMap['day'] != null;
            if (!hasSeduta) {
              childMap['seduta'] = entry.key.toString();
            }

            walkNode(
              childMap,
              inheritedWeek: ownWeek,
              inheritedCategory: ownCategory,
              inheritedSeduta: ownSeduta,
            );
          }
        }
      }

      if (!expandedAnyNested) {
        pushCandidate(
          map,
          inheritedWeek: ownWeek,
          inheritedCategory: ownCategory,
          inheritedSeduta: ownSeduta,
        );
      }
    }

    for (final item in rawItems) {
      walkNode(item);
    }

    if (flattened.isEmpty) {
      return rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    }

    return flattened;
  }

  static List<Map<String, dynamic>> _normalizzaSchemaSchede(
    List<dynamic> rawItems,
  ) {
    final schedeRaw = _flattenRawSchede(rawItems);

    return schedeRaw.asMap().entries.map((entry) {
      final index = entry.key;
      final rawScheda = entry.value;
      final scheda = Map<String, dynamic>.from(
        rawScheda.cast<String, dynamic>(),
      );

      final rawId = scheda['id']?.toString().trim();
      final rawWeek =
          scheda['settimanaCorrente'] ?? scheda['settimana'] ?? scheda['week'];
      final nomeRaw = scheda['nome']?.toString().trim();
      final categoriaRaw = scheda['categoria']?.toString().trim();

      final hasWeekHint =
          rawWeek != null ||
          RegExp(
            r'week|settiman',
            caseSensitive: false,
          ).hasMatch('${scheda['nome'] ?? ''} ${scheda['categoria'] ?? ''}');

      final settimanaCorrente = _resolveWeekNumber(
        rawWeek: rawWeek,
        categoria: categoriaRaw,
        nome: nomeRaw,
      );

      final sedutaRaw =
          (scheda['seduta'] ??
                  scheda['sessione'] ??
                  scheda['session'] ??
                  scheda['day'])
              ?.toString()
              .trim();

      String nomeScheda;
      if (nomeRaw != null && nomeRaw.isNotEmpty) {
        nomeScheda = nomeRaw;
      } else if (sedutaRaw != null && sedutaRaw.isNotEmpty) {
        nomeScheda = 'Week $settimanaCorrente - Seduta $sedutaRaw';
      } else if (hasWeekHint) {
        nomeScheda = 'Week $settimanaCorrente - Seduta';
      } else {
        nomeScheda = 'Scheda Importata';
      }

      final eserciziRaw = scheda['esercizi'];
      final esercizi = (eserciziRaw is List ? eserciziRaw : <dynamic>[])
          .whereType<Map>()
          .map((rawEs) {
            final es = Map<String, dynamic>.from(rawEs.cast<String, dynamic>());

            final percentuale = _toDoubleOrNull(
              es['percentualeMassimale'] ?? es['percentuale'],
            );
            final massimale = _toDoubleOrNull(
              es['massimaleKg'] ?? es['massimale'],
            );
            final infoTestuale = [
              es['ripetizioni'],
              es['note'],
              es['descrizione'],
            ].where((v) => v != null).map((v) => v.toString()).join(' ');

            final bigThree = _isBigThreeLift((es['nome'] ?? '').toString());
            final percentualeDaTesto = _extractPercentFromText(infoTestuale);
            final massimaleDaTesto = _extractOneRmFromText(infoTestuale);
            final percentualeFinale =
                percentuale ?? (bigThree ? percentualeDaTesto : null);
            final massimaleFinale =
                massimale ?? (bigThree ? massimaleDaTesto : null);

            String modalita = (es['modalitaIntensita'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (modalita != 'rir' && modalita != 'percentuale') {
              modalita = (percentualeFinale != null || massimaleFinale != null)
                  ? 'percentuale'
                  : 'rir';
            }

            final tecnicheValue = es['tecniche'];
            final metodo = es['metodo']?.toString().trim();
            List<String> tecniche = tecnicheValue is List
                ? tecnicheValue
                      .map((t) => t.toString())
                      .where((t) => t.trim().isNotEmpty)
                      .toList()
                : (tecnicheValue is String && tecnicheValue.trim().isNotEmpty)
                ? <String>[tecnicheValue.trim()]
                : (metodo != null && metodo.isNotEmpty)
                ? <String>[metodo]
                : <String>[];

            // Fallback: se nessuna tecnica dal JSON, cerca nei campi testuali
            if (tecniche.isEmpty || (tecniche.length == 1 && tecniche.first.toLowerCase() == 'classico')) {
              final testoLibero = [
                es['nome']?.toString() ?? '',
                es['note']?.toString() ?? '',
                es['descrizione']?.toString() ?? '',
                es['metodo']?.toString() ?? '',
                es['tags'] is List ? (es['tags'] as List).join(' ') : (es['tags']?.toString() ?? ''),
              ].join(' ');
              final estratte = _extractTechniqueFromText(testoLibero);
              if (estratte.isNotEmpty) tecniche = estratte;
            }

            if (tecniche.isEmpty) tecniche = ['Classico'];

            // Estrai RIR dalla nota se non è nel campo dedicato (es. "RIR 2", "RIR: 2-3")
            final noteRaw = (es['note'] ?? es['descrizione'])?.toString();
            double? rirFromNote;
            String? notePulita = noteRaw;
            if (noteRaw != null && es['rirTarget'] == null && es['rir'] == null && es['rpe'] == null) {
              final rirMatch = RegExp(r'[Rr][Ii][Rr]\s*:?\s*(\d+(?:[.,]\d+)?)', caseSensitive: false).firstMatch(noteRaw);
              if (rirMatch != null) {
                rirFromNote = double.tryParse((rirMatch.group(1) ?? '').replaceAll(',', '.'));
                notePulita = noteRaw.replaceAll(RegExp(r'[Rr][Ii][Rr]\s*:?\s*\d+(?:[.,\-]\d+)*\s*'), '').trim();
                if (notePulita.isEmpty) notePulita = null;
              }
            }
            final rirDaInput = es['rirTarget'] ?? es['rir'] ?? es['rpe'] ?? rirFromNote?.toString();

            final serieAttiveRaw = es['serieAttive'];
            final serieAttiveList = serieAttiveRaw is List
                ? serieAttiveRaw
                : <dynamic>[];

            final avvFromSerieAttive = serieAttiveList.whereType<Map>().where((
              s,
            ) {
              final tipo = (s['tipo'] ?? '').toString().toLowerCase();
              return tipo.contains('avvicin');
            }).length;

            final workFromSerieAttive = serieAttiveList.whereType<Map>().where((
              s,
            ) {
              final tipo = (s['tipo'] ?? '').toString().toLowerCase();
              return !tipo.contains('avvicin');
            }).length;

            final ripetizioniRaw =
                (es['ripetizioni'] ?? es['reps'] ?? es['rep'] ?? '').toString();
            final schemaRaw =
                (es['schema'] ?? es['setsReps'] ?? es['sets_reps'] ?? '')
                    .toString();
            final tagsRaw = es['tags'];
            final tagsText = tagsRaw is List
                ? tagsRaw.map((t) => t.toString()).join(' ')
                : tagsRaw?.toString() ?? '';
            final tecnicheText = tecniche.join(' ');
            final setRepContext = [
              schemaRaw,
              ripetizioniRaw,
              metodo ?? '',
              tecnicheText,
              tagsText,
              es['note']?.toString() ?? '',
              es['descrizione']?.toString() ?? '',
              es['nome']?.toString() ?? '',
            ].join(' ');
            final inferredSetRep = _extractSetRepFromText(setRepContext);
            final setsFromText =
                _extractSetCountFromText(setRepContext) ?? inferredSetRep.sets;

            final avvicinamento =
                _firstPositiveInt([
                  es['avvicinamento'],
                  es['warmupSets'],
                  es['warmUpSets'],
                  es['rampUpSets'],
                  es['serieAvvicinamento'],
                  es['avv'],
                ]) ??
                (avvFromSerieAttive > 0 ? avvFromSerieAttive : 0);

            final workingSetFromFields = _firstPositiveInt([
              es['workingSet'],
              es['workingSets'],
              es['serieAllenanti'],
              es['serieLavoro'],
              es['sets'],
              es['set'],
            ]);

            final shouldOverrideFieldOne =
                workingSetFromFields == 1 &&
                setsFromText != null &&
                setsFromText > 1;
            final workingSet = shouldOverrideFieldOne
                ? setsFromText
                : (workingSetFromFields ??
                      setsFromText ??
                      (workFromSerieAttive > 0 ? workFromSerieAttive : 3));

            var ripetizioniFinal = ripetizioniRaw;
            final inferredReps = inferredSetRep.reps;
            final isSingleDefault = _looksDefaultSingleRep(ripetizioniRaw);
            if ((ripetizioniFinal.trim().isEmpty || isSingleDefault) &&
                inferredReps != null &&
                inferredReps.isNotEmpty &&
                inferredReps != '1') {
              ripetizioniFinal = inferredReps;
            }

            if (ripetizioniFinal.trim().isEmpty) {
              ripetizioniFinal = '8-10';
            }

            final normalizedSerieAttive = _normalizeSerieAttiveForImport(
              rawSerieAttive: serieAttiveList,
              avvicinamento: avvicinamento,
              workingSet: workingSet,
              modalita: modalita,
              percentualeMassimale: modalita == 'percentuale'
                  ? percentualeFinale
                  : null,
            );

            return {
              'nome': es['nome']?.toString().trim().isNotEmpty == true
                  ? es['nome']
                  : 'Esercizio',
              'avvicinamento': avvicinamento,
              'workingSet': workingSet,
              'ripetizioni': ripetizioniFinal,
              'recupero': (es['recupero'] ?? es['rest'] ?? es['pausa'] ?? '')
                  .toString(),
              'note': notePulita,
              'tecniche': tecniche,
              'modalitaIntensita': modalita,
              'rirTarget': modalita == 'rir' && rirDaInput != null
                  ? rirDaInput.toString().trim()
                  : null,
              'percentualeMassimale': modalita == 'percentuale'
                  ? percentualeFinale
                  : null,
              'massimaleKg': modalita == 'percentuale' ? massimaleFinale : null,
              'caricoTargetKg': _toDoubleOrNull(es['caricoTargetKg']),
              'serieAttive': normalizedSerieAttive,
            };
          })
          .toList();

      final normalizedCategoria =
          (categoriaRaw != null && categoriaRaw.isNotEmpty)
          ? categoriaRaw
          : hasWeekHint
          ? 'Week $settimanaCorrente'
          : 'Importata AI';

      final stableId = (rawId != null && rawId.isNotEmpty)
          ? rawId
          : 'ai_${index + 1}_${nomeScheda.hashCode.abs()}_${settimanaCorrente}_${normalizedCategoria.hashCode.abs()}';

      return {
        'id': stableId,
        'nome': nomeScheda,
        'livello': scheda['livello']?.toString().trim().isNotEmpty == true
            ? scheda['livello']
            : 'Intermedio',
        'categoria': normalizedCategoria,
        'continuativa': scheda['continuativa'] ?? true,
        'settimanaCorrente': settimanaCorrente,
        'esercizi': esercizi,
      };
    }).toList();
  }

  // Helper pubblico per test/debug locale della normalizzazione import AI.
  static List<Map<String, dynamic>> normalizeImportedSchedeForTest(
    List<dynamic> rawItems, {
    List<String> nomiUfficiali = const [],
    bool enrichSetRepFromTags = true,
    bool synthesizeMissingWeeks = true,
  }) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('AI NORMALIZE TEST DEBUG items=${rawItems.length}');
    }
    return _readSchedeFromGeneratedJson(
      rawItems,
      enrichSetRepFromTags: enrichSetRepFromTags,
      synthesizeMissingWeeks: synthesizeMissingWeeks,
    ).map((s) => s.toJson()).toList();
  }

  // Migrazione one-shot per archivi locali storici:
  // recupera set/rep da tecniche legacy (es. "4x10") e ripulisce le etichette.
  static List<Scheda> migrateLegacySetRepInSavedSchede(List<Scheda> schede) {
    if (schede.isEmpty) return const <Scheda>[];

    final rawMaps = schede.map((s) => s.toJson()).toList();
    _enrichSetRepFromTagsInPlace(rawMaps);

    return rawMaps.map(Scheda.fromJson).toList();
  }

  static Future<Map<String, dynamic>?> _postProxy(
    String endpoint,
    Map<String, dynamic> payload, {
    Duration requestTimeout = const Duration(seconds: 45),
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AiProxyException('Utente non autenticato.', statusCode: 401);
    }

    try {
      final idToken = await user.getIdToken(true).timeout(
        const Duration(seconds: 20),
      );

      final proxyBases = <String>[];

      void addBaseCandidate(String raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return;

        final normalized = trimmed.endsWith('/')
            ? trimmed.substring(0, trimmed.length - 1)
            : trimmed;
        if (normalized.isEmpty) return;

        if (!proxyBases.contains(normalized)) {
          proxyBases.add(normalized);
        }
      }

      addBaseCandidate(_aiProxyBaseUrl);
      addBaseCandidate(_aiProxyFallbackBaseUrl);
      addBaseCandidate(_defaultWorkerProxyBaseUrl);
      addBaseCandidate(_defaultFirebaseProxyBaseUrl);

      if (proxyBases.isEmpty) {
        throw const AiProxyException(
          'AI proxy non configurato. Imposta AI_PROXY_BASE_URL.',
        );
      }

      final endpointClean = endpoint.trim().replaceAll(RegExp(r'^/+|/+$'), '');
      if (endpointClean.isEmpty) {
        throw const AiProxyException('Endpoint AI non valido.');
      }

      final candidates = <Uri>[];

      void addCandidate(Uri uri) {
        if (!candidates.contains(uri)) {
          candidates.add(uri);
        }
      }

      void addEndpointCandidates(String base, Uri? parsedBase, String ep) {
        addCandidate(Uri.parse('$base/$ep'));
        addCandidate(Uri.parse('$base/$ep/'));

        if (parsedBase != null && parsedBase.hasAuthority) {
          addCandidate(
            parsedBase.replace(path: '/$ep', query: null, fragment: null),
          );
          addCandidate(
            parsedBase.replace(path: '/$ep/', query: null, fragment: null),
          );
        }
      }

      final endpointLower = endpointClean.toLowerCase();

      for (final base in proxyBases) {
        final parsedBase = Uri.tryParse(base);

        if (base.endsWith('/$endpointClean') ||
            base.endsWith('/$endpointClean/')) {
          addCandidate(Uri.parse(base));
        }

        addEndpointCandidates(base, parsedBase, endpointClean);
        if (endpointLower != endpointClean) {
          addEndpointCandidates(base, parsedBase, endpointLower);
        }

        // Extra resilience: if edge/path routing is inconsistent, hit the host root.
        // The worker can infer target operation from payload fields.
        addCandidate(Uri.parse(base));
        addCandidate(Uri.parse('$base/'));
        if (parsedBase != null && parsedBase.hasAuthority) {
          addCandidate(
            parsedBase.replace(path: '', query: null, fragment: null),
          );
          addCandidate(
            parsedBase.replace(path: '/', query: null, fragment: null),
          );
        }
      }

      final tried = <String>[];
      final notFoundDiagnostics = <String>[];
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
            .timeout(requestTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          throw const AiProxyException(
            'Risposta proxy non valida (JSON atteso).',
          );
        }

        String backendError = 'Errore sconosciuto';
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body['error'] != null) {
            final error = body['error'].toString();
            final details = body['details']?.toString();
            String? debugDetails;
            if (kDebugMode && body['debugJsonRead'] != null) {
              try {
                debugDetails = _truncateForDebug(
                  jsonEncode(body['debugJsonRead']),
                );
              } catch (_) {
                debugDetails = 'debugJsonRead non serializzabile';
              }
            }
            backendError = (details != null && details.trim().isNotEmpty)
                ? '$error | $details'
                : error;
            if (debugDetails != null && debugDetails.isNotEmpty) {
              backendError = '$backendError | debugJsonRead: $debugDetails';
            }
          } else {
            backendError = response.body;
          }
        } catch (_) {
          backendError = response.body;
        }

        tried.add('${uri.toString()} -> ${response.statusCode}');

        if (response.statusCode == 404) {
          final contentType = (response.headers['content-type'] ?? '')
              .toLowerCase();
          final isJsonResponse = contentType.contains('application/json');
          final isEndpointRoute404 = backendError.toLowerCase().contains(
            'endpoint non trovato',
          );

          final server = response.headers['server'];
          final cfRay = response.headers['cf-ray'];
          final compactBody = response.body
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final bodyPreview = compactBody.isEmpty
              ? ''
              : _truncateForDebug(compactBody, max: 240);

          final details = StringBuffer('${uri.toString()} -> 404');
          if (server != null && server.trim().isNotEmpty) {
            details.write(' server=$server');
          }
          if (cfRay != null && cfRay.trim().isNotEmpty) {
            details.write(' cf-ray=$cfRay');
          }
          if (bodyPreview.isNotEmpty) {
            details.write(' body="$bodyPreview"');
          }
          notFoundDiagnostics.add(details.toString());

          // If a JSON 404 comes from proxy business logic (for example Gemini model 404),
          // surface it immediately instead of mislabeling it as endpoint-not-found.
          if (isJsonResponse && !isEndpointRoute404) {
            throw AiProxyException(
              'Proxy AI errore 404',
              statusCode: 404,
              details: backendError,
            );
          }

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
        details: [
          'URL provati: ${tried.join(' | ')}',
          if (notFoundDiagnostics.isNotEmpty)
            'Diagnostica 404: ${notFoundDiagnostics.join(' || ')}',
        ].join(' | '),
      );
    } on TimeoutException {
      throw const AiProxyException(
        'Timeout durante la connessione al proxy AI.',
        statusCode: 408,
      );
    } on SocketException {
      throw const AiProxyException(
        'Nessuna connessione di rete verso il proxy AI.',
      );
    }
  }

  static String _friendlyProxyError(AiProxyException e) {
    final code = e.statusCode;
    final details = e.details?.trim();

    if (code == 401 || code == 403) {
      return 'Sessione scaduta o non autorizzata. Esci e rientra nell\'app, poi riprova.';
    }
    if (code == 404) {
      final lowered = (details ?? '').toLowerCase();
      final isModelNotFound =
          lowered.contains('gemini error 404') ||
          lowered.contains('not found for api version') ||
          lowered.contains('models/') ||
          lowered.contains('generatecontent');

      if (isModelNotFound) {
        return 'Il provider AI ha restituito 404 sul modello Gemini configurato. Aggiorna i modelli fallback del proxy e riprova.';
      }

      if (details != null && details.isNotEmpty) {
        return 'Endpoint AI non trovato. Base URL attuale: ${_aiProxyBaseUrl.isEmpty ? '(vuoto)' : _aiProxyBaseUrl}. $details';
      }
      return 'Endpoint AI non trovato. Base URL attuale: ${_aiProxyBaseUrl.isEmpty ? '(vuoto)' : _aiProxyBaseUrl}. Verifica AI_PROXY_BASE_URL e deploy del proxy.';
    }
    if (code == 408) {
      return 'Timeout AI: il PDF sta impiegando troppo tempo. Riprova con rete stabile (meglio Wi-Fi) oppure con un PDF piu leggero.';
    }
    if (code == 524) {
      return 'Timeout upstream (524): Gemini non ha risposto in tempo. Riprova con un PDF piu corto o meno pesante; il retry veloce e gia attivo automaticamente.';
    }
    if (code == 400) {
      if (details != null && details.isNotEmpty) {
        return 'Gemini ha rifiutato il contenuto inviato. Dettagli: $details';
      }
      return 'Gemini ha rifiutato il contenuto inviato (400). Verifica che il PDF non sia protetto/corrotto e riprova.';
    }
    if (code == 422) {
      final lowered = (details ?? '').toLowerCase();
      if (lowered.contains('troncata') ||
          lowered.contains('incompleto') ||
          lowered.contains('max_tokens')) {
        return 'Il PDF e molto denso e l\'output AI e stato troncato. Riprova: il sistema passa automaticamente in modalita compatta per recuperare tutte le week.';
      }
      return details != null && details.isNotEmpty
          ? 'Risposta AI non valida durante la lettura del PDF: $details'
          : 'Risposta AI non valida durante la lettura del PDF. Riprova.';
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

  static bool _isRetryablePdfProxyStatus(int? statusCode) {
    return {
      422,
      500,
      408,
      502,
      503,
      504,
      520,
      522,
      523,
      524,
      525,
      526,
      527,
      530,
    }.contains(statusCode);
  }

  static final RegExp _weekOnlyCategoryPattern = RegExp(
    r'^\s*(?:week|settimana)\s*\d+\s*$',
    caseSensitive: false,
  );

  static String _deriveUnifiedImportCategory(List<Map<String, dynamic>> maps) {
    final structuredName = _lastStructuredPlan?.nomeScheda.trim();
    if (structuredName != null && structuredName.isNotEmpty) {
      return structuredName;
    }

    for (final map in maps) {
      final category = (map['categoria'] ?? '').toString().trim();
      if (category.isEmpty || _weekOnlyCategoryPattern.hasMatch(category)) {
        continue;
      }
      return category;
    }

    for (final map in maps) {
      var candidate = (map['nome'] ?? '').toString().trim();
      if (candidate.isEmpty) continue;

      candidate = candidate
          .replaceFirst(
            RegExp(
              r'\s*-\s*(?:w|week|settimana)\s*\d+\b.*$',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return 'Importata AI';
  }

  static void _coalesceWeekCategoriesInPlace(List<Map<String, dynamic>> maps) {
    if (maps.isEmpty) return;

    final onlyWeekLikeOrEmpty = maps.every((map) {
      final category = (map['categoria'] ?? '').toString().trim();
      return category.isEmpty || _weekOnlyCategoryPattern.hasMatch(category);
    });

    if (!onlyWeekLikeOrEmpty) return;

    final unifiedCategory = _deriveUnifiedImportCategory(maps);
    for (final map in maps) {
      map['categoria'] = unifiedCategory;
    }
  }

  static String _stripWeekMarkersFromName(String input) {
    final original = input.trim();
    if (original.isEmpty) return original;

    var cleaned = original.replaceFirst(_weekPrefixNamePattern, '').trim();
    cleaned = cleaned.replaceFirst(_weekSuffixNamePattern, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned.isEmpty ? original : cleaned;
  }

  static String _withWeekInName(String input, int week) {
    final raw = input.trim();
    if (raw.isEmpty) return 'Week $week - Seduta';

    if (RegExp(r'(?:\bweek\b|\bsettimana\b|\bw\b)\s*[-_ ]*\d+', caseSensitive: false)
        .hasMatch(raw)) {
      return raw
          .replaceFirst(
            RegExp(r'(?:\bweek\b|\bsettimana\b|\bw\b)\s*[-_ ]*\d+', caseSensitive: false),
            'Week $week',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    return 'Week $week - $raw';
  }

  static int _resolveWeekForMap(Map<String, dynamic> map) {
    return _resolveWeekNumber(
      rawWeek: map['settimanaCorrente'] ?? map['settimana'] ?? map['week'],
      categoria: map['categoria']?.toString(),
      nome: map['nome']?.toString(),
    );
  }

  static int _exerciseCountInMap(Map<String, dynamic> map) {
    final esercizi = map['esercizi'];
    return esercizi is List ? esercizi.length : 0;
  }

  static String _sessionAnchorForMap(Map<String, dynamic> map) {
    final seduta =
        (map['seduta'] ?? map['sessione'] ?? map['session'] ?? map['day'] ?? map['giorno'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';

    final nomeBase = _stripWeekMarkersFromName((map['nome'] ?? '').toString())
        .toLowerCase()
        .trim();

    final esercizi = map['esercizi'];
    final exerciseSignature = esercizi is List
        ? esercizi
              .whereType<Map>()
              .map((e) => _normalizza((e['nome'] ?? '').toString()))
              .where((n) => n.isNotEmpty)
              .take(4)
              .join('|')
        : '';

    if (seduta.isNotEmpty) return '$seduta|$exerciseSignature';
    if (nomeBase.isNotEmpty) return '$nomeBase|$exerciseSignature';
    return exerciseSignature.isNotEmpty ? exerciseSignature : 'session_fallback';
  }

  static bool _hasWeekSignalInMap(Map<String, dynamic> map) {
    final week = _resolveWeekForMap(map);
    if (week > 1) return true;

    final context =
        '${map['nome'] ?? ''} ${map['categoria'] ?? ''} ${map['seduta'] ?? map['sessione'] ?? map['day'] ?? ''}'
            .toLowerCase();
    return RegExp(r'(?:\bweek\b|\bsettimana\b|\bw\s*\d+)', caseSensitive: false)
        .hasMatch(context);
  }

  static void _expandWeeksFromSingleWeekInPlace(
    List<Map<String, dynamic>> maps, {
    int targetWeeks = 14,
  }) {
    if (maps.isEmpty) return;
    final hasSignal = maps.any(_hasWeekSignalInMap);
    if (kDebugMode) {
      // ignore: avoid_print
      print('AI EXPAND DEBUG hasSignal=$hasSignal maps=${maps.length} names=${maps.map((m) => m['nome']).toList()} cats=${maps.map((m) => m['categoria']).toList()}');
    }
    if (!hasSignal) return;

    final observedWeeks = maps.map(_resolveWeekForMap).toSet();
    if (kDebugMode) {
      // ignore: avoid_print
      print('AI EXPAND DEBUG observedWeeks=$observedWeeks');
    }
    // If at least one explicit week > 1 already exists, keep source weeks as-is.
    if (observedWeeks.any((w) => w > 1)) return;

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final map in maps) {
      final key = _sessionAnchorForMap(map);
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(map);
    }

    final expanded = <Map<String, dynamic>>[];

    for (final group in grouped.values) {
      final weekMap = <int, Map<String, dynamic>>{};
      for (final item in group) {
        final week = _resolveWeekForMap(item);
        final existing = weekMap[week];
        if (existing == null ||
            _exerciseCountInMap(item) > _exerciseCountInMap(existing)) {
          weekMap[week] = item;
        }
      }

      final baseline = weekMap[1] ?? group.first;
      final baselineName = _stripWeekMarkersFromName(
        (baseline['nome'] ?? '').toString(),
      );
      final baselineId = (baseline['id'] ?? '').toString().trim();
      final baselineWeek = _resolveWeekForMap(baseline);

      for (int week = 1; week <= targetWeeks; week += 1) {
        final source = weekMap[week] ?? baseline;
        final cloned = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
        );

        cloned['settimanaCorrente'] = week;
        cloned['nome'] = _withWeekInName(
          baselineName.isNotEmpty ? baselineName : (cloned['nome'] ?? '').toString(),
          week,
        );

        if (!weekMap.containsKey(week)) {
          if (baselineId.isNotEmpty) {
            cloned['id'] = '${baselineId}_w$week';
          } else {
            cloned.remove('id');
          }

          final offset = week - (baselineWeek > 0 ? baselineWeek : 1);
          _applyWeekOffsetToSchedaMap(cloned, offset);
        }

        expanded.add(cloned);
      }
    }

    maps
      ..clear()
      ..addAll(expanded);
    if (kDebugMode) {
      // ignore: avoid_print
      print('AI EXPAND DEBUG expanded=${maps.length}');
    }
  }

  static int _inferWeekFromScheda(Scheda scheda) {
    final raw = scheda.settimanaCorrente;
    final fromName = _parseWeekOrDefault(scheda.nome, -1);
    final fromCategory = _parseWeekOrDefault(scheda.categoria, -1);

    if (raw > 1) return raw;
    if (fromName > 0 && fromName != raw) return fromName;
    if (fromCategory > 0 && fromCategory != raw) return fromCategory;
    return raw > 0 ? raw : 1;
  }

  static String _sessionAnchorForImportedScheda(Scheda scheda) {
    final baseName = _stripWeekMarkersFromName(scheda.nome);
    final normalizedName = _normalizza(
      baseName.isEmpty ? scheda.nome : baseName,
    );
    final normalizedCategory = _normalizza(scheda.categoria);
    // Intentionally excludes exercise signature: exercises can legitimately
    // change between weeks, so identity is name+category only.
    return '$normalizedCategory|$normalizedName';
  }

  static AiImportWeeklyResolution collapseImportedSchedeForWeeklyProgression(
    List<Scheda> schede,
  ) {
    if (schede.isEmpty) {
      return const AiImportWeeklyResolution(
        schedeVisibili: <Scheda>[],
        weekHistoryStoreEntries: <String, Map<String, dynamic>>{},
      );
    }

    final grouped = <String, List<Scheda>>{};
    for (final scheda in schede) {
      final anchor = _sessionAnchorForImportedScheda(scheda);
      grouped.putIfAbsent(anchor, () => <Scheda>[]).add(scheda);
    }

    final hasMultiWeekGroups = grouped.values.any((group) {
      final weeks = group.map(_inferWeekFromScheda).toSet();
      return weeks.length > 1;
    });

    final importSeed = DateTime.now().microsecondsSinceEpoch;
    var importCounter = 0;

    String nextImportedId(String baseId) {
      importCounter += 1;
      final safeBase = baseId.trim().isEmpty ? 'imported' : baseId;
      return 'imp_${importSeed}_${importCounter}_${safeBase.hashCode.abs()}';
    }

    final schedeVisibili = <Scheda>[];
    final weekHistoryStoreEntries = <String, Map<String, dynamic>>{};

    if (!hasMultiWeekGroups) {
      for (final scheda in schede) {
        final normalized = Map<String, dynamic>.from(scheda.toJson());
        final cleanedName = _stripWeekMarkersFromName(scheda.nome);
        if (cleanedName.isNotEmpty) {
          normalized['nome'] = cleanedName;
        }
        normalized['settimanaCorrente'] = 1;
        normalized['id'] = nextImportedId(scheda.id);
        schedeVisibili.add(Scheda.fromJson(normalized));
      }

      return AiImportWeeklyResolution(
        schedeVisibili: schedeVisibili,
        weekHistoryStoreEntries: const <String, Map<String, dynamic>>{},
      );
    }

    for (final group in grouped.values) {
      final ordered = List<Scheda>.from(group)
        ..sort((a, b) {
          final wa = _inferWeekFromScheda(a);
          final wb = _inferWeekFromScheda(b);
          if (wa != wb) return wa.compareTo(wb);
          return a.nome.compareTo(b.nome);
        });

      final base = ordered.firstWhere(
        (s) => _inferWeekFromScheda(s) == 1,
        orElse: () => ordered.first,
      );

      final baseJson = Map<String, dynamic>.from(base.toJson());
      final cleanedName = _stripWeekMarkersFromName(base.nome);
      if (cleanedName.isNotEmpty) {
        baseJson['nome'] = cleanedName;
      }
      baseJson['id'] = nextImportedId(base.id);
      baseJson['settimanaCorrente'] = 1;

      final visibleScheda = Scheda.fromJson(baseJson);

      // Embed ALL weeks' exercises into the Scheda so it is self-contained.
      for (final candidate in ordered) {
        final week = _inferWeekFromScheda(candidate);
        visibleScheda.eserciziPerSettimana[week] = candidate.esercizi;
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('[COLLAPSE] "${visibleScheda.nome}" id=${visibleScheda.id} weeks=${visibleScheda.eserciziPerSettimana.keys.toList()..sort()} exercises_per_week=${visibleScheda.eserciziPerSettimana.map((k, v) => MapEntry(k, v.length))}');
      }

      schedeVisibili.add(visibleScheda);

      // Also build the external snapshot store for backwards compat
      // (dettaglio_scheda_screen still reads from SharedPreferences).
      final snapshots = <String, dynamic>{};
      for (final candidate in ordered) {
        final week = _inferWeekFromScheda(candidate);
        if (week <= 1) continue;

        final snapshot = Map<String, dynamic>.from(candidate.toJson());
        snapshot['id'] = visibleScheda.id;
        snapshot['nome'] = visibleScheda.nome;
        snapshot['categoria'] = visibleScheda.categoria;
        snapshot['settimanaCorrente'] = week;
        snapshots[week.toString()] = snapshot;
      }

      if (snapshots.isNotEmpty) {
        weekHistoryStoreEntries[visibleScheda.id] = snapshots;
      }
    }

    return AiImportWeeklyResolution(
      schedeVisibili: schedeVisibili,
      weekHistoryStoreEntries: weekHistoryStoreEntries,
    );
  }

  static List<Scheda> _readSchedeFromGeneratedJson(
    List<dynamic> items, {
    bool enrichSetRepFromTags = true,
    bool synthesizeMissingWeeks = true,
  }) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('AI READ JSON DEBUG items=${items.length}');
    }
    final parsedMaps = <Map<String, dynamic>>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      parsedMaps.add(Map<String, dynamic>.from(raw.cast<String, dynamic>()));
    }

    if (enrichSetRepFromTags) {
      _enrichSetRepFromTagsInPlace(parsedMaps);
    }
    if (synthesizeMissingWeeks) {
      _expandWeeksFromSingleWeekInPlace(parsedMaps);
    }
    _coalesceWeekCategoriesInPlace(parsedMaps);

    final out = <Scheda>[];
    for (final map in parsedMaps) {
      out.add(Scheda.fromJson(map));
    }

    return out;
  }

  static Future<List<Scheda>?> _analizzaDocumentoScheda({
    required List<int> bytes,
    required String endpoint,
    required String payloadField,
    required String sourceLabel,
  }) async {
    try {
      _lastError = null;
      _lastStructuredPlan = null;

      if (bytes.isEmpty) {
        _lastError = 'Il file selezionato e vuoto.';
        return null;
      }

      const maxBytes = 10 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        _lastError = 'File troppo grande. Limite massimo 10MB.';
        return null;
      }

      final database = await ApiEsercizi.ottieniEserciziTradotti();
      final List<String> nomiUfficiali = database
          .map((e) => e['nome'].toString())
          .toSet()
          .toList();

      final payload = {
        payloadField: base64Encode(bytes),
        'nomiUfficiali': nomiUfficiali,
        'debugJsonRead': true,
      };

      final isPdf = endpoint == 'analyzeWorkoutPdf';
      Map<String, dynamic>? risultato;

      try {
        risultato = await _postProxy(
          endpoint,
          payload,
          requestTimeout: isPdf
              ? const Duration(seconds: 150)
              : const Duration(seconds: 45),
        );
      } on AiProxyException catch (e) {
        // PDFs can legitimately take longer due to upload + OCR/extraction on Gemini.
        if (isPdf && _isRetryablePdfProxyStatus(e.statusCode)) {
          final retryPayload = {...payload, 'fastMode': true};

          try {
            risultato = await _postProxy(
              endpoint,
              retryPayload,
              requestTimeout: const Duration(seconds: 210),
            );
          } on AiProxyException catch (retryError) {
            if (_isRetryablePdfProxyStatus(retryError.statusCode)) {
              risultato = await _postProxy(
                endpoint,
                retryPayload,
                requestTimeout: const Duration(seconds: 240),
              );
            } else {
              rethrow;
            }
          }
        } else {
          rethrow;
        }
      }

      if (risultato == null) return null;

      _logJsonReadDebug(sourceLabel, risultato['debugJsonRead']);
      _captureStructuredPlan(risultato);
      final debugPayload = risultato['debugJsonRead'];
      if (debugPayload is Map<String, dynamic>) {
        _lastDebugJson = debugPayload;
      } else if (debugPayload is Map) {
        _lastDebugJson = Map<String, dynamic>.from(debugPayload);
      }

      final items = risultato['items'];
      if (items is! List) {
        _lastError = 'Output AI non valido: manca array items.';
        return null;
      }

      // For PDF imports we keep AI values as-is: no inferred set/rep overrides
      // and no synthetic week progression from a single detected week.
      final shouldInferFromTags = !isPdf;
      final shouldSynthesizeWeeks = !isPdf;
      final schede = _readSchedeFromGeneratedJson(
        items,
        enrichSetRepFromTags: shouldInferFromTags,
        synthesizeMissingWeeks: shouldSynthesizeWeeks,
      );
      if (schede.isEmpty) {
        _lastError =
            'Output AI non valido: nessuna scheda leggibile dal motore app.';
        return null;
      }
      return schede;
    } on AiProxyException catch (e) {
      _lastError = _friendlyProxyError(e);
      debugPrint('Errore AI $sourceLabel: $e');
      return null;
    } catch (e) {
      _lastError = 'Errore imprevisto durante la connessione all\'IA.';
      debugPrint('Errore AI $sourceLabel: $e');
      return null;
    }
  }

  // FUNZIONE 1: ANALISI FOTO SCHEDA
  static Future<List<Scheda>?> analizzaFotoScheda(XFile foto) async {
    final imageBytes = await foto.readAsBytes();
    return _analizzaDocumentoScheda(
      bytes: imageBytes,
      endpoint: 'analyzeWorkoutPhoto',
      payloadField: 'imageBase64',
      sourceLabel: 'Foto',
    );
  }

  // FUNZIONE 1B: ANALISI PDF SCHEDA
  static Future<List<Scheda>?> analizzaPdfSchedaBytes(Uint8List pdfBytes) {
    return _analizzaDocumentoScheda(
      bytes: pdfBytes,
      endpoint: 'analyzeWorkoutPdf',
      payloadField: 'pdfBase64',
      sourceLabel: 'PDF',
    );
  }

  // --- FUNZIONE 2: VALUTAZIONE SCHEDA ---
  static Future<String?> valutaCartella(
    String nomeCartella,
    List<Scheda> schede,
  ) async {
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
