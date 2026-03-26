import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/esercizio.dart';
import '../models/serie.dart';
import '../models/catalogo_esercizi.dart';
import '../services/api_esercizi.dart';
import '../services/dizionario_esercizi.dart'; 
import '../services/workload_calculator.dart';

class CreaEsercizioScreen extends StatefulWidget {
  final Esercizio? esercizioDaModificare;
  const CreaEsercizioScreen({super.key, this.esercizioDaModificare});

  @override
  State<CreaEsercizioScreen> createState() => _CreaEsercizioScreenState();
}

class _CreaEsercizioScreenState extends State<CreaEsercizioScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _avvicinamentoController = TextEditingController();
  final TextEditingController _workingSetController = TextEditingController();
  final TextEditingController _ripetizioniController = TextEditingController();
  final TextEditingController _recuperoController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _rirTargetController = TextEditingController();
  final TextEditingController _massimaleController = TextEditingController();
  final TextEditingController _percentualeController = TextEditingController();
  final TextEditingController _percentualiSerieController = TextEditingController();

  String _modalitaIntensita = 'rir';
  
  List<String> _tecnicheSelezionate = [];
  List<Map<String, String>> _eserciziCustom = [];
  List<String> _nomiDalDatabase = [];

  final List<String> _tutteLeTecniche = [
    'Superset', 'Stripping', 'Drop Set', 'Rest Pause', 'Monopodalico', 
    'Piramidale', 'Back off', 'Giant Set', 'Cluster Set', 'Top Set', 
    'Feeder Set', 'Warm Up', 'Myo-reps', 'AMRAP', 'Negative', 
    'Isometria', 'Trisets', 'Pre-stancaggio', 'EMOM', 'Burnouts'
  ];

  @override
  void initState() {
    super.initState();
    _caricaEserciziCustom();
    _caricaDatabaseJSON();
    
    if (widget.esercizioDaModificare != null) {
      final e = widget.esercizioDaModificare!;
      
      _nomeController.text = DizionarioEsercizi.daIngleseAItaliano[e.nome] ?? e.nome;
      _avvicinamentoController.text = e.avvicinamento.toString();
      _workingSetController.text = e.workingSet.toString();
      _ripetizioniController.text = e.ripetizioni;
      _recuperoController.text = e.recupero;
      _modalitaIntensita = e.modalitaIntensita;
      _rirTargetController.text = e.rirTarget ?? '';
      _massimaleController.text = e.massimaleKg?.toString() ?? '';
      _percentualeController.text = e.percentualeMassimale?.toString() ?? '';
      final percentualiEsistenti = e.serieAttive
          .where((s) => s.tipo != 'Avvicinamento' && s.percentualeTarget.trim().isNotEmpty)
          .map((s) => s.percentualeTarget.trim())
          .toList();
      if (percentualiEsistenti.isNotEmpty) {
        _percentualiSerieController.text = percentualiEsistenti.join(', ');
      }
      
      // 👇 TRADUTTORE DEI VECCHI TAG! Così spuntano già selezionati
      _tecnicheSelezionate = e.tecniche.map((t) {
        if (t == 'Super Set') return 'Superset';
        if (t.toLowerCase() == 'drop set') return 'Drop Set';
        if (t.toLowerCase() == 'unilaterale') return 'Monopodalico';
        return t;
      }).toList(); 
      
      _tecnicheSelezionate.remove('Classico'); 

      if (e.note != null) {
        _noteController.text = e.note!;
      }
    }
  }

  Future<void> _caricaDatabaseJSON() async {
    final datiJson = await ApiEsercizi.ottieniEserciziTradotti();
    if (mounted) {
      setState(() {
        _nomiDalDatabase = datiJson
            .map((e) => e['nome'].toString())
            .where((nome) => nome.isNotEmpty && nome != 'null')
            .toList();
      });
    }
  }

  Future<void> _caricaEserciziCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final String? salvati = prefs.getString('esercizi_custom_db_v2');
    if (salvati != null) {
      setState(() {
        _eserciziCustom = List<Map<String, String>>.from(
          jsonDecode(salvati).map((item) => Map<String, String>.from(item))
        );
      });
    }
  }

  Future<void> _salvaNuovoNomeSeNecessario(String nome) async {
    final nomePulito = nome.trim();
    if (nomePulito.isEmpty) return;
    
    bool esisteGia = catalogoEsercizi.any((e) => e.nome.toLowerCase() == nomePulito.toLowerCase()) ||
                     _eserciziCustom.any((e) => e['nome']!.toLowerCase() == nomePulito.toLowerCase()) ||
                     _nomiDalDatabase.any((n) => n.toLowerCase() == nomePulito.toLowerCase());
                     
    if (!esisteGia) {
      final prefs = await SharedPreferences.getInstance();
      _eserciziCustom.add({'nome': nomePulito, 'categoria': 'Altro'});
      await prefs.setString('esercizi_custom_db_v2', jsonEncode(_eserciziCustom));
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _avvicinamentoController.dispose();
    _workingSetController.dispose();
    _ripetizioniController.dispose();
    _recuperoController.dispose();
    _noteController.dispose();
    _rirTargetController.dispose();
    _massimaleController.dispose();
    _percentualeController.dispose();
    _percentualiSerieController.dispose();
    super.dispose();
  }

  double? _toDouble(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  double? _calcolaCaricoTarget() {
    if (_modalitaIntensita != 'percentuale') return null;
    final massimale = _toDouble(_massimaleController.text);
    final percentuale = _toDouble(_percentualeController.text);
    if (massimale == null || percentuale == null) return null;

    return WorkloadCalculator.calculateFromMaxAndPercentage(
      oneRepMax: massimale,
      percentage: percentuale,
    );
  }

  List<double?> _parsePercentualiSerie(int numWork, double? fallbackPercentuale) {
    final raw = _percentualiSerieController.text.trim();
    if (raw.isEmpty) {
      return List<double?>.generate(numWork, (_) => fallbackPercentuale);
    }

    final tokens = raw
        .split(RegExp(r'[,;\-/\s]+'))
        .map((t) => t.replaceAll('%', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final parsed = tokens.map(_toDouble).toList();
    return List<double?>.generate(
      numWork,
      (i) => i < parsed.length ? parsed[i] : fallbackPercentuale,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isEditing = widget.esercizioDaModificare != null;
    bool isPiramidale = _tecnicheSelezionate.contains('Piramidale'); 

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Modifica Esercizio' : 'Nuovo Esercizio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            // Autocomplete Bilingue Intelligente
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                
                String query = textEditingValue.text.toLowerCase();
                
                final tuttiINomi = {
                  ..._nomiDalDatabase,
                  ...catalogoEsercizi.map((e) => e.nome), 
                  ..._eserciziCustom.map((e) => e['nome']!)
                }.toList(); 
                
                return tuttiINomi.where((nomeItaliano) {
                  // A. Cerca nel nome italiano
                  if (nomeItaliano.toLowerCase().contains(query)) return true;
                  
                  // B. Cerca nel nome inglese originale
                  var matchInglese = DizionarioEsercizi.daIngleseAItaliano.entries
                      .where((entry) => entry.value == nomeItaliano && entry.key.toLowerCase().contains(query))
                      .isNotEmpty;
                      
                  return matchInglese;
                }).toList();
              },
              onSelected: (String selection) { _nomeController.text = selection; },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                if (_nomeController.text.isNotEmpty && controller.text.isEmpty) controller.text = _nomeController.text;
                controller.addListener(() { _nomeController.text = controller.text; });
                return TextField(
                  controller: controller, focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Nome Esercizio', 
                    hintText: 'Cerca (es. Panca, Lat, Curl, Bench...)',
                    border: OutlineInputBorder(), 
                    prefixIcon: Icon(Icons.search, color: Colors.deepOrange)
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            const Text("Tecniche avanzate (opzionali):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: _tutteLeTecniche.map((tecnica) {
                final isSelected = _tecnicheSelezionate.contains(tecnica);
                return FilterChip(
                  label: Text(tecnica),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.deepOrange.shade200, 
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                  ),
                  backgroundColor: const Color(0xFF2A2A2A),
                  selected: isSelected,
                  selectedColor: Colors.deepOrange,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? Colors.transparent : Colors.deepOrange.withOpacity(0.3),
                    )
                  ),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _tecnicheSelezionate.add(tecnica);
                      } else {
                        _tecnicheSelezionate.remove(tecnica);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            
            const SizedBox(height: 24),

            if (isPiramidale)
              TextField(
                controller: _workingSetController, 
                keyboardType: TextInputType.number, 
                decoration: const InputDecoration(labelText: 'Numero Totale di Serie (Piramidale)', border: OutlineInputBorder())
              )
            else
              Row(
                children: [
                  Expanded(child: TextField(controller: _avvicinamentoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Avvicinamento', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _workingSetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Serie Allenanti', border: OutlineInputBorder()))),
                ],
              ),
            
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(controller: _ripetizioniController, decoration: InputDecoration(labelText: isPiramidale ? 'Reps (es. 12-10-8)' : 'Ripetizioni', border: const OutlineInputBorder()))),
                const SizedBox(width: 16),
                Expanded(child: TextField(controller: _recuperoController, decoration: const InputDecoration(labelText: 'Recupero (sec)', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _modalitaIntensita,
              decoration: const InputDecoration(
                labelText: 'Modalita intensita',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'rir', child: Text('RIR (Ripetizioni in Riserva)')),
                DropdownMenuItem(value: 'percentuale', child: Text('Percentuale del massimale')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _modalitaIntensita = value);
              },
            ),
            const SizedBox(height: 16),
            if (_modalitaIntensita == 'rir')
              TextField(
                controller: _rirTargetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target RIR (es. 2)',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _massimaleController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Massimale (kg)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _percentualeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Percentuale (%)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _percentualiSerieController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Percentuali per serie (es. 70,72.5,75)',
                      hintText: 'Una percentuale per ogni working set',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _calcolaCaricoTarget() == null
                          ? 'Carico calcolato: -'
                          : 'Carico calcolato: ${_calcolaCaricoTarget()!.toStringAsFixed(1)} kg',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlueAccent),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note extra (opzionale)', border: OutlineInputBorder())),
            const SizedBox(height: 32),
            
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
              onPressed: () async {
                if (_nomeController.text.isNotEmpty && _workingSetController.text.isNotEmpty) {
                  await _salvaNuovoNomeSeNecessario(_nomeController.text);

                  int numAvv = isPiramidale ? 0 : (int.tryParse(_avvicinamentoController.text) ?? 0);
                  int numWork = int.tryParse(_workingSetController.text) ?? 1;

                  List<Serie> vecchieSerie = widget.esercizioDaModificare?.serieAttive ?? [];
                  List<Serie> vecchiAvv = vecchieSerie.where((s) => s.tipo == 'Avvicinamento').toList();
                  List<Serie> vecchiWork = vecchieSerie.where((s) => s.tipo != 'Avvicinamento').toList();

                  List<Serie> nuoveSerie = [];
                  for (int i = 0; i < numAvv; i++) {
                    nuoveSerie.add(i < vecchiAvv.length ? vecchiAvv[i] : Serie(tipo: 'Avvicinamento'));
                  }
                  
                  String tipoSerieAllenante = isPiramidale ? 'Piramidale' : 'Working Set';
                  final caricoCalcolato = _calcolaCaricoTarget();
                  final massimale = _toDouble(_massimaleController.text);
                  final fallbackPercent = _toDouble(_percentualeController.text);
                  final percentualiSerie = _parsePercentualiSerie(numWork, fallbackPercent);
                  for (int i = 0; i < numWork; i++) {
                    final percSerie = percentualiSerie[i];
                    final caricoSerie = (_modalitaIntensita == 'percentuale' && massimale != null && percSerie != null)
                        ? WorkloadCalculator.calculateFromMaxAndPercentage(
                            oneRepMax: massimale,
                            percentage: percSerie,
                          )
                        : caricoCalcolato;

                    if (i < vecchiWork.length) {
                      final pesoEsistente = vecchiWork[i].peso;
                      final pesoDefaultPercentuale = (_modalitaIntensita == 'percentuale' &&
                              (pesoEsistente.isEmpty) &&
                              caricoSerie != null)
                          ? caricoSerie.toStringAsFixed(1)
                          : pesoEsistente;
                      nuoveSerie.add(Serie(
                        tipo: tipoSerieAllenante,
                        peso: pesoDefaultPercentuale,
                        ripetizioniFatte: vecchiWork[i].ripetizioniFatte,
                        isCompletata: vecchiWork[i].isCompletata,
                        percentualeTarget: _modalitaIntensita == 'percentuale' && percSerie != null
                            ? percSerie.toStringAsFixed(percSerie % 1 == 0 ? 0 : 1)
                            : vecchiWork[i].percentualeTarget,
                      ));
                    } else {
                      nuoveSerie.add(Serie(
                        tipo: tipoSerieAllenante,
                        peso: (_modalitaIntensita == 'percentuale' && caricoSerie != null)
                            ? caricoSerie.toStringAsFixed(1)
                            : '',
                        percentualeTarget: _modalitaIntensita == 'percentuale' && percSerie != null
                            ? percSerie.toStringAsFixed(percSerie % 1 == 0 ? 0 : 1)
                            : '',
                      ));
                    }
                  }

                  List<String> tecnicheFinali = _tecnicheSelezionate.isEmpty ? ['Classico'] : _tecnicheSelezionate;

                  final esercizioAggiornato = Esercizio(
                    nome: _nomeController.text, 
                    avvicinamento: numAvv,
                    workingSet: numWork,
                    ripetizioni: _ripetizioniController.text,
                    recupero: _recuperoController.text,
                    note: _noteController.text.isEmpty ? null : _noteController.text,
                    tecniche: tecnicheFinali, 
                    modalitaIntensita: _modalitaIntensita,
                    rirTarget: _modalitaIntensita == 'rir' && _rirTargetController.text.trim().isNotEmpty
                      ? _rirTargetController.text.trim()
                      : null,
                    percentualeMassimale: _modalitaIntensita == 'percentuale'
                      ? (percentualiSerie.isNotEmpty ? percentualiSerie.first : _toDouble(_percentualeController.text))
                      : null,
                    massimaleKg: _modalitaIntensita == 'percentuale'
                      ? _toDouble(_massimaleController.text)
                      : null,
                    caricoTargetKg: _modalitaIntensita == 'percentuale' ? caricoCalcolato : null,
                    serieAttive: nuoveSerie,
                  );
                  
                  if (!mounted) return;
                  Navigator.pop(context, esercizioAggiornato);
                }
              },
              child: Text(isEditing ? 'Salva Modifiche' : 'Aggiungi Esercizio', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}