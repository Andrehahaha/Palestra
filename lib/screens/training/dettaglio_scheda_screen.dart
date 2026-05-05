import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math'; 
import '../../models/scheda.dart';
import '../../models/allenamento.dart';
import '../../models/esercizio.dart';
import '../../models/serie.dart';
import 'crea_esercizio.dart';
import 'settimana_successiva_screen.dart';
import '../../services/api_esercizi.dart';
import '../../services/dizionario_esercizi.dart';
import '../../services/athlete_progress_service.dart';
import '../../services/workload_calculator.dart';


class DettaglioSchedaScreen extends StatefulWidget {
  final Scheda scheda; 
  final List<Allenamento> storico; 

  const DettaglioSchedaScreen({super.key, required this.scheda, required this.storico});

  @override
  State<DettaglioSchedaScreen> createState() => _DettaglioSchedaScreenState();
}

class _DettaglioSchedaScreenState extends State<DettaglioSchedaScreen> with WidgetsBindingObserver {
  static const String _weekHistoryStoreKey = 'week_history_store_v1';
  List<Map<String, dynamic>> _databaseEsercizi = [];
  Timer? _bozzaDebounce;
  final AthleteProgressService _athleteProgressService = AthleteProgressService();
  final Map<int, Map<String, dynamic>> _weekSnapshots = {};
  final Set<String> _collapsedExercises = <String>{};
  bool _compactMode = false;
  bool _showOnlyIncomplete = false;
  bool _headerExpanded = false;

  String get _bozzaKey => 'workout_bozza_${widget.scheda.id}';

  String get _legacyBozzaKeyByName => 'workout_bozza_${widget.scheda.nome}';

  String get _schedaWeekHistoryKey {
    return widget.scheda.id;
  }

  String get _legacySchedaWeekHistoryKey {
    final n = _normalizzaTesto(widget.scheda.nome);
    return n.replaceAll(' ', '_');
  }

  String _exerciseUiKey(Esercizio esercizio, int index) => '${esercizio.nome}_$index';

  bool _isExerciseCollapsed(Esercizio esercizio, int index) {
    return _collapsedExercises.contains(_exerciseUiKey(esercizio, index));
  }

  void _toggleExerciseCollapsed(Esercizio esercizio, int index) {
    final key = _exerciseUiKey(esercizio, index);
    setState(() {
      if (_collapsedExercises.contains(key)) {
        _collapsedExercises.remove(key);
      } else {
        _collapsedExercises.add(key);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitialLoad();
    });
  }

  Future<void> _bootstrapInitialLoad() async {
    try {
      await Future.wait([
        _caricaDatabase(),
        _caricaBozzaWorkout(),
      ]);

      if (!mounted) return;
      await _applicaPrSuSchedaAperta();
    } catch (e, st) {
      debugPrint('Errore bootstrap dettaglio scheda: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bozzaDebounce?.cancel();
    _salvaBozzaWorkout();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _salvaBozzaWorkout();
    }
  }

  void _scheduleBozzaSave() {
    _bozzaDebounce?.cancel();
    _bozzaDebounce = Timer(const Duration(milliseconds: 500), _salvaBozzaWorkout);
  }

  void _snapshotCurrentWeek() {
    _weekSnapshots[widget.scheda.settimanaCorrente] =
        Map<String, dynamic>.from(widget.scheda.toJson());
  }

  bool _applySnapshotForWeek(int week) {
    var raw = _weekSnapshots[week];

    // Fallback: use embedded per-week data from the Scheda model itself.
    if (raw == null) {
      final embeddedEsercizi = widget.scheda.eserciziPerSettimana[week];
      if (embeddedEsercizi == null) return false;
      final weekJson = Map<String, dynamic>.from(widget.scheda.toJson());
      weekJson['settimanaCorrente'] = week;
      weekJson['esercizi'] = embeddedEsercizi.map((e) => e.toJson()).toList();
      raw = weekJson;
    }

    final snapshot = Scheda.fromJson(Map<String, dynamic>.from(raw));
    // Defensive fix: if stored snapshot has mismatched week metadata,
    // force coherence with the slot key to avoid navigation lockups.
    if (snapshot.settimanaCorrente != week) {
      snapshot.settimanaCorrente = week;
    }
    setState(() {
      widget.scheda.nome = snapshot.nome;
      widget.scheda.livello = snapshot.livello;
      widget.scheda.categoria = snapshot.categoria;
      widget.scheda.continuativa = snapshot.continuativa;
      widget.scheda.settimanaCorrente = snapshot.settimanaCorrente;
      widget.scheda.esercizi = snapshot.esercizi;
    });
    return true;
  }

  Future<void> _vaiSettimanaSuccessiva() async {
    _snapshotCurrentWeek();
    final targetWeek = widget.scheda.settimanaCorrente + 1;
    if (kDebugMode) {
      debugPrint('[WEEK] avanti tap: current=${widget.scheda.settimanaCorrente}, target=$targetWeek, snapshots=${_weekSnapshots.keys.toList()..sort()}');
    }

    if (_applySnapshotForWeek(targetWeek)) {
      if (kDebugMode) {
        debugPrint('[WEEK] ripristino snapshot target=$targetWeek riuscito');
      }
      _scheduleBozzaSave();
      return;
    }

    final aggiornata = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettimanaSuccessivaScreen(scheda: widget.scheda),
      ),
    );
    if (aggiornata != null) {
      if (widget.scheda.settimanaCorrente < targetWeek) {
        widget.scheda.settimanaCorrente = targetWeek;
      }
      if (kDebugMode) {
        debugPrint('[WEEK] ritorno da schermata progressione: current=${widget.scheda.settimanaCorrente}, target=$targetWeek');
      }
      setState(() {});
      _snapshotCurrentWeek();
      _scheduleBozzaSave();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Progressione settimana annullata.'),
          backgroundColor: Colors.grey,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _caricaBozzaWorkout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawWeekStore = prefs.getString(_weekHistoryStoreKey);
      if (rawWeekStore != null) {
        final decodedStore = jsonDecode(rawWeekStore);
        if (decodedStore is Map) {
          dynamic perScheda = decodedStore[_schedaWeekHistoryKey];
          final usingLegacyKey = perScheda == null;
          perScheda ??= decodedStore[_legacySchedaWeekHistoryKey];
          if (perScheda is Map) {
            _weekSnapshots.clear();
            for (final entry in perScheda.entries) {
              final k = int.tryParse(entry.key.toString());
              if (k == null) continue;
              final v = entry.value;
              if (v is Map) {
                _weekSnapshots[k] = Map<String, dynamic>.from(v);
              }
            }
            if (kDebugMode) {
              debugPrint('[WEEK] caricati snapshot da store: key=$_schedaWeekHistoryKey weeks=${_weekSnapshots.keys.toList()..sort()} legacyFallback=$usingLegacyKey');
            }

            if (usingLegacyKey) {
              final migrated = Map<String, dynamic>.from(decodedStore);
              migrated[_schedaWeekHistoryKey] =
                  _weekSnapshots.map((k, v) => MapEntry(k.toString(), v));
              migrated.remove(_legacySchedaWeekHistoryKey);
              await prefs.setString(_weekHistoryStoreKey, jsonEncode(migrated));
            }
          }
        }
      }

      // Populate _weekSnapshots from embedded eserciziPerSettimana for any
      // weeks not already covered by the history store. This ensures all weeks
      // are visible as chips even if the history store is empty or partial.
      final baseJson = <String, dynamic>{
        'id': widget.scheda.id,
        'nome': widget.scheda.nome,
        'livello': widget.scheda.livello,
        'categoria': widget.scheda.categoria,
        'continuativa': widget.scheda.continuativa,
      };
      for (final entry in widget.scheda.eserciziPerSettimana.entries) {
        if (_weekSnapshots.containsKey(entry.key)) continue;
        _weekSnapshots[entry.key] = {
          ...baseJson,
          'settimanaCorrente': entry.key,
          'esercizi': entry.value.map((e) => e.toJson()).toList(),
        };
      }

      String? bozzaJson = prefs.getString(_bozzaKey);
      final usingLegacyBozzaKey = bozzaJson == null;
      bozzaJson ??= prefs.getString(_legacyBozzaKeyByName);

      if (usingLegacyBozzaKey && bozzaJson != null) {
        await prefs.setString(_bozzaKey, bozzaJson);
        await prefs.remove(_legacyBozzaKeyByName);
      }

      if (bozzaJson == null || !mounted) {
        if (kDebugMode) {
          debugPrint('[WEEK] nessuna bozza trovata per key=$_bozzaKey, rimango su W${widget.scheda.settimanaCorrente}');
        }
        // No bozza: stay on the saved settimanaCorrente so the card and the
        // detail screen always show the same week.  The week chips are already
        // all visible (populated above from eserciziPerSettimana).
        _snapshotCurrentWeek();
        return;
      }

      final decoded = jsonDecode(bozzaJson);
      if (decoded is! Map<String, dynamic>) return;

      final uiRaw = decoded['ui'];
      if (uiRaw is Map) {
        _compactMode = uiRaw['compactMode'] == true;
        _showOnlyIncomplete = uiRaw['showOnlyIncomplete'] == true;
      }

      final historyRaw = decoded['weekHistory'];
      if (historyRaw is Map) {
        for (final entry in historyRaw.entries) {
          final k = int.tryParse(entry.key.toString());
          if (k == null) continue;
          final v = entry.value;
          if (v is Map) {
            _weekSnapshots[k] = Map<String, dynamic>.from(v);
          }
        }
      }

      final schedaMap = decoded['scheda'];
      if (schedaMap is! Map) return;

      final bozza = Scheda.fromJson(Map<String, dynamic>.from(schedaMap));
      setState(() {
        widget.scheda.nome = bozza.nome;
        widget.scheda.livello = bozza.livello;
        widget.scheda.categoria = bozza.categoria;
        widget.scheda.continuativa = bozza.continuativa;
        widget.scheda.settimanaCorrente = bozza.settimanaCorrente;
        widget.scheda.esercizi = bozza.esercizi;
      });

      if (_weekSnapshots.isNotEmpty) {
        final latestWeek = _weekSnapshots.keys.reduce(max);
        if (latestWeek > widget.scheda.settimanaCorrente) {
          if (kDebugMode) {
            debugPrint('[WEEK] bozza piu vecchia di store: bozza=${widget.scheda.settimanaCorrente}, storeLatest=$latestWeek');
          }
          _applySnapshotForWeek(latestWeek);
        }
      }

      _snapshotCurrentWeek();
    } catch (e) {
      debugPrint('Errore caricamento bozza workout: $e');
    }
  }

  Future<void> _salvaBozzaWorkout() async {
    try {
      _snapshotCurrentWeek();
      final prefs = await SharedPreferences.getInstance();

      final existingRaw = prefs.getString(_weekHistoryStoreKey);
      final weekStore = <String, dynamic>{};
      if (existingRaw != null) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is Map<String, dynamic>) {
          weekStore.addAll(decoded);
        } else if (decoded is Map) {
          weekStore.addAll(Map<String, dynamic>.from(decoded));
        }
      }
      weekStore[_schedaWeekHistoryKey] =
          _weekSnapshots.map((k, v) => MapEntry(k.toString(), v));
      await prefs.setString(_weekHistoryStoreKey, jsonEncode(weekStore));

      await prefs.setString(
        _bozzaKey,
        jsonEncode({
          'scheda': widget.scheda.toJson(),
          'weekHistory': _weekSnapshots.map((k, v) => MapEntry(k.toString(), v)),
          'ui': {
            'compactMode': _compactMode,
            'showOnlyIncomplete': _showOnlyIncomplete,
          },
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Errore salvataggio bozza workout: $e');
    }
  }

  Future<void> _pulisciBozzaWorkout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bozzaKey);
    } catch (e) {
      debugPrint('Errore pulizia bozza workout: $e');
    }
  }

  List<int> _sortedWeekTimeline() {
    final weeks = <int>{
      widget.scheda.settimanaCorrente,
      ..._weekSnapshots.keys,
      ...widget.scheda.eserciziPerSettimana.keys,
    }.toList()
      ..sort();
    if (kDebugMode) {
      debugPrint('[TIMELINE] "${widget.scheda.nome}" settimanaCorrente=${widget.scheda.settimanaCorrente} eperSett.keys=${widget.scheda.eserciziPerSettimana.keys.toList()..sort()} snapshots=${_weekSnapshots.keys.toList()..sort()} result=$weeks');
    }
    return weeks;
  }

  Map<String, int> _statsFromScheda(Scheda source) {
    final totalExercises = source.esercizi.length;
    final totalSeries = source.esercizi.fold<int>(
      0,
      (total, e) => total + e.serieAttive.where((s) => s.tipo != 'Avvicinamento').length,
    );
    final completedSeries = source.esercizi.fold<int>(
      0,
      (total, e) => total + e.serieAttive.where((s) => s.tipo != 'Avvicinamento' && s.isCompletata).length,
    );

    return {
      'exercises': totalExercises,
      'totalSeries': totalSeries,
      'completedSeries': completedSeries,
    };
  }

  Map<String, int> _statsForWeek(int week) {
    if (week == widget.scheda.settimanaCorrente) {
      return _statsFromScheda(widget.scheda);
    }

    var raw = _weekSnapshots[week];
    if (raw == null) {
      final embeddedEsercizi = widget.scheda.eserciziPerSettimana[week];
      if (embeddedEsercizi == null) {
        return {
          'exercises': 0,
          'totalSeries': 0,
          'completedSeries': 0,
        };
      }
      final weekJson = Map<String, dynamic>.from(widget.scheda.toJson());
      weekJson['settimanaCorrente'] = week;
      weekJson['esercizi'] = embeddedEsercizi.map((e) => e.toJson()).toList();
      raw = weekJson;
    }

    try {
      final scheda = Scheda.fromJson(Map<String, dynamic>.from(raw));
      return _statsFromScheda(scheda);
    } catch (_) {
      return {
        'exercises': 0,
        'totalSeries': 0,
        'completedSeries': 0,
      };
    }
  }

  Future<void> _vaiASettimana(int week) async {
    if (week == widget.scheda.settimanaCorrente) return;

    _snapshotCurrentWeek();
    final restored = _applySnapshotForWeek(week);
    if (!restored) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nessun dato salvato per la settimana $week.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _scheduleBozzaSave();
  }

  Future<void> _caricaDatabase() async {
    try {
      final dati = await ApiEsercizi.ottieniEserciziTradotti();
      if (mounted) {
        setState(() {
          _databaseEsercizi = dati;
        });
      }
    } catch (e) {
      debugPrint('Errore caricamento database esercizi: $e');
    }
  }

  String _normalizzaTesto(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _big3Key(String nome) {
    final n = _normalizzaTesto(_traduciNome(nome));
    final isPancaBilancierePresaMedia = n.contains('panca') && n.contains('bilanciere') && n.contains('presa media');
    final isSquatCompletoBilanciere = n.contains('squat') && n.contains('completo') && n.contains('bilanciere');
    final isStaccoBilanciere = n.contains('stacco') && n.contains('bilanciere');
    final isStaccoConventional = n.contains('conventional') && n.contains('deadlift');
    if (n.contains('panca piana') || n.contains('bench press') || n == 'panca' || isPancaBilancierePresaMedia) return 'Panca Piana';
    if (n == 'squat' || n.contains('back squat') || isSquatCompletoBilanciere) return 'Squat';
    if (n.contains('stacco da terra') || n.contains('deadlift') || n == 'stacco' || isStaccoBilanciere || isStaccoConventional) return 'Stacco da Terra';
    return '';
  }

  List<String> _prAliasesForBig3(String canonicalDisplayName) {
    final n = _normalizzaTesto(canonicalDisplayName);
    if (n == 'panca piana') {
      return const [
        'Panca Piana',
        'Panca piana con bilanciere(presa media)',
        'Panca piana con bilanciere - presa media',
        'Panca piana con bilanciere (presa media)',
      ];
    }
    if (n == 'squat') {
      return const [
        'Squat',
        'Squat Completo con Bilanciere',
        'Squat completo con bilanciere',
      ];
    }
    if (n == 'stacco da terra') {
      return const [
        'Stacco da Terra',
        'Stacco da Terra con Bilanciere',
        'Stacco da terra con bilanciere',
      ];
    }
    return [canonicalDisplayName];
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value.toString().replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double? _parsePercentInput(String raw) {
    final cleaned = raw.replaceAll('%', '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  bool _isAlmostEqual(double a, double b, {double tolerance = 0.26}) {
    return (a - b).abs() <= tolerance;
  }

  double? _expectedKgForSerie(Esercizio esercizio, Serie serie) {
    if (esercizio.modalitaIntensita != 'percentuale') return null;
    final rm = esercizio.massimaleKg;
    if (rm == null || rm <= 0 || serie.tipo == 'Avvicinamento') return null;

    final perc = _parsePercentInput(serie.percentualeTarget) ?? esercizio.percentualeMassimale;
    if (perc == null || perc <= 0) return null;

    return WorkloadCalculator.calculateFromMaxAndPercentage(
      oneRepMax: rm,
      percentage: perc,
    );
  }

  double? _extractPercentFromText(String text) {
    final t = _normalizzaTesto(text);
    final patterns = <RegExp>[
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*%'),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*percento'),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*per\s*cento'),
      RegExp(r'al\s*(\d{1,3}(?:[\.,]\d+)?)\b'),
      RegExp(r'at\s*(\d{1,3}(?:[\.,]\d+)?)\b'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m == null) continue;
      final parsed = _toDoubleOrNull(m.group(1));
      if (parsed != null && parsed > 0 && parsed <= 110) return parsed;
    }
    return null;
  }

  double? _inferPercentuale(Esercizio esercizio) {
    final existing = esercizio.percentualeMassimale;
    if (existing != null && existing > 0) return existing;

    for (final s in esercizio.serieAttive.where((x) => x.tipo != 'Avvicinamento')) {
      final p = _toDoubleOrNull(s.percentualeTarget);
      if (p != null && p > 0 && p <= 110) return p;
    }

    final text = '${esercizio.ripetizioni} ${esercizio.note ?? ''}';
    return _extractPercentFromText(text);
  }

  double? _findPr(Map<String, double> prs, String exerciseName) {
    final key = _big3Key(exerciseName);
    if (key.isEmpty) return null;

    final normKey = _normalizzaTesto(key);
    for (final entry in prs.entries) {
      final k = _normalizzaTesto(entry.key);
      if (k == normKey || k.contains(normKey) || normKey.contains(k)) {
        return entry.value;
      }
    }
    return null;
  }

  Future<Map<String, double>> _caricaPrAtleta() async {
    final out = <String, double>{};
    final prefs = await SharedPreferences.getInstance();

    final local = prefs.getString('personal_records');
    if (local != null) {
      try {
        final decoded = jsonDecode(local);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is num) out[e.key.toString()] = v.toDouble();
          }
        }
      } catch (e) {
        debugPrint('PR locali corrotti/non validi: $e');
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final cloud = doc.data()?['personal_records'];
        if (cloud is Map) {
          for (final e in cloud.entries) {
            final v = e.value;
            if (v is num) out[e.key.toString()] = v.toDouble();
          }
        }
      } catch (e) {
        debugPrint('Caricamento PR cloud fallito: $e');
      }
    }

    return out;
  }

  Future<void> _applicaPrSuSchedaAperta() async {
    final prs = await _caricaPrAtleta();
    if (prs.isEmpty || !mounted) return;

    bool changed = false;

    setState(() {
      for (final es in widget.scheda.esercizi) {
        if (es.modalitaIntensita != 'percentuale') continue;

        if (es.massimaleKg == null || es.massimaleKg! <= 0) {
          es.massimaleKg = _findPr(prs, es.nome);
        }
        final perc = _inferPercentuale(es);
        if (es.percentualeMassimale == null && perc != null) {
          es.percentualeMassimale = perc;
          changed = true;
        }

        final rm = es.massimaleKg;
        final percFinale = es.percentualeMassimale;
        if (rm == null || rm <= 0 || percFinale == null || percFinale <= 0) continue;

        es.caricoTargetKg = WorkloadCalculator.calculateFromMaxAndPercentage(
          oneRepMax: rm,
          percentage: percFinale,
        );
        changed = true;

        for (final serie in es.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
          final percSerie = _toDoubleOrNull(serie.percentualeTarget) ?? percFinale;
          if (serie.percentualeTarget.trim().isEmpty) {
            serie.percentualeTarget = percSerie.toStringAsFixed(percSerie % 1 == 0 ? 0 : 1);
          }

          if (serie.peso.trim().isEmpty) {
            final carico = WorkloadCalculator.calculateFromMaxAndPercentage(
              oneRepMax: rm,
              percentage: percSerie,
            );
            serie.peso = carico.toStringAsFixed(1);
          }
        }
      }
    });

    if (changed) {
      _scheduleBozzaSave();
    }
  }

  Future<void> _impostaPrPersonale(Esercizio esercizio) async {
    final key = _big3Key(esercizio.nome);
    if (key.isEmpty) return;

    final controller = TextEditingController(
      text: esercizio.massimaleKg != null ? esercizio.massimaleKg!.toStringAsFixed(1) : '',
    );

    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Imposta PR per $key'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Massimale (kg)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salva')),
        ],
      ),
    );

    if (conferma != true) return;
    final value = double.tryParse(controller.text.replaceAll(',', '.').trim());
    if (value == null || value <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('personal_records');
    final records = <String, dynamic>{};
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        records.addAll(decoded);
      } else if (decoded is Map) {
        records.addAll(Map<String, dynamic>.from(decoded));
      }
    }
    for (final alias in _prAliasesForBig3(key)) {
      records[alias] = value;
    }
    await prefs.setString('personal_records', jsonEncode(records));

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'personal_records': records,
          'ultimo_aggiornamento_pr': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Salvataggio PR cloud fallito: $e');
      }
    }

    final perc = esercizio.percentualeMassimale ?? _inferPercentuale(esercizio);
    if (perc != null && perc > 0) {
      final caricoDefault = WorkloadCalculator.calculateFromMaxAndPercentage(
        oneRepMax: value,
        percentage: perc,
      );
      setState(() {
        esercizio.massimaleKg = value;
        esercizio.percentualeMassimale ??= perc;
        esercizio.caricoTargetKg = caricoDefault;
        for (final serie in esercizio.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
          final percSerie = double.tryParse(serie.percentualeTarget.replaceAll(',', '.'));
          final caricoSerie = WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: value,
            percentage: percSerie ?? perc,
          );
          if (serie.percentualeTarget.trim().isEmpty) {
            serie.percentualeTarget = (percSerie ?? perc).toStringAsFixed(((percSerie ?? perc) % 1 == 0) ? 0 : 1);
          }
          if (serie.peso.trim().isEmpty) serie.peso = caricoSerie.toStringAsFixed(1);
        }
      });
      _scheduleBozzaSave();
    }
  }

  String _macroTagDaCategoria(String categoria) {
    final c = _normalizzaTesto(categoria);

    if (c.contains('petto') || c.contains('pettoral')) return 'petto';
    if (c.contains('dorso') || c.contains('schiena') || c.contains('lombar') || c.contains('trapez') || c.contains('lat')) return 'schiena';
    if (c.contains('spall') || c.contains('deltoid')) return 'spalle';
    if (c.contains('bicip') || c.contains('tricip') || c.contains('avambr') || c.contains('bracci')) return 'braccia';
    if (c.contains('gambe') || c.contains('quadric') || c.contains('femoral') || c.contains('glute') || c.contains('polpacc') || c.contains('addutt') || c.contains('abdutt')) return 'gambe';
    if (c.contains('core') || c.contains('addom') || c.contains('obliqu')) return 'core';
    if (c.contains('total')) return 'total';
    return 'altro';
  }

  Set<String> _tagGruppiScheda() {
    final tag = <String>{};

    for (final esercizioScheda in widget.scheda.esercizi) {
      final nomeScheda = _normalizzaTesto(_traduciNome(esercizioScheda.nome));

      Map<String, dynamic>? match;
      for (final db in _databaseEsercizi) {
        final nomeDb = _normalizzaTesto((db['nome'] ?? '').toString());
        if (nomeDb == nomeScheda) {
          match = db;
          break;
        }
      }

      if (match != null) {
        tag.add(_macroTagDaCategoria((match['categoria'] ?? '').toString()));
      }
    }

    tag.remove('altro');
    return tag;
  }

  int _limiteStretching(Set<String> tagScheda) {
    final nomeScheda = _normalizzaTesto(widget.scheda.nome);
    final categoriaScheda = _normalizzaTesto(widget.scheda.categoria);
    final isFullBody = nomeScheda.contains('full body') ||
        nomeScheda.contains('total body') ||
        categoriaScheda.contains('full body') ||
        categoriaScheda.contains('total body') ||
        categoriaScheda.contains('total');

    if (isFullBody) return 6;
    if (tagScheda.length >= 4) return 7;
    if (tagScheda.length >= 2) return 8;
    return 6;
  }

  List<Map<String, dynamic>> _eserciziSoloStretching() {
    final tagScheda = _tagGruppiScheda();
    final limite = _limiteStretching(tagScheda);

    List<Map<String, dynamic>> risultati = _databaseEsercizi.where((es) => es['isStretching'] == true).toList();

    if (tagScheda.isNotEmpty) {
      risultati = risultati.where((es) {
        final tagStretching = _macroTagDaCategoria((es['categoria'] ?? '').toString());
        return tagScheda.contains(tagStretching) || tagStretching == 'total';
      }).toList();
    }

    if (risultati.isEmpty) {
      risultati = _databaseEsercizi.where((es) => es['isStretching'] == true).toList();
    }

    risultati.sort((a, b) => (a['nome'] ?? '').toString().compareTo((b['nome'] ?? '').toString()));
    return risultati.take(limite).toList();
  }

  Widget _buildSoloStretchingSection() {
    final stretching = _eserciziSoloStretching();
    final tagScheda = _tagGruppiScheda();
    final sottotitolo = tagScheda.isEmpty
        ? 'Esercizi dal database master Tiger'
        : 'Filtrati per gruppi muscolari scheda: ${tagScheda.join(', ')}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.self_improvement, color: Colors.lightBlueAccent),
        title: const Text(
          'Sezione informativa • Solo stretching',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(sottotitolo),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (stretching.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Nessun esercizio di stretching disponibile al momento.', style: TextStyle(color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stretching.length,
                itemBuilder: (context, i) {
                  final es = stretching[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.fitness_center, size: 18, color: Colors.lightBlueAccent),
                    title: Text(es['nome'] ?? 'Stretching'),
                    trailing: const Icon(Icons.info_outline, color: Colors.grey, size: 18),
                    onTap: () => _mostraDettagliEsercizio(es),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // 👇 MOTORE DI TRADUZIONE BLINDATO (Ignora maiuscole/minuscole)
  String _traduciNome(String nomeOriginale) {
    String lower = nomeOriginale.toLowerCase().trim();
    
    for (var entry in DizionarioEsercizi.daIngleseAItaliano.entries) {
      if (entry.key.toLowerCase().trim() == lower || entry.value.toLowerCase().trim() == lower) {
        return entry.value; 
      }
    }
    return nomeOriginale;
  }

  // 👇 SALVATAGGIO CON NOTE
  Future<void> _salvaAllenamentoIbrido(String noteFineAllenamento) async {
    final nuovoAllenamento = Allenamento(
      data: DateTime.now(),
      scheda: widget.scheda,
      note: noteFineAllenamento.isNotEmpty ? noteFineAllenamento : null, 
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storicoJson = prefs.getString('storico_salvato');
      List<dynamic> listaLocale = storicoJson != null ? jsonDecode(storicoJson) : [];
      
      listaLocale.add(nuovoAllenamento.toJson());
      await prefs.setString('storico_salvato', jsonEncode(listaLocale));

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Map<String, dynamic> datiCloud = nuovoAllenamento.toJson();
        datiCloud['atletaId'] = user.uid;
        datiCloud['atletaEmail'] = user.email;
        final coachId = await _caricaCoachIdAtleta(user.uid);
        if (coachId != null && coachId.isNotEmpty) {
          datiCloud['coachId'] = coachId;
        }
        
        await FirebaseFirestore.instance.collection('storico_atleti').add(datiCloud);

        if (coachId != null && coachId.isNotEmpty) {
          try {
            await _athleteProgressService.saveProgressEntry(
              coachId: coachId,
              athleteId: user.uid,
              payload: datiCloud,
              sessionAt: nuovoAllenamento.data,
            );
          } catch (e) {
            debugPrint('Sync nuovo schema progress fallita: $e');
          }
        }
      }

      if (!mounted) return;
      await _pulisciBozzaWorkout();
      if (!mounted) return;
      Navigator.pop(context); 
      Navigator.pop(context, true); 

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allenamento completato e inviato! 🐯💪'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        )
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red)
      );
    }
  }

  Future<String?> _caricaCoachIdAtleta(String atletaId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(atletaId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      final coachId = data?['coachId']?.toString().trim() ?? '';
      return coachId.isEmpty ? null : coachId;
    } catch (e) {
      debugPrint('Impossibile leggere coachId atleta: $e');
      return null;
    }
  }

  Map<String, String>? _getDatiPrecedenti(String nomeEs, int indiceSerie) {
    String nomeTargetIta = _traduciNome(nomeEs).toLowerCase().trim();
    final storicoRecentePrima = List<Allenamento>.from(widget.storico)
      ..sort((a, b) => b.data.compareTo(a.data));

    for (var allenamento in storicoRecentePrima) {
      for (var es in allenamento.scheda.esercizi) {
        String nomeStoricoIta = _traduciNome(es.nome).toLowerCase().trim();
        if (nomeTargetIta == nomeStoricoIta && es.serieAttive.length > indiceSerie) {
          var seriePrecedente = es.serieAttive[indiceSerie];
          if (seriePrecedente.peso.isNotEmpty || seriePrecedente.ripetizioniFatte.isNotEmpty) {
            return {
              'peso': seriePrecedente.peso,
              'reps': seriePrecedente.ripetizioniFatte,
              'rpe': seriePrecedente.rpe,
            };
          }
        }
      }
    }
    return null;
  }

  int _estraiSecondi(String recupero) {
    String soloNumeri = recupero.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloNumeri.isEmpty) return 90; 
    return int.parse(soloNumeri);
  }

  void _avviaTimerRecupero(int secondi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecuperoTimerWidget(secondiTotali: secondi),
    );
  }

  void _mostraStoricoEsercizio(String nomeEs) {
    String nomeTargetIta = _traduciNome(nomeEs).toLowerCase().trim();
    List<Allenamento> storicoEs = [];
    final storicoRecentePrima = List<Allenamento>.from(widget.storico)
      ..sort((a, b) => b.data.compareTo(a.data));
    
    for (var allenamento in storicoRecentePrima) {
      if (allenamento.scheda.esercizi.any((e) => _traduciNome(e.nome).toLowerCase().trim() == nomeTargetIta)) {
        storicoEs.add(allenamento);
        if (storicoEs.length >= 5) break; 
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Storico Recente: $nomeEs', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              storicoEs.isEmpty 
                ? const Text('Nessun dato precedente trovato per questo esercizio.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))
                : Expanded(
                    child: ListView.builder(
                      itemCount: storicoEs.length,
                      itemBuilder: (context, i) {
                        var all = storicoEs[i];
                        final esOrNull = all.scheda.esercizi.where((e) => _traduciNome(e.nome).toLowerCase().trim() == nomeTargetIta).firstOrNull;
                        if (esOrNull == null) return const SizedBox.shrink();
                        var es = esOrNull;
                        
                        String dataStr = '${all.data.day}/${all.data.month}/${all.data.year}';
                        return Card(
                          color: Colors.black12,
                          child: ExpansionTile(
                            title: Text(dataStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                            children: es.serieAttive.map((s) {
                              if (!s.isCompletata || s.peso.isEmpty) return const SizedBox.shrink();
                              return ListTile(
                                dense: true,
                                title: Text('${s.peso} kg x ${s.ripetizioniFatte} reps', style: const TextStyle(color: Colors.green)),
                                trailing: s.rpe.isNotEmpty ? Text('RPE: ${s.rpe}', style: const TextStyle(color: Colors.grey)) : null,
                              );
                            }).toList(),
                          ),
                        );
                      }
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  void _mostraAlternative(String nomeEsercizioAttuale, String categoria) {
    List<Map<String, dynamic>> alternative = _databaseEsercizi.where((es) => 
      es['categoria'] == categoria && es['nome'] != nomeEsercizioAttuale
    ).toList();

    alternative.shuffle(Random());
    List<Map<String, dynamic>> treAlternative = alternative.take(3).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, color: Colors.blueAccent, size: 28),
                  SizedBox(width: 8),
                  Text('Attrezzo Occupato?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Alternative per: $categoria', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              if (treAlternative.isEmpty)
                const Text('Nessun esercizio alternativo suggerito.', textAlign: TextAlign.center)
              else
                Column(
                  children: treAlternative.map((alt) => Card(
                    color: Colors.black12,
                    child: ListTile(
                      leading: const Icon(Icons.fitness_center, color: Colors.blueAccent),
                      title: Text(alt['nome'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.info_outline, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(context);
                        _mostraDettagliEsercizio(alt); 
                      },
                    ),
                  )).toList(),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _mostraDettagliEsercizio(Map<String, dynamic> esercizio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(esercizio['nome'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (esercizio['video'] != null && esercizio['video'].toString().isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: Colors.white,
                          child: Image.network(
                            esercizio['video'], height: 160, fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const SizedBox(height: 160, child: Center(child: Icon(Icons.videocam_off, color: Colors.grey))),
                          ),
                        ),
                      ),
                    ),
                    if (esercizio['video2'] != null && esercizio['video2'].toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            color: Colors.white,
                            child: Image.network(
                              esercizio['video2'], height: 160, fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const SizedBox(height: 160, child: Center(child: Icon(Icons.videocam_off, color: Colors.grey))),
                            ),
                          ),
                        ),
                      ),
                    ]
                  ],
                ),
              const SizedBox(height: 20),
              if (esercizio['note'] != null && esercizio['note'].toString().isNotEmpty) ...[
                const Text('Esecuzione:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(child: Text(esercizio['note'], style: const TextStyle(color: Colors.white70, fontSize: 16))),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => Navigator.pop(context), 
                child: const Text('Chiudi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _apriCalcolatoreDischi() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => const PlateCalculatorWidget(),
    );
  }

  Future<void> _vaiSettimanaPrecedente() async {
    if (widget.scheda.settimanaCorrente <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sei gia alla settimana 1.'),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    _snapshotCurrentWeek();
    final targetWeek = widget.scheda.settimanaCorrente - 1;
    final restored = _applySnapshotForWeek(targetWeek);
    if (!restored) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun dato salvato per la settimana precedente.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _scheduleBozzaSave();
  }

  Future<void> _sincronizzaWeekHistorySuCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_weekHistoryStoreKey);
      Map<String, dynamic> decoded = {};
      if (raw != null && raw.trim().isNotEmpty) {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          decoded = json;
        } else if (json is Map) {
          decoded = Map<String, dynamic>.from(json);
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'app_state': {
          'week_history_store': decoded,
          'updated_at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Errore sync week history cloud: $e');
    }
  }

  Future<void> _eliminaSettimana(int week) async {
    _snapshotCurrentWeek();
    if (!_weekSnapshots.containsKey(week)) return;

    setState(() {
      _weekSnapshots.remove(week);
    });

    if (_weekSnapshots.isEmpty) {
      // Keep at least current live state as week 1 baseline.
      setState(() {
        widget.scheda.settimanaCorrente = 1;
      });
      _snapshotCurrentWeek();
    } else if (widget.scheda.settimanaCorrente == week) {
      final sorted = _weekSnapshots.keys.toList()..sort();
      final prevCandidates = sorted.where((k) => k < week).toList();
      final target = prevCandidates.isNotEmpty ? prevCandidates.last : sorted.first;
      _applySnapshotForWeek(target);
    }

    await _salvaBozzaWorkout();
    await _sincronizzaWeekHistorySuCloud();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Settimana $week eliminata.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _apriGestioneSettimane() async {
    _snapshotCurrentWeek();
    final weeks = _sortedWeekTimeline();

    if (weeks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna settimana salvata.'), backgroundColor: Colors.grey),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Timeline settimane', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Tocca una settimana per aprirla o gestiscila da qui'),
              ),
              ...weeks.map((w) {
                final isCurrent = w == widget.scheda.settimanaCorrente;
                final stats = _statsForWeek(w);
                final completed = stats['completedSeries'] ?? 0;
                final total = stats['totalSeries'] ?? 0;
                final exercises = stats['exercises'] ?? 0;

                return ListTile(
                  onTap: () async {
                    Navigator.pop(context);
                    await _vaiASettimana(w);
                  },
                  leading: Icon(
                    isCurrent ? Icons.play_circle_fill : Icons.calendar_month,
                    color: isCurrent ? Colors.greenAccent : Colors.white70,
                  ),
                  title: Text('Settimana $w${isCurrent ? ' (corrente)' : ''}'),
                  subtitle: Text('$exercises esercizi • $completed/$total serie completate'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrent)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.star, color: Colors.amber, size: 18),
                        ),
                      IconButton(
                        tooltip: 'Elimina settimana $w',
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onPressed: () async {
                          Navigator.pop(context);
                          final confirmed = await showDialog<bool>(
                            context: this.context,
                            builder: (context) => AlertDialog(
                              title: const Text('Elimina settimana'),
                              content: Text('Confermi eliminazione della settimana $w? L\'azione sincronizza anche il cloud.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Elimina'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _eliminaSettimana(w);
                          }
                        },
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSchedaHeaderCompatto() {
    final stats = _statsFromScheda(widget.scheda);
    final totalSeries = stats['totalSeries'] ?? 0;
    final completedSeries = stats['completedSeries'] ?? 0;
    final completionRatio = totalSeries == 0 ? 0.0 : completedSeries / totalSeries;
    final weeks = _sortedWeekTimeline();
    final canGoBack = widget.scheda.settimanaCorrente > 1;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed strip (always visible) ──────────────
          InkWell(
            onTap: () => setState(() => _headerExpanded = !_headerExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D2A0D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'W${widget.scheda.settimanaCorrente}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: completionRatio,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(completionRatio * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _headerExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: const Color(0xFF555555),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ───────────────────────────────
          if (_headerExpanded) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Navigation buttons
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: canGoBack ? _vaiSettimanaPrecedente : null,
                        icon: const Icon(Icons.chevron_left, size: 16),
                        label: const Text('Prec.'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _vaiSettimanaSuccessiva,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B1A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.trending_up, size: 16),
                          label: Text('Pianifica W${widget.scheda.settimanaCorrente + 1}'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Timeline settimane',
                        onPressed: _apriGestioneSettimane,
                        icon: const Icon(Icons.view_timeline, color: Color(0xFFFFB347), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Week chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: weeks.map((w) {
                        final isCurrent = w == widget.scheda.settimanaCorrente;
                        final hasSnapshot = _weekSnapshots.containsKey(w) ||
                            widget.scheda.eserciziPerSettimana.containsKey(w) ||
                            isCurrent;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('W$w', style: const TextStyle(fontSize: 12)),
                            selected: isCurrent,
                            selectedColor: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                            backgroundColor: Colors.white.withValues(alpha: 0.04),
                            side: BorderSide(
                              color: isCurrent
                                  ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                            onSelected: hasSnapshot ? (_) => _vaiASettimana(w) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Filter/action chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('Solo incompleti', style: TextStyle(fontSize: 12)),
                        selected: _showOnlyIncomplete,
                        onSelected: (_) => setState(() => _showOnlyIncomplete = !_showOnlyIncomplete),
                        avatar: Icon(
                          _showOnlyIncomplete ? Icons.filter_alt : Icons.filter_alt_outlined,
                          size: 14,
                          color: _showOnlyIncomplete ? Colors.amber : Colors.white54,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      FilterChip(
                        label: const Text('Compatta', style: TextStyle(fontSize: 12)),
                        selected: _compactMode,
                        onSelected: (_) => setState(() => _compactMode = !_compactMode),
                        avatar: Icon(
                          _compactMode ? Icons.view_agenda : Icons.view_stream,
                          size: 14,
                          color: _compactMode ? const Color(0xFF6BB5E8) : Colors.white54,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      ActionChip(
                        label: const Text('Dischi', style: TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.calculate, size: 14),
                        onPressed: _apriCalcolatoreDischi,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      ActionChip(
                        label: const Text('+ Esercizio', style: TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.add, size: 14),
                        onPressed: () async {
                          final nuovo = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaEsercizioScreen()));
                          if (nuovo != null) {
                            setState(() => widget.scheda.esercizi.add(nuovo));
                            _scheduleBozzaSave();
                          }
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildSchedaHeaderCompatto(),
          _buildSoloStretchingSection(),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.only(bottom: 100),
              onReorder: (int oldIndex, int newIndex) {
                if (_showOnlyIncomplete) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Disattiva il filtro "solo incompleti" per riordinare la scheda.'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final esercizio = widget.scheda.esercizi.removeAt(oldIndex);
                  widget.scheda.esercizi.insert(newIndex, esercizio);
                });
                _scheduleBozzaSave();
              },
              children: [
                for (int i = 0; i < widget.scheda.esercizi.length; i++)
                  if (!_showOnlyIncomplete ||
                      widget.scheda.esercizi[i].serieAttive.any((s) => !s.isCompletata && s.tipo != 'Avvicinamento'))
                    _buildEsercizioItem(widget.scheda.esercizi[i], i),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.flag, color: Colors.white),
        label: const Text('Termina Allenamento', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: () async {
          TextEditingController noteAllenamentoController = TextEditingController();
          
          bool? conferma = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [Icon(Icons.emoji_events, color: Colors.amber, size: 28), SizedBox(width: 10), Text('Ottimo Lavoro!')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Salverai lo storico per te e per il tuo Coach.', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteAllenamentoController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Note a fine sessione (Opzionale)',
                      hintText: 'Es: Ottime sensazioni, stanco sul finale...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.black12,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), 
                  onPressed: () => Navigator.pop(context, true), 
                  child: const Text('Sì, Salva')
                ),
              ],
            ),
          );
          
          if (conferma == true) {
            _salvaAllenamentoIbrido(noteAllenamentoController.text.trim());
          }
        },
      ),
    );
  }

  Widget _buildEsercizioItem(Esercizio esercizio, int index) {
    bool tuttoFatto = esercizio.serieAttive.isNotEmpty && esercizio.serieAttive.every((Serie s) => s.isCompletata);
    final isCollapsed = _isExerciseCollapsed(esercizio, index);
    
    bool isSuperSet = esercizio.tecniche.any((t) => t.toLowerCase().contains('super'));
    bool prevIsSuperSet = index > 0 && widget.scheda.esercizi[index - 1].tecniche.any((t) => t.toLowerCase().contains('super'));
    bool nextIsSuperSet = index < widget.scheda.esercizi.length - 1 && widget.scheda.esercizi[index + 1].tecniche.any((t) => t.toLowerCase().contains('super'));

    // Ricerca nel database: prima esatta, poi token-based per nomi parziali/brevi
    final nomeTargetNorm = _normalizzaTesto(_traduciNome(esercizio.nome));
    final nomeOriginaleNorm = _normalizzaTesto(esercizio.nome);
    final matchDb = _databaseEsercizi.cast<Map<String, dynamic>?>().firstWhere(
      (e) {
        if (e == null) return false;
        final dbNorm = _normalizzaTesto(e['nome'].toString());

        // 1. Match esatto dopo normalizzazione
        if (dbNorm == nomeTargetNorm || dbNorm == nomeOriginaleNorm) return true;

        // 2. Token match: tutti i token significativi del target sono nel DB
        //    es. "squat" (1 token) matcha "squat completo con bilanciere"
        final targetTokens = nomeTargetNorm.split(' ').where((t) => t.length >= 4).toList();
        final origTokens = nomeOriginaleNorm.split(' ').where((t) => t.length >= 4).toList();
        if (targetTokens.isNotEmpty && targetTokens.every((t) => dbNorm.contains(t))) return true;
        if (origTokens.isNotEmpty && origTokens.every((t) => dbNorm.contains(t))) return true;

        // 3. DB name è substring del target (es. "panca piana" matcha "panca piana con bilanciere presa media")
        final dbTokens = dbNorm.split(' ').where((t) => t.length >= 4).toList();
        if (dbTokens.length <= 3 && dbTokens.every((t) => nomeTargetNorm.contains(t))) return true;

        return false;
      },
      orElse: () => null,
    );

    return Column(
      key: ValueKey('col_${esercizio.nome}_$index'), 
      children: [
        if (isSuperSet && prevIsSuperSet)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 32),
            color: Colors.white.withValues(alpha: 0.05),
          ),

        Dismissible(
          key: ValueKey('dismiss_${esercizio.nome}_$index'),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete, color: Colors.white)),
          confirmDismiss: (direction) async {
            final bool? confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Elimina esercizio'),
                content: Text('Sei sicuro di voler eliminare "${esercizio.nome}"? Questa azione è irreversibile.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annulla'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sì, elimina'),
                  ),
                ],
              ),
            );
            return confirmed == true;
          },
          onDismissed: (direction) { setState(() { widget.scheda.esercizi.removeAt(index); }); _scheduleBozzaSave(); },
          onUpdate: (details) {
            if (details.reached) {
              _scheduleBozzaSave();
            }
          },
          child: Card(
            margin: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: (isSuperSet && prevIsSuperSet) ? 0 : 8, 
              bottom: (isSuperSet && nextIsSuperSet) ? 0 : 8
            ),
            color: isSuperSet ? const Color(0xFF24202A) : const Color(0xFF1E1E1E),
            elevation: isSuperSet ? 0 : 1, 
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular((isSuperSet && prevIsSuperSet) ? 0 : 16),
                bottom: Radius.circular((isSuperSet && nextIsSuperSet) ? 0 : 16),
              ),
              side: BorderSide.none, 
            ),
            child: Padding(
              padding: EdgeInsets.all(_compactMode ? 9.0 : 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.drag_indicator, color: Colors.grey, size: _compactMode ? 18 : 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(esercizio.nome, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _compactMode ? 14 : 16, color: tuttoFatto ? Colors.green : Colors.white))),
                      if (matchDb != null)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill, color: Colors.deepOrange, size: 24),
                          tooltip: 'Dettagli tecnica',
                          onPressed: () => _mostraDettagliEsercizio(matchDb),
                        ),
                      IconButton(icon: const Icon(Icons.edit, color: Colors.lightBlueAccent, size: 20), onPressed: () async {
                        final mod = await Navigator.push(context, MaterialPageRoute(builder: (c) => CreaEsercizioScreen(esercizioDaModificare: esercizio)));
                        if (mod != null) {
                          setState(() => widget.scheda.esercizi[index] = mod);
                          _scheduleBozzaSave();
                        }
                      }),
                      if (matchDb != null)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                          onSelected: (value) {
                            if (value == 'alt') {
                              _mostraAlternative(esercizio.nome, matchDb['categoria']);
                            }
                            if (value == 'det') {
                              _mostraDettagliEsercizio(matchDb);
                            }
                            if (value == 'sto') {
                              _mostraStoricoEsercizio(esercizio.nome);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'alt', child: Text('Alternative')), 
                            PopupMenuItem(value: 'det', child: Text('Dettagli tecnica')),
                            PopupMenuItem(value: 'sto', child: Text('Cronologia esercizio')),
                          ],
                        ),
                      IconButton(
                        icon: Icon(
                          isCollapsed ? Icons.expand_more : Icons.expand_less,
                          color: Colors.white70,
                          size: 20,
                        ),
                        tooltip: isCollapsed ? 'Espandi' : 'Comprimi',
                        onPressed: () => _toggleExerciseCollapsed(esercizio, index),
                      ),
                    ],
                  ),

                  if (!isCollapsed) ...[
                  
                  if (esercizio.tecniche.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: esercizio.tecniche.map((t) {
                        
                        // Nascondi tag inutile
                        if (t.toLowerCase() == 'classico') return const SizedBox.shrink();

                        // Colora tag speciali
                        bool isMono = t.toLowerCase().contains('mono') || t.toLowerCase().contains('unilaterale');
                        Color coloreTag = isMono ? Colors.cyanAccent : Colors.deepOrange; 
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: coloreTag.withValues(alpha: 0.15), 
                            borderRadius: BorderRadius.circular(4), 
                            border: Border.all(color: coloreTag.withValues(alpha: 0.5))
                          ),
                          child: Text(t.toUpperCase(), style: TextStyle(color: coloreTag, fontSize: 9, fontWeight: FontWeight.bold)),
                        );
                      }).toList(),
                    ),
                  Text('Obiettivo: ${esercizio.ripetizioni} | Rec: ${esercizio.recupero}s', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  if (esercizio.modalitaIntensita == 'rir')
                    Text(
                      'Intensita: RIR ${esercizio.rirTarget ?? '-'}',
                      style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Intensita: ${esercizio.percentualeMassimale?.toStringAsFixed(1) ?? '-'}% '
                          'di ${esercizio.massimaleKg?.toStringAsFixed(1) ?? '-'}kg '
                          '(target ${esercizio.caricoTargetKg?.toStringAsFixed(1) ?? '-'}kg)',
                          style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                        ),
                        if (esercizio.massimaleKg == null)
                          TextButton.icon(
                            onPressed: () => _impostaPrPersonale(esercizio),
                            icon: const Icon(Icons.fitness_center, size: 16),
                            label: const Text('Imposta il tuo PR per calcolare i carichi'),
                          ),
                      ],
                    ),
                  
                  if (esercizio.note != null && esercizio.note!.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        border: const Border(left: BorderSide(color: Colors.amber, width: 3)),
                        borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                      ),
                      child: Text('📝 ${esercizio.note}', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontStyle: FontStyle.italic)),
                    ),

                  const Divider(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: const [
                        SizedBox(width: 30, child: Text('#', style: TextStyle(color: Colors.white38, fontSize: 11))),
                        Expanded(flex: 3, child: Text('Kg', style: TextStyle(color: Colors.white38, fontSize: 11))),
                        Expanded(flex: 3, child: Text('Reps', style: TextStyle(color: Colors.white38, fontSize: 11))),
                        Expanded(flex: 2, child: Text('RPE / %', style: TextStyle(color: Colors.white38, fontSize: 11))),
                        SizedBox(width: 42),
                      ],
                    ),
                  ),
                  ...esercizio.serieAttive.asMap().entries.map((entry) {
                    int sIdx = entry.key;
                    Serie serie = entry.value;
                    final prev = _getDatiPrecedenti(esercizio.nome, sIdx);
                    final expectedKg = _expectedKgForSerie(esercizio, serie);
                    final expectedPerc = _parsePercentInput(serie.percentualeTarget) ?? esercizio.percentualeMassimale;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: serie.isCompletata ? Colors.green.withValues(alpha: 0.1) : Colors.black12, borderRadius: BorderRadius.circular(6)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(width: 30, child: Text('${sIdx + 1}º', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                              Expanded(flex: 3, child: TextFormField(
                                key: ValueKey('peso_${widget.scheda.settimanaCorrente}_${esercizio.nome}_$sIdx'),
                                initialValue: serie.peso,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: expectedKg != null
                                      ? '${expectedKg.toStringAsFixed(1)}kg'
                                      : (prev != null ? '${prev['peso']}kg' : 'Kg'),
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                ),
                                onChanged: (v) {
                                  serie.peso = v;
                                  _scheduleBozzaSave();
                                },
                              )),
                              Expanded(flex: 3, child: TextFormField(
                                key: ValueKey('reps_${widget.scheda.settimanaCorrente}_${esercizio.nome}_$sIdx'),
                                initialValue: serie.ripetizioniFatte,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: prev != null ? '${prev['reps']}r' : 'Reps',
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                ),
                                onChanged: (v) {
                                  serie.ripetizioniFatte = v;
                                  _scheduleBozzaSave();
                                },
                              )),
                              Expanded(flex: 2, child: TextFormField(
                                key: ValueKey('int_${widget.scheda.settimanaCorrente}_${esercizio.nome}_$sIdx'),
                                initialValue: esercizio.modalitaIntensita == 'percentuale' ? serie.percentualeTarget : serie.rpe,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: esercizio.modalitaIntensita == 'percentuale' && serie.tipo != 'Avvicinamento'
                                      ? '% ${serie.percentualeTarget.isNotEmpty ? serie.percentualeTarget : (esercizio.percentualeMassimale?.toStringAsFixed(1) ?? '-')}'
                                      : (prev != null && prev['rpe'] != null ? 'RPE ${prev['rpe']}' : 'RPE'),
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                ),
                                style: const TextStyle(color: Colors.amber, fontSize: 14),
                                onChanged: (v) {
                                  if (esercizio.modalitaIntensita == 'percentuale') {
                                    final rm = esercizio.massimaleKg;
                                    final oldPerc = _parsePercentInput(serie.percentualeTarget) ?? esercizio.percentualeMassimale;
                                    final oldExpected = (rm != null && rm > 0 && oldPerc != null && oldPerc > 0 && serie.tipo != 'Avvicinamento')
                                        ? WorkloadCalculator.calculateFromMaxAndPercentage(oneRepMax: rm, percentage: oldPerc)
                                        : null;

                                    final parsed = _parsePercentInput(v);
                                    serie.percentualeTarget = parsed != null
                                        ? parsed.toStringAsFixed(parsed % 1 == 0 ? 0 : 1)
                                        : v.replaceAll('%', '').trim();

                                    if (rm != null && rm > 0 && parsed != null && parsed > 0 && serie.tipo != 'Avvicinamento') {
                                      final newExpected = WorkloadCalculator.calculateFromMaxAndPercentage(
                                        oneRepMax: rm,
                                        percentage: parsed,
                                      );
                                      final currentPeso = _toDoubleOrNull(serie.peso);
                                      final shouldAutoUpdatePeso = serie.peso.trim().isEmpty ||
                                          (oldExpected != null && currentPeso != null && _isAlmostEqual(currentPeso, oldExpected));

                                      if (shouldAutoUpdatePeso) {
                                        serie.peso = newExpected.toStringAsFixed(1);
                                      }
                                    }
                                  } else {
                                    serie.rpe = v;
                                  }
                                  _scheduleBozzaSave();
                                  setState(() {});
                                },
                              )),
                              IconButton(
                                icon: Icon(serie.isCompletata ? Icons.check_box : Icons.check_box_outline_blank, color: serie.isCompletata ? Colors.green : Colors.grey, size: 22),
                                onPressed: () async {
                                  setState(() { serie.isCompletata = !serie.isCompletata; });
                                  _scheduleBozzaSave();
                                  if (await Vibration.hasVibrator() == true) Vibration.vibrate(duration: 50, amplitude: 100);
                                  if (serie.isCompletata) _avviaTimerRecupero(_estraiSecondi(esercizio.recupero));
                                },
                              )
                            ],
                          ),
                          if (expectedKg != null && serie.tipo != 'Avvicinamento')
                            Padding(
                              padding: const EdgeInsets.only(left: 32, top: 2, bottom: 2),
                              child: Text(
                                'Expected: ${expectedKg.toStringAsFixed(1)} kg @ ${expectedPerc?.toStringAsFixed(expectedPerc % 1 == 0 ? 0 : 1) ?? '-'}%',
                                style: TextStyle(color: Colors.lightBlueAccent.withValues(alpha: 0.9), fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        'Card compatta: tocca per espandere serie e dettagli',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// WIDGET TIMER RECUPERO (CON ALLARME INFINITO)
// ============================================================================
class RecuperoTimerWidget extends StatefulWidget {
  final int secondiTotali;
  const RecuperoTimerWidget({super.key, required this.secondiTotali});
  @override
  State<RecuperoTimerWidget> createState() => _RecuperoTimerWidgetState();
}

class _RecuperoTimerWidgetState extends State<RecuperoTimerWidget> {
  late int _rimanenti;
  Timer? _t;
  Timer? _alarmTimer;
  late DateTime _fineTimer;

  @override
  void initState() {
    super.initState();
    _rimanenti = widget.secondiTotali;

    _fineTimer = DateTime.now().add(Duration(seconds: widget.secondiTotali));
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _aggiornaDaTempoReale());
    _aggiornaDaTempoReale();
  }

  void _aggiornaDaTempoReale() {
    final secondiRestanti = _fineTimer.difference(DateTime.now()).inSeconds;
    final nuoviRimanenti = secondiRestanti > 0 ? secondiRestanti : 0;

    if (!mounted) return;
    if (_rimanenti != nuoviRimanenti) {
      setState(() => _rimanenti = nuoviRimanenti);
    }

    if (_rimanenti == 0) {
      _t?.cancel();
      if (_alarmTimer == null || !_alarmTimer!.isActive) {
        _avviaSvegliaInfinita();
      }
    }
  }

  void _avviaSvegliaInfinita() async {
    Future<void> playCue() async {
      SystemSound.play(SystemSoundType.alert);
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(duration: 1000, amplitude: 255);
      }
    }

    await playCue();

    _alarmTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      playCue();
    });
  }

  @override
  void dispose() { 
    _t?.cancel(); 
    _alarmTimer?.cancel(); 
    Vibration.cancel();    
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    int m = _rimanenti ~/ 60; int s = _rimanenti % 60;
    bool isAllarme = _rimanenti == 0;

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(30), height: 280,
      child: Column(
        children: [
          Text(isAllarme ? 'SVEGLIA! TOCCA A TE!' : 'RECUPERO IN CORSO', 
            style: TextStyle(letterSpacing: 2, color: isAllarme ? Colors.redAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}', 
            style: TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: isAllarme ? Colors.redAccent : Colors.white)),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isAllarme ? Colors.redAccent : Colors.deepOrange, 
              minimumSize: const Size(double.infinity, 60), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () => Navigator.pop(context), 
            child: Text(isAllarme ? 'STOP E CHIUDI' : 'SALTA TIMER', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET CALCOLATORE DISCHI
// ============================================================================
class PlateCalculatorWidget extends StatefulWidget {
  const PlateCalculatorWidget({super.key});
  @override
  State<PlateCalculatorWidget> createState() => _PlateCalculatorWidgetState();
}

class _PlateCalculatorWidgetState extends State<PlateCalculatorWidget> {
  final TextEditingController _p = TextEditingController();
  double bil = 20.0;
  List<double> dischi = [];

  void _calc() {
    double tot = double.tryParse(_p.text.replaceAll(',', '.')) ?? 0;
    dischi.clear();
    if (tot <= bil) { setState(() {}); return; }
    double lato = (tot - bil) / 2;
    for (var d in [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]) {
      while (lato >= d) { dischi.add(d); lato -= d; }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PLATE CALCULATOR 🏋️', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 8),
          const Text('Peso da caricare per ogni lato del bilanciere', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(child: TextField(controller: _p, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso Totale (kg)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.fitness_center)), onChanged: (v) => _calc())),
              const SizedBox(width: 15),
              DropdownButton<double>(
                value: bil, 
                items: [20.0, 15.0, 10.0].map((e) => DropdownMenuItem(value: e, child: Text('Bil. ${e}kg'))).toList(), 
                onChanged: (v) { setState(() { bil = v!; _calc(); }); }
              ),
            ],
          ),
          const SizedBox(height: 30),
          if (dischi.isNotEmpty)
            Wrap(
              spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
              children: dischi.map((d) => Column(
                children: [
                  CircleAvatar(
                    radius: 25 + (d/2),
                    backgroundColor: d >= 20 ? Colors.red.shade900 : (d == 15 ? Colors.amber.shade800 : (d == 10 ? Colors.green.shade800 : Colors.grey.shade800)),
                    child: Text(d.toString().replaceAll('.0', ''), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 4),
                  Text('${d}kg', style: const TextStyle(fontSize: 10, color: Colors.grey))
                ],
              )).toList(),
            )
          else if (_p.text.isNotEmpty)
            const Text('Carica solo il bilanciere!', style: TextStyle(color: Colors.amber)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}