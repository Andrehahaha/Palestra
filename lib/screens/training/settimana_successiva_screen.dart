
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../../models/esercizio.dart';
import '../../models/scheda.dart';
import '../../services/workload_calculator.dart';

double? _parseProgressionePercent(String raw) {
  final normalized = raw.replaceAll('%', '').replaceAll(',', '.').trim();
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

void applyProgressioneToExerciseForTest({
  required Esercizio exercise,
  double? massimaleInput,
  double? percentualeBaseInput,
  double incrementoPercentuale = 0,
  List<double?>? percentualiSerieOverride,
  bool forceRecalculateWeights = false,
  double? incrementoKg,
  String? rirInput,
}) {
  if (exercise.modalitaIntensita == 'percentuale') {
    final percentualeBase = percentualeBaseInput ?? exercise.percentualeMassimale;
    final percentualeFinale = (percentualeBase != null)
        ? (percentualeBase + incrementoPercentuale)
        : null;
    final massimale = massimaleInput ?? exercise.massimaleKg;

    if (massimale != null && massimale > 0) {
      exercise.massimaleKg = massimale;
    }
    if (percentualeFinale != null && percentualeFinale > 0) {
      exercise.percentualeMassimale = percentualeFinale;
    }

    if (massimale != null && percentualeFinale != null) {
      exercise.caricoTargetKg = WorkloadCalculator.calculateFromMaxAndPercentage(
        oneRepMax: massimale,
        percentage: percentualeFinale,
      );

      int serieIndex = 0;
      for (final serie in exercise.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
        final percSerieAttuale = _parseProgressionePercent(serie.percentualeTarget);
        final percOverride = (percentualiSerieOverride != null && serieIndex < percentualiSerieOverride.length)
            ? percentualiSerieOverride[serieIndex]
            : null;
        final percSerieBase = percOverride ?? percSerieAttuale ?? percentualeBase;
        if (percSerieBase == null || percSerieBase <= 0) continue;

        final percSerieNuova = percOverride ?? (percSerieBase + incrementoPercentuale);
        final caricoSerie = WorkloadCalculator.calculateFromMaxAndPercentage(
          oneRepMax: massimale,
          percentage: percSerieNuova,
        );

        final hadExplicitPercent = percSerieAttuale != null;
        final oldExpected = (percSerieAttuale != null && percSerieAttuale > 0)
            ? WorkloadCalculator.calculateFromMaxAndPercentage(
                oneRepMax: massimale,
                percentage: percSerieAttuale,
              )
            : null;
        final currentPeso = double.tryParse(serie.peso.replaceAll(',', '.').trim());
        final isPesoAutoDerived = oldExpected != null && currentPeso != null && (currentPeso - oldExpected).abs() < 0.11;
        final shouldUpdatePeso = serie.peso.trim().isEmpty ||
          forceRecalculateWeights ||
            incrementoPercentuale != 0 ||
            percOverride != null ||
            !hadExplicitPercent ||
            isPesoAutoDerived;

        serie.percentualeTarget = percSerieNuova.toStringAsFixed(percSerieNuova % 1 == 0 ? 0 : 1);
        if (shouldUpdatePeso) {
          serie.peso = caricoSerie.toStringAsFixed(1);
        }
        serieIndex += 1;
      }
    }
  } else {
    final rir = (rirInput ?? '').trim();
    exercise.rirTarget = rir.isEmpty ? null : rir;
  }

  if (incrementoPercentuale <= 0 && incrementoKg != null && incrementoKg > 0) {
    if (exercise.modalitaIntensita == 'percentuale' && exercise.massimaleKg != null && exercise.massimaleKg! > 0) {
      final rm = exercise.massimaleKg!;
      final percBase = exercise.percentualeMassimale;

      if (percBase != null && percBase > 0) {
        final nuovoTarget = WorkloadCalculator.calculateFromMaxAndPercentage(
              oneRepMax: rm,
              percentage: percBase,
            ) +
            incrementoKg;
        exercise.caricoTargetKg = nuovoTarget;
      }

      for (final serie in exercise.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
        final percSerie = _parseProgressionePercent(serie.percentualeTarget) ?? percBase;
        if (percSerie == null || percSerie <= 0) continue;

        final baseSerie = WorkloadCalculator.calculateFromMaxAndPercentage(
          oneRepMax: rm,
          percentage: percSerie,
        );
        serie.peso = (baseSerie + incrementoKg).toStringAsFixed(1);
      }
    } else {
      final base = exercise.caricoTargetKg;
      if (base != null) {
        final nuovoCarico = base + incrementoKg;
        exercise.caricoTargetKg = nuovoCarico;
        for (final serie in exercise.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
          serie.peso = nuovoCarico.toStringAsFixed(1);
        }
      }
    }
  }

  for (final serie in exercise.serieAttive) {
    serie.isCompletata = false;
  }
}

class SettimanaSuccessivaScreen extends StatefulWidget {
  final Scheda scheda;

  const SettimanaSuccessivaScreen({super.key, required this.scheda});

  @override
  State<SettimanaSuccessivaScreen> createState() => _SettimanaSuccessivaScreenState();
}

class _SettimanaSuccessivaScreenState extends State<SettimanaSuccessivaScreen> {
  late final List<_ProgressEditorState> _editors;
  bool _forceRecalculateWeights = false;
  static const String _prefsKeyForceRecalc = 'force_recalculate_weights_toggle';
  final TextEditingController _globalDeltaPercentController = TextEditingController();
  final TextEditingController _globalDeltaKgController = TextEditingController();
  final TextEditingController _globalRirController = TextEditingController();
  String _modalitaFiltro = 'tutte';

  @override
  void initState() {
    super.initState();
    _editors = widget.scheda.esercizi.map((esercizio) {
      return _ProgressEditorState.fromExercise(esercizio);
    }).toList();
    _caricaPreferenzaToggle();

  }

  Future<void> _caricaPreferenzaToggle() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool(_prefsKeyForceRecalc);
    if (val != null) {
      setState(() {
        _forceRecalculateWeights = val;
      });
    }
  }

  @override
  void dispose() {
    for (final editor in _editors) {
      editor.dispose();
    }
    _globalDeltaPercentController.dispose();
    _globalDeltaKgController.dispose();
    _globalRirController.dispose();
    super.dispose();
  }

  double? _toDouble(String raw) {
    final normalized = raw.replaceAll('%', '').replaceAll(',', '.').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String _formatPercent(double value) {
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  }

  String _formatKg(double value) {
    return value.toStringAsFixed(1);
  }

  List<double?> _parsePercentualiSerieInput(String raw, int length) {
    final clean = raw.trim();
    if (clean.isEmpty) return List<double?>.filled(length, null);

    final parts = clean
        .split(RegExp(r'[,;\-/\s]+'))
        .map((p) => p.replaceAll('%', '').replaceAll(',', '.').trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return List<double?>.generate(
      length,
      (i) => i < parts.length ? double.tryParse(parts[i]) : null,
    );
  }

  List<Map<String, String>> _buildSeriePreview(Esercizio esercizio, _ProgressEditorState editor) {
    final out = <Map<String, String>>[];
    if (esercizio.modalitaIntensita != 'percentuale') return out;

    final rm = _toDouble(editor.massimaleController.text) ?? esercizio.massimaleKg;
    if (rm == null || rm <= 0) return out;

    final baseInput = _toDouble(editor.percentualeController.text) ?? esercizio.percentualeMassimale;
    final delta = _toDouble(editor.incrementoPercentualeController.text) ?? 0;
    if (baseInput == null || baseInput <= 0) return out;

    final workCount = esercizio.serieAttive.where((s) => s.tipo != 'Avvicinamento').length;
    final overrideSerie = _parsePercentualiSerieInput(editor.percentualiSerieController.text, workCount);

    int idx = 1;
    for (final serie in esercizio.serieAttive.where((s) => s.tipo != 'Avvicinamento')) {
      final currentIndex = idx - 1;
      final percSerieCorrente = _toDouble(serie.percentualeTarget) ?? baseInput;
      final percOverride = currentIndex < overrideSerie.length ? overrideSerie[currentIndex] : null;
      final percSerieNuova = percOverride ?? (percSerieCorrente + delta);

      final kgOld = WorkloadCalculator.calculateFromMaxAndPercentage(
        oneRepMax: rm,
        percentage: percSerieCorrente,
      );
      final kgNew = WorkloadCalculator.calculateFromMaxAndPercentage(
        oneRepMax: rm,
        percentage: percSerieNuova,
      );

      out.add({
        'serie': 'S$idx',
        'oldP': '${_formatPercent(percSerieCorrente)}%',
        'newP': '${_formatPercent(percSerieNuova)}%',
        'oldKg': '${_formatKg(kgOld)} kg',
        'newKg': '${_formatKg(kgNew)} kg',
      });
      idx += 1;
    }

    return out;
  }

  bool _matchesFilter(Esercizio esercizio) {
    if (_modalitaFiltro == 'tutte') return true;
    return esercizio.modalitaIntensita == _modalitaFiltro;
  }

  void _applicaPresetGlobale() {
    final deltaPerc = _globalDeltaPercentController.text.trim();
    final deltaKg = _globalDeltaKgController.text.trim();
    final rir = _globalRirController.text.trim();

    int touched = 0;
    for (int i = 0; i < widget.scheda.esercizi.length; i++) {
      final esercizio = widget.scheda.esercizi[i];
      if (!_matchesFilter(esercizio)) continue;

      final editor = _editors[i];
      if (esercizio.modalitaIntensita == 'percentuale') {
        if (deltaPerc.isNotEmpty) {
          editor.incrementoPercentualeController.text = deltaPerc;
          touched += 1;
        }
        if (deltaKg.isNotEmpty) {
          editor.incrementoController.text = deltaKg;
          touched += 1;
        }
      } else {
        if (rir.isNotEmpty) {
          editor.rirController.text = rir;
          touched += 1;
        }
      }
    }

    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          touched == 0
              ? 'Nessun campo aggiornato: inserisci un preset globale.'
              : 'Preset globale applicato agli esercizi filtrati.',
        ),
        backgroundColor: touched == 0 ? Colors.orange : Colors.green,
      ),
    );
  }

  Widget _buildPresetGlobaleCard() {
    final total = widget.scheda.esercizi.length;
    final totalPercent = widget.scheda.esercizi.where((e) => e.modalitaIntensita == 'percentuale').length;
    final totalRir = widget.scheda.esercizi.where((e) => e.modalitaIntensita != 'percentuale').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progressione da W${widget.scheda.settimanaCorrente} a W${widget.scheda.settimanaCorrente + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '$total esercizi • $totalPercent percentuale • $totalRir RIR',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tutte'),
                selected: _modalitaFiltro == 'tutte',
                onSelected: (_) => setState(() => _modalitaFiltro = 'tutte'),
              ),
              ChoiceChip(
                label: const Text('Percentuale'),
                selected: _modalitaFiltro == 'percentuale',
                onSelected: (_) => setState(() => _modalitaFiltro = 'percentuale'),
              ),
              ChoiceChip(
                label: const Text('RIR'),
                selected: _modalitaFiltro == 'rir',
                onSelected: (_) => setState(() => _modalitaFiltro = 'rir'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _globalDeltaPercentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Preset Δ% (globale)',
                    hintText: 'es. 2.5',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _globalDeltaKgController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Preset Δkg (globale)',
                    hintText: 'es. 2.5',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _globalRirController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preset RIR (globale)',
                    hintText: 'es. 2',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _applicaPresetGlobale,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Applica'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _applicaProgressione() {
    for (int i = 0; i < widget.scheda.esercizi.length; i++) {
      final e = widget.scheda.esercizi[i];
      final ed = _editors[i];
      applyProgressioneToExerciseForTest(
        exercise: e,
        massimaleInput: _toDouble(ed.massimaleController.text),
        percentualeBaseInput: _toDouble(ed.percentualeController.text),
        incrementoPercentuale: _toDouble(ed.incrementoPercentualeController.text) ?? 0,
        percentualiSerieOverride: _parsePercentualiSerieInput(
          ed.percentualiSerieController.text,
          e.serieAttive.where((s) => s.tipo != 'Avvicinamento').length,
        ),
        forceRecalculateWeights: _forceRecalculateWeights,
        incrementoKg: _toDouble(ed.incrementoController.text),
        rirInput: ed.rirController.text,
      );
    }

    widget.scheda.settimanaCorrente += 1;
    if (!mounted) return;
    Navigator.pop(context, widget.scheda);
  }

  @override
  Widget build(BuildContext context) {
    final visibleIndexes = <int>[];
    for (int i = 0; i < widget.scheda.esercizi.length; i++) {
      if (_matchesFilter(widget.scheda.esercizi[i])) {
        visibleIndexes.add(i);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Settimana Successiva • W${widget.scheda.settimanaCorrente + 1}'),
      ),
      body: Column(
        children: [
          _buildPresetGlobaleCard(),
          Expanded(
            child: visibleIndexes.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun esercizio visibile con il filtro selezionato.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visibleIndexes.length,
                    itemBuilder: (context, visibleIndex) {
                      final index = visibleIndexes[visibleIndex];
                      final esercizio = widget.scheda.esercizi[index];
                      final editor = _editors[index];
                      final isPercent = esercizio.modalitaIntensita == 'percentuale';

                      final massimale = _toDouble(editor.massimaleController.text);
                      final percentuale = _toDouble(editor.percentualeController.text);
                      final incrementoPerc = _toDouble(editor.incrementoPercentualeController.text) ?? 0;
                      final percentualeFinalePreview = percentuale != null ? percentuale + incrementoPerc : null;
                      final calcolato = (isPercent && massimale != null && percentualeFinalePreview != null)
                          ? WorkloadCalculator.calculateFromMaxAndPercentage(
                              oneRepMax: massimale,
                              percentage: percentualeFinalePreview,
                            )
                          : null;
                      final previewSerie = _buildSeriePreview(esercizio, editor);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      esercizio.nome,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPercent
                                          ? Colors.lightBlueAccent.withValues(alpha: 0.15)
                                          : Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isPercent
                                            ? Colors.lightBlueAccent.withValues(alpha: 0.4)
                                            : Colors.amber.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Text(
                                      isPercent ? 'Percentuale' : 'RIR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isPercent ? Colors.lightBlueAccent : Colors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (isPercent)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: editor.massimaleController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: '1RM / Massimale (kg)',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: editor.percentualeController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Percentuale base (%)',
                                          hintText: 'es. 75',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                TextField(
                                  controller: editor.rirController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Nuovo target RIR',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              if (isPercent)
                                Text(
                                  calcolato == null
                                      ? 'Carico calcolato: -'
                                      : 'Target esercizio previsto: ${calcolato.toStringAsFixed(1)} kg',
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.lightBlueAccent),
                                ),
                              if (isPercent && previewSerie.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Text('Preview modifiche serie', style: TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                ...previewSerie.map(
                                  (r) => Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black12,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 34, child: Text(r['serie']!, style: const TextStyle(fontWeight: FontWeight.bold))),
                                        Expanded(child: Text('${r['oldP']} -> ${r['newP']}', style: const TextStyle(color: Colors.amberAccent))),
                                        Expanded(child: Text('${r['oldKg']} -> ${r['newKg']}', textAlign: TextAlign.right)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              if (isPercent)
                                TextField(
                                  controller: editor.incrementoPercentualeController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Incremento intensita (%)',
                                    hintText: 'es. +2.5',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              if (isPercent) const SizedBox(height: 10),
                              if (isPercent)
                                TextField(
                                  controller: editor.percentualiSerieController,
                                  keyboardType: TextInputType.text,
                                  decoration: const InputDecoration(
                                    labelText: 'Percentuali serie (assolute) settimana prossima',
                                    hintText: 'es. 75,80,82.5',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              if (isPercent) const SizedBox(height: 10),
                              TextField(
                                controller: editor.incrementoController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Incremento carico opzionale (kg)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Ricalcola automaticamente i carichi'),
                subtitle: const Text('Se disattivo, mantiene i carichi custom dove possibile'),
                value: _forceRecalculateWeights,
                onChanged: (v) async {
                  setState(() {
                    _forceRecalculateWeights = v;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_prefsKeyForceRecalc, v);
                },
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: _applicaProgressione,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Applica Settimana Successiva'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressEditorState {
  final TextEditingController rirController;
  final TextEditingController massimaleController;
  final TextEditingController percentualeController;
  final TextEditingController incrementoPercentualeController;
  final TextEditingController percentualiSerieController;
  final TextEditingController incrementoController;

  _ProgressEditorState({
    required this.rirController,
    required this.massimaleController,
    required this.percentualeController,
    required this.incrementoPercentualeController,
    required this.percentualiSerieController,
    required this.incrementoController,
  });

  factory _ProgressEditorState.fromExercise(Esercizio esercizio) {
    return _ProgressEditorState(
      rirController: TextEditingController(text: esercizio.rirTarget ?? ''),
      massimaleController: TextEditingController(text: esercizio.massimaleKg?.toString() ?? ''),
      percentualeController: TextEditingController(text: esercizio.percentualeMassimale?.toString() ?? ''),
      incrementoPercentualeController: TextEditingController(),
      percentualiSerieController: TextEditingController(),
      incrementoController: TextEditingController(),
    );
  }

  void dispose() {
    rirController.dispose();
    massimaleController.dispose();
    percentualeController.dispose();
    incrementoPercentualeController.dispose();
    percentualiSerieController.dispose();
    incrementoController.dispose();
  }
}
