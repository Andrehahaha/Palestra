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

part 'dettaglio_scheda_screen_ui.dart';
part 'dettaglio_scheda_screen_widgets.dart';

// ============================================================================
// SCHERMATA DETTAGLIO ALLENAMENTO (CORE DELL'APP)
// ============================================================================
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

  String get _bozzaKey => 'workout_bozza_${widget.scheda.nome}';

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

  void _updateState(VoidCallback updater) {
    if (!mounted) return;
    setState(updater);
  }

  void _snapshotCurrentWeek() {
    _weekSnapshots[widget.scheda.settimanaCorrente] =
        Map<String, dynamic>.from(widget.scheda.toJson());
  }

  bool _applySnapshotForWeek(int week) {
    final raw = _weekSnapshots[week];
    if (raw == null) return false;

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

      final bozzaJson = prefs.getString(_bozzaKey);
      if (bozzaJson == null || !mounted) {
        if (kDebugMode) {
          debugPrint('[WEEK] nessuna bozza trovata per key=$_bozzaKey');
        }
        if (_weekSnapshots.isNotEmpty) {
          final latestWeek = _weekSnapshots.keys.reduce(max);
          if (kDebugMode) {
            debugPrint('[WEEK] ripristino da store settimana piu recente=$latestWeek');
          }
          _applySnapshotForWeek(latestWeek);
        }
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
      } catch (_) {}
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
      } catch (_) {}
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
                        var es = all.scheda.esercizi.firstWhere((e) => _traduciNome(e.nome).toLowerCase().trim() == nomeTargetIta);
                        
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
    final weeks = _weekSnapshots.keys.toList()..sort();

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
                title: Text('Gestione settimane', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Elimina una settimana salvata'),
              ),
              ...weeks.map((w) {
                final isCurrent = w == widget.scheda.settimanaCorrente;
                return ListTile(
                  leading: Icon(isCurrent ? Icons.play_arrow : Icons.calendar_today, color: isCurrent ? Colors.greenAccent : Colors.white70),
                  title: Text('Settimana $w${isCurrent ? ' (corrente)' : ''}'),
                  trailing: IconButton(
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
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildDettaglioSchedaScaffold(context);
  }
}
