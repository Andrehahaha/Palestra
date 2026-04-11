import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/allenamento.dart';
import '../../models/scheda.dart';
import '../../services/dolore_data.dart';
import '../../services/workload_calculator.dart';

// ============================================================================
// SCHERMATA MODALITÀ PR
// ============================================================================
class PRModeScreen extends StatefulWidget {
  const PRModeScreen({super.key});

  @override
  State<PRModeScreen> createState() => _PRModeScreenState();
}

class _PRModeScreenState extends State<PRModeScreen> {
  Map<String, double> iMieiPRStorici = {};
  Map<String, double> prManuali = {};

  final List<String> _eserciziFissi = ['Panca', 'Squat', 'Stacco'];
  String _esercizioSelezionato = 'Panca';

  final TextEditingController _maxController = TextEditingController();

  double pesoSelezionatoPerBilanciere = 0.0;
  double pesoBilanciereVuoto = 20.0;

  bool _modalitaWarmup = true;
  final Set<int> _indiciCompletati = {};

  double _prInizialeSessione = 0.0;
  double _percentualeAttuale = 0.0;

  bool _isTimerOpen = false;

  final List<Map<String, dynamic>> progressioneWarmup = [
    {'sets': '1', 'reps': '5', 'perc': 50.0},
    {'sets': '1', 'reps': '4', 'perc': 60.0},
    {'sets': '1', 'reps': '3', 'perc': 70.0},
    {'sets': '1', 'reps': '2', 'perc': 80.0},
    {'sets': '1', 'reps': '1', 'perc': 90.0},
    {'sets': '2', 'reps': '1', 'perc': 95.0},
    {'sets': '1', 'reps': '1', 'perc': 100.0},
    {'sets': '1', 'reps': '1', 'perc': 102.5, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 105.0, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 107.5, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 110.0, 'pr': true},
  ];

  String _zonaStretchingSelezionata = 'Lombare';

  void _onZonaCondivisaChanged() {
    if (!mounted) return;
    if (_zonaStretchingSelezionata != zonaStretchingNotifier.value) {
      setState(() => _zonaStretchingSelezionata = zonaStretchingNotifier.value);
    }
  }

  @override
  void initState() {
    super.initState();
    _zonaStretchingSelezionata = zonaStretchingNotifier.value;
    zonaStretchingNotifier.addListener(_onZonaCondivisaChanged);
    _caricaDatiMemoria();
  }

  @override
  void dispose() {
    zonaStretchingNotifier.removeListener(_onZonaCondivisaChanged);
    _maxController.dispose();
    super.dispose();
  }

  String _getNomeEsteso(String es) {
    if (es == 'Panca') return 'Panca Piana';
    if (es == 'Stacco') return 'Stacco da Terra';
    return es;
  }

  List<String> _prAliasesForExercise(String canonicalName) {
    final lowered = canonicalName.toLowerCase();
    if (lowered == 'panca piana') {
      return const [
        'Panca Piana',
        'Panca piana con bilanciere(presa media)',
        'Panca piana con bilanciere - presa media',
        'Panca piana con bilanciere (presa media)',
      ];
    }
    if (lowered == 'squat') {
      return const [
        'Squat',
        'Squat Completo con Bilanciere',
        'Squat completo con bilanciere',
      ];
    }
    if (lowered == 'stacco da terra') {
      return const [
        'Stacco da Terra',
        'Stacco da Terra con Bilanciere',
        'Stacco da terra con bilanciere',
      ];
    }
    return [canonicalName];
  }

  String _norm(String value) {
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
    final n = _norm(nome);
    final isPancaBilancierePresaMedia =
        n.contains('panca') &&
        n.contains('bilanciere') &&
        n.contains('presa media');
    final isSquatCompletoBilanciere =
        n.contains('squat') &&
        n.contains('completo') &&
        n.contains('bilanciere');
    final isStaccoBilanciere = n.contains('stacco') && n.contains('bilanciere');
    final isStaccoConventional =
        n.contains('conventional') && n.contains('deadlift');
    if (n.contains('panca piana') ||
        n.contains('bench press') ||
        n == 'panca' ||
        isPancaBilancierePresaMedia) {
      return 'panca piana';
    }
    if (n == 'squat' || n.contains('back squat') || isSquatCompletoBilanciere) {
      return 'squat';
    }
    if (n.contains('stacco da terra') ||
        n.contains('deadlift') ||
        n == 'stacco' ||
        isStaccoBilanciere ||
        isStaccoConventional) {
      return 'stacco da terra';
    }
    return '';
  }

  Future<void> _aggiornaCarichiPercentualiRetroattivi({
    required String esercizioSelezionato,
    required double nuovoPrKg,
  }) async {
    final targetKey = _big3Key(_getNomeEsteso(esercizioSelezionato));
    if (targetKey.isEmpty || nuovoPrKg <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final schedeJson = prefs.getString('schede_salvate');
    if (schedeJson == null) return;

    final decoded = jsonDecode(schedeJson);
    if (decoded is! List) return;

    final schede = decoded
        .whereType<Map>()
        .map((e) => Scheda.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    bool changed = false;

    for (final scheda in schede) {
      for (final es in scheda.esercizi) {
        if (es.modalitaIntensita != 'percentuale') continue;
        if (_big3Key(es.nome) != targetKey) continue;

        final oldRm = es.massimaleKg;
        es.massimaleKg = nuovoPrKg;
        changed = true;

        final percEsercizio = es.percentualeMassimale;
        if (percEsercizio != null && percEsercizio > 0) {
          es.caricoTargetKg = WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: nuovoPrKg,
            percentage: percEsercizio,
          );
        }

        for (final serie in es.serieAttive.where(
          (s) => s.tipo != 'Avvicinamento',
        )) {
          final percSerie = double.tryParse(
            serie.percentualeTarget.replaceAll(',', '.'),
          );
          final percToUse = (percSerie != null && percSerie > 0)
              ? percSerie
              : (percEsercizio ?? 0);

          if (percToUse <= 0) continue;

          if (serie.percentualeTarget.trim().isEmpty) {
            serie.percentualeTarget = percToUse.toStringAsFixed(
              percToUse % 1 == 0 ? 0 : 1,
            );
            changed = true;
          }

          final carico = WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: nuovoPrKg,
            percentage: percToUse,
          );
          final pesoEsistente = double.tryParse(
            serie.peso.replaceAll(',', '.'),
          );
          final oldAutoCarico = oldRm != null && oldRm > 0
              ? WorkloadCalculator.calculateFromMaxAndPercentage(
                  oneRepMax: oldRm,
                  percentage: percToUse,
                )
              : null;

          // Aggiorna solo se vuoto o se il peso attuale coincide con il vecchio auto-calcolo.
          final isAutoOld =
              oldAutoCarico != null &&
              pesoEsistente != null &&
              (pesoEsistente - oldAutoCarico).abs() <= 0.26;
          if (serie.peso.trim().isEmpty || isAutoOld) {
            final nuovoPeso = carico.toStringAsFixed(1);
            if (serie.peso != nuovoPeso) {
              serie.peso = nuovoPeso;
              changed = true;
            }
          }
        }
      }
    }

    if (!changed) return;

    await prefs.setString(
      'schede_salvate',
      jsonEncode(schede.map((s) => s.toJson()).toList()),
    );

    await _sincronizzaSchedeRetroattiveSuCloud(schede);
  }

  Future<void> _sincronizzaSchedeRetroattiveSuCloud(List<Scheda> schede) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'app_state': {
          'schede_salvate': schede.map((s) => s.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Errore sync retroattivo schede cloud: $e');
    }
  }

  double _readPrForSelection(String shortExerciseName) {
    final canonical = _getNomeEsteso(shortExerciseName);
    final aliases = _prAliasesForExercise(canonical);

    final manuale = prManuali[shortExerciseName];
    if (manuale != null && manuale > 0) return manuale;

    final shortNorm = _norm(shortExerciseName);
    for (final entry in prManuali.entries) {
      if (_norm(entry.key) == shortNorm && entry.value > 0) {
        return entry.value;
      }
    }

    for (final alias in aliases) {
      final value = iMieiPRStorici[alias];
      if (value != null && value > 0) return value;
    }

    final aliasNorms = aliases.map(_norm).toList();
    for (final entry in iMieiPRStorici.entries) {
      final keyNorm = _norm(entry.key);
      final value = entry.value;
      if (value <= 0) continue;
      if (aliasNorms.any(
        (a) => keyNorm == a || keyNorm.contains(a) || a.contains(keyNorm),
      )) {
        return value;
      }
    }

    final big3Canonical = _big3Key(canonical);
    if (big3Canonical.isNotEmpty) {
      for (final entry in iMieiPRStorici.entries) {
        final keyNorm = _norm(entry.key);
        if ((keyNorm == big3Canonical || keyNorm.contains(big3Canonical)) &&
            entry.value > 0) {
          return entry.value;
        }
      }
    }

    return 0.0;
  }

  Future<void> _caricaDatiMemoria() async {
    final prefs = await SharedPreferences.getInstance();

    final String? zonaSalvata = prefs.getString(zonaStretchingSharedKey);
    if (zonaSalvata != null && zoneDolore.contains(zonaSalvata)) {
      _zonaStretchingSelezionata = zonaSalvata;
      aggiornaZonaStretchingCondivisa(zonaSalvata);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final cloudZona = doc.data()?['app_state']?['zona_stretching'];
        if (cloudZona is String && zoneDolore.contains(cloudZona)) {
          _zonaStretchingSelezionata = cloudZona;
          aggiornaZonaStretchingCondivisa(cloudZona);
          await prefs.setString(zonaStretchingSharedKey, cloudZona);
        }
      } catch (e) {
        debugPrint('Errore caricamento zona cloud PR: $e');
      }
    }

    final String? prStoriciJson = prefs.getString('personal_records');
    if (prStoriciJson != null) {
      Map<String, dynamic> decodificati = jsonDecode(prStoriciJson);
      decodificati.forEach((key, value) {
        iMieiPRStorici[key] = (value as num).toDouble();
      });
    }

    final String? manualiJson = prefs.getString('pr_manuali_salvati');
    if (manualiJson != null) {
      Map<String, dynamic> decodificati = jsonDecode(manualiJson);
      decodificati.forEach((key, value) {
        prManuali[key] = (value as num).toDouble();
      });
    }

    _aggiornaUI();

    setState(() {
      _prInizialeSessione = _readPrForSelection(_esercizioSelezionato);
    });
  }

  Future<void> _salvaZonaStretching(String zona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(zonaStretchingSharedKey, zona);
    aggiornaZonaStretchingCondivisa(zona);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'app_state': {
            'zona_stretching': zona,
            'updated_at': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Errore salvataggio zona cloud PR: $e');
      }
    }
  }

  Future<void> _salvaPRInStorico(
    String nomeEs,
    double peso,
    double perc,
    String reps,
  ) async {
    String nomeEsteso = _getNomeEsteso(nomeEs);
    String dataIso = DateTime.now().toIso8601String();
    String nomeScheda = '🏆 TEST PR: $nomeEsteso';
    String feedback = 'Miglior alzata: $nomeEsteso a $peso kg ($perc%)';

    Map<String, dynamic> fakeJson = {
      'data': dataIso,
      'note': feedback,
      'scheda': {
        'nome': nomeScheda,
        'livello': 'Massimale',
        'categoria': 'Test PR',
        'esercizi': [
          {
            'nome': nomeEsteso,
            'avvicinamento': 0,
            'workingSet': 1,
            'ripetizioni': reps,
            'recupero': '0',
            'tecniche': ['Test PR'],
            'note': '',
            'serieAttive': [
              {
                'tipo': 'Nuovo PR',
                'peso': peso.toString(),
                'ripetizioniFatte': reps,
                'isCompletata': true,
                'rpe': '10',
              },
            ],
          },
        ],
      },
    };

    final nuovoAll = Allenamento.fromJson(fakeJson);
    final prefs = await SharedPreferences.getInstance();
    final String? storicoJson = prefs.getString('storico_salvato');
    List<dynamic> listaLocale = storicoJson != null
        ? jsonDecode(storicoJson)
        : [];
    listaLocale.add(nuovoAll.toJson());
    await prefs.setString('storico_salvato', jsonEncode(listaLocale));

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('storico_atleti').add({
          'atletaId': user.uid,
          'atletaEmail': user.email,
          'data': dataIso,
          'nomeScheda': nomeScheda,
          'feedback_atleta': feedback,
          'esercizi': [
            {
              'nome': nomeEsteso,
              'target_ripetizioni': reps,
              'tecniche': ['Test PR'],
              'serie': [
                {'peso': peso.toString(), 'tipo': 'Nuovo PR'},
              ],
            },
          ],
        });
      } catch (e) {
        debugPrint("Errore invio PR al database: $e");
      }
    }
  }

  Future<void> _salvaPRManuale(
    String es,
    double peso, {
    bool sincronizzaCloud = true,
  }) async {
    prManuali[es] = peso;
    String nomeEsteso = _getNomeEsteso(es);
    for (final alias in _prAliasesForExercise(nomeEsteso)) {
      iMieiPRStorici[alias] = peso;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pr_manuali_salvati', jsonEncode(prManuali));

    String? prJson = prefs.getString('personal_records');
    Map<String, dynamic> prGlobali = prJson != null ? jsonDecode(prJson) : {};
    for (final alias in _prAliasesForExercise(nomeEsteso)) {
      prGlobali[alias] = peso;
    }
    await prefs.setString('personal_records', jsonEncode(prGlobali));

    await _aggiornaCarichiPercentualiRetroattivi(
      esercizioSelezionato: es,
      nuovoPrKg: peso,
    );

    final user = FirebaseAuth.instance.currentUser;
    if (sincronizzaCloud && user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'personal_records': prGlobali,
          'ultimo_aggiornamento_pr': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Errore sync PR: $e");
      }
    }
  }

  void _aggiornaUI() {
    double pesoCaricato = _readPrForSelection(_esercizioSelezionato);

    setState(() {
      if (pesoCaricato > 0) {
        _maxController.text = pesoCaricato == pesoCaricato.truncateToDouble()
            ? pesoCaricato.toInt().toString()
            : pesoCaricato.toString();
        pesoSelezionatoPerBilanciere = pesoCaricato;
      } else {
        _maxController.text = '';
        pesoSelezionatoPerBilanciere = 0.0;
      }
    });
  }

  List<double> _calcolaDischi(double pesoTotale) {
    List<double> dischiDaCaricare = [];
    if (pesoTotale <= pesoBilanciereVuoto || pesoTotale > 2000) {
      return dischiDaCaricare;
    }

    double pesoDaAggiungere = (pesoTotale - pesoBilanciereVuoto) / 2;
    List<double> pezzature = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];

    for (var disco in pezzature) {
      while (pesoDaAggiungere >= disco) {
        dischiDaCaricare.add(disco);
        pesoDaAggiungere -= disco;
        if (dischiDaCaricare.length > 30) break;
      }
    }
    return dischiDaCaricare;
  }

  Color _coloreDisco(double peso) {
    if (peso == 25.0) return Colors.red.shade700;
    if (peso == 20.0) return Colors.blue.shade700;
    if (peso == 15.0) return Colors.yellow.shade700;
    if (peso == 10.0) return Colors.green.shade700;
    if (peso == 5.0) return Colors.white;
    if (peso == 2.5) return Colors.black;
    return Colors.grey.shade400;
  }

  double _altezzaDisco(double peso) {
    if (peso >= 15.0) return 100.0;
    if (peso == 10.0) return 80.0;
    if (peso == 5.0) return 60.0;
    if (peso == 2.5) return 50.0;
    return 40.0;
  }

  Widget _disegnaBilanciere(double pesoTotale) {
    List<double> dischi = _calcolaDischi(pesoTotale);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.deepOrange.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            pesoTotale > 0 ? '$pesoTotale kg' : 'Inserisci il Massimale',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          if (pesoTotale >= pesoBilanciereVuoto)
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 15,
                    width: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey.shade400,
                          Colors.grey.shade600,
                          Colors.grey.shade400,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Positioned(
                    left: MediaQuery.of(context).size.width * 0.25,
                    child: Container(
                      height: 40,
                      width: 10,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Positioned(
                    left: MediaQuery.of(context).size.width * 0.25 + 12,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.5,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: dischi
                              .map(
                                (d) => Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  height: _altezzaDisco(d),
                                  width: 16,
                                  decoration: BoxDecoration(
                                    color: _coloreDisco(d),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.black54,
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: Text(
                                        d.toString().replaceAll('.0', ''),
                                        style: TextStyle(
                                          color:
                                              d == 5.0 || d == 15.0 || d == 1.25
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Text(
              'Troppo leggero per il bilanciere!',
              style: TextStyle(color: Colors.amber),
            ),
        ],
      ),
    );
  }

  Widget _buildBarraProgresso() {
    Color barColor = Colors.grey;
    if (_percentualeAttuale >= 102.5) {
      barColor = Colors.purpleAccent;
    } else if (_percentualeAttuale == 100) {
      barColor = Colors.redAccent;
    } else if (_percentualeAttuale >= 90) {
      barColor = Colors.orange;
    } else if (_percentualeAttuale >= 70) {
      barColor = Colors.blueAccent;
    } else if (_percentualeAttuale > 0) {
      barColor = Colors.green;
    }

    double fillRatio = (_percentualeAttuale / 110.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _percentualeAttuale > 0
              ? 'Intensità Massima Raggiunta: ${_percentualeAttuale.toString().replaceAll('.0', '')}%'
              : 'Seleziona una spunta per riempire la barra',
          style: TextStyle(
            color: barColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              height: 14,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.elasticOut,
                    width: constraints.maxWidth * fillRatio,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        if (_percentualeAttuale > 0)
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStretchingInfoSection() {
    final stretching = stretchingPerZona(_zonaStretchingSelezionata);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.self_improvement, color: Colors.lightBlueAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sezione informativa • Solo stretching',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Usa questa mini-routine per mobilità/recupero prima o dopo il lavoro PR.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            const Text(
              'Zona condivisa con Schede e Dolori',
              style: TextStyle(
                color: Colors.lightBlueAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zoneDolore.map((zona) {
                final isSelected = _zonaStretchingSelezionata == zona;
                return ChoiceChip(
                  label: Text(zona),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _zonaStretchingSelezionata = zona);
                    _salvaZonaStretching(zona);
                  },
                  selectedColor: Colors.deepOrange,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade300,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            ...stretching.map(
              (riga) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(child: Text(riga)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 👇 NUOVA FUNZIONE: PERMETTE DI INSERIRE UNA % CUSTOM E RIORDINA LA LISTA
  Future<void> _aggiungiPercentualeCustom() async {
    TextEditingController percController = TextEditingController();
    String? val = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Percentuale su misura 🎯',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: percController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'Es: 87.5',
            suffixText: '%',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(context, percController.text.trim()),
            child: const Text(
              'Aggiungi',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (val != null && val.isNotEmpty) {
      double? nuovaPerc = double.tryParse(val.replaceAll(',', '.'));
      if (nuovaPerc != null && nuovaPerc > 0) {
        setState(() {
          progressioneWarmup.add({
            'sets': '1',
            'reps': '1',
            'perc': nuovaPerc,
            'pr': true,
          });
          progressioneWarmup.sort(
            (a, b) => (a['perc'] as double).compareTo(b['perc'] as double),
          );
        });
      }
    }
  }

  Future<bool> _concludiSessione(bool dalTastoIndietro) async {
    double maxAttuale =
        double.tryParse(_maxController.text.replaceAll(',', '.')) ?? 0.0;
    double maxPesoRaggiunto = 0.0;
    double maxPercRaggiunta = 0.0;
    String repsPerStorico = '1';

    for (int i in _indiciCompletati) {
      double perc = _modalitaWarmup
          ? progressioneWarmup[i]['perc']
          : (110 - (i * 5)).toDouble();
      String reps = _modalitaWarmup ? progressioneWarmup[i]['reps'] : '1';
      double pesoCalcolato = (maxAttuale * (perc / 100));
      double pesoArrotondato = (pesoCalcolato / 2.5).round() * 2.5;

      if (pesoArrotondato > maxPesoRaggiunto) {
        maxPesoRaggiunto = pesoArrotondato;
        maxPercRaggiunta = perc;
        repsPerStorico = reps;
      }
    }

    if (maxPesoRaggiunto == 0.0) {
      if (!dalTastoIndietro) Navigator.pop(context);
      return true;
    }

    bool isNuovoPR = maxPesoRaggiunto > _prInizialeSessione;
    bool aggiornaMassimale = isNuovoPR || _prInizialeSessione == 0;

    int? scelta = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              dalTastoIndietro ? 'Uscire dal Test?' : 'Finito PR? 🏆',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hai sollevato un carico massimo di $maxPesoRaggiunto kg.',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CheckboxListTile(
                    activeColor: Colors.deepOrange,
                    title: const Text(
                      'Imposta come nuovo Massimale',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: aggiornaMassimale,
                    onChanged: (val) {
                      setDialogState(() => aggiornaMassimale = val ?? false);
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: const Text(
                  'Annulla',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 1),
                child: const Text(
                  'Scarta ed Esci',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, 2),
                child: const Text('Salva Sessione'),
              ),
            ],
          );
        },
      ),
    );

    if (scelta == null || scelta == 0) return false;

    if (scelta == 1) {
      if (!dalTastoIndietro && mounted) {
        Navigator.pop(context);
      }
      return true;
    }

    if (scelta == 2) {
      if (aggiornaMassimale) {
        setState(() {
          _maxController.text =
              maxPesoRaggiunto == maxPesoRaggiunto.truncateToDouble()
              ? maxPesoRaggiunto.toInt().toString()
              : maxPesoRaggiunto.toString();
        });
        await _salvaPRManuale(
          _esercizioSelezionato,
          maxPesoRaggiunto,
          sincronizzaCloud: true,
        );
        _prInizialeSessione = maxPesoRaggiunto;
      }

      await _salvaPRInStorico(
        _esercizioSelezionato,
        maxPesoRaggiunto,
        maxPercRaggiunta,
        repsPerStorico,
      );

      if (!mounted) return true;

      if (aggiornaMassimale && isNuovoPR) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nuovo Record di $_esercizioSelezionato: $maxPesoRaggiunto kg! 🏆🔥',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ottimo lavoro! $maxPesoRaggiunto kg salvati in cronologia 💪',
            ),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (!dalTastoIndietro) {
        Navigator.pop(context);
      }
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    double maxAttuale =
        double.tryParse(_maxController.text.replaceAll(',', '.')) ?? 0.0;

    return PopScope(
      canPop: _indiciCompletati.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _indiciCompletati.isEmpty) return;
        final shouldPop = await _concludiSessione(true);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Modalità PR 👑')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: _eserciziFissi.map((es) {
                  bool isSelected = _esercizioSelezionato == es;
                  return ChoiceChip(
                    label: Text(
                      es,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? Colors.white : Colors.grey,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        _esercizioSelezionato = es;
                        _indiciCompletati.clear();
                        _percentualeAttuale = 0.0;
                      });
                      _aggiornaUI();

                      setState(() {
                        _prInizialeSessione = _readPrForSelection(
                          _esercizioSelezionato,
                        );
                      });
                    },
                    selectedColor: Colors.deepOrange,
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              _buildStretchingInfoSection(),
              const SizedBox(height: 24),

              TextField(
                controller: _maxController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
                decoration: InputDecoration(
                  labelText: 'Massimale (1RM) $_esercizioSelezionato in Kg',
                  labelStyle: const TextStyle(fontSize: 16),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.fitness_center,
                    color: Colors.amber,
                  ),

                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save, color: Colors.greenAccent),
                    tooltip: 'Salva il peso sul bilanciere come Massimale',
                    onPressed: () async {
                      double p = pesoSelezionatoPerBilanciere;
                      if (p > 0) {
                        await _salvaPRManuale(
                          _esercizioSelezionato,
                          p,
                          sincronizzaCloud: true,
                        );
                        if (!context.mounted) return;
                        setState(() {
                          _prInizialeSessione = p;
                          _maxController.text = p == p.truncateToDouble()
                              ? p.toInt().toString()
                              : p.toString();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Massimale aggiornato a $p kg! 💾'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Nessun peso selezionato sul bilanciere!',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  ),
                ),
                onChanged: (val) {
                  double p = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                  setState(() {
                    pesoSelezionatoPerBilanciere = p;
                    _indiciCompletati.clear();
                    _percentualeAttuale = 0.0;
                  });
                },
              ),
              const SizedBox(height: 16),

              _disegnaBilanciere(pesoSelezionatoPerBilanciere),
              const SizedBox(height: 20),

              _buildBarraProgresso(),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text(
                      'Protocollo PR',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    selected: _modalitaWarmup,
                    onSelected: (val) => setState(() {
                      _modalitaWarmup = true;
                      _indiciCompletati.clear();
                      _percentualeAttuale = 0.0;
                    }),
                    selectedColor: Colors.blueAccent,
                    backgroundColor: Colors.black26,
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text(
                      'Tutte le %',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    selected: !_modalitaWarmup,
                    onSelected: (val) => setState(() {
                      _modalitaWarmup = false;
                      _indiciCompletati.clear();
                      _percentualeAttuale = 0.0;
                    }),
                    selectedColor: Colors.blueAccent,
                    backgroundColor: Colors.black26,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _modalitaWarmup ? progressioneWarmup.length + 1 : 13,
                itemBuilder: (context, index) {
                  if (_modalitaWarmup && index == progressioneWarmup.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16.0,
                        horizontal: 20.0,
                      ),
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black45,
                              foregroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                double ultimaPerc =
                                    progressioneWarmup.last['perc'];
                                progressioneWarmup.add({
                                  'sets': '1',
                                  'reps': '1',
                                  'perc': ultimaPerc + 2.5,
                                  'pr': true,
                                });
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'Aggiungi +2.5%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black45,
                              foregroundColor: Colors.orangeAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ),
                            onPressed: _aggiungiPercentualeCustom,
                            icon: const Icon(Icons.edit),
                            label: const Text(
                              'Aggiungi % a scelta...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  double percentuale = 0.0;
                  String titoloSetsReps = "";
                  bool isNuovoPR = false;

                  if (_modalitaWarmup) {
                    var step = progressioneWarmup[index];
                    percentuale = step['perc'];
                    titoloSetsReps = "${step['sets']} x ${step['reps']} ";
                    isNuovoPR = step['pr'] == true;
                  } else {
                    percentuale = (110 - (index * 5)).toDouble();
                  }

                  double pesoCalcolato = (maxAttuale * (percentuale / 100));
                  double pesoArrotondato = (pesoCalcolato / 2.5).round() * 2.5;

                  Color avatarColor = Colors.green;
                  if (percentuale >= 102.5) {
                    avatarColor = Colors.purpleAccent;
                  } else if (percentuale == 100) {
                    avatarColor = Colors.redAccent;
                  } else if (percentuale >= 90) {
                    avatarColor = Colors.orange;
                  } else if (percentuale >= 70) {
                    avatarColor = Colors.blueAccent;
                  }

                  bool isSelezionato = _indiciCompletati.contains(index);

                  return Card(
                    color: pesoSelezionatoPerBilanciere == pesoArrotondato
                        ? Colors.deepOrange.withValues(alpha: 0.3)
                        : const Color(0xFF1E1E1E),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: avatarColor,
                        child: Text(
                          '${percentuale.toString().replaceAll('.0', '')}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          if (_modalitaWarmup)
                            Text(
                              titoloSetsReps,
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          Text(
                            '$pesoArrotondato kg',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            'Esatto: ${pesoCalcolato.toStringAsFixed(1)} kg',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (isNuovoPR) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '🌟 TENTATIVO PR',
                              style: TextStyle(
                                color: Colors.purpleAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isSelezionato
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelezionato
                              ? Colors.greenAccent
                              : Colors.grey,
                          size: 28,
                        ),
                        tooltip: 'Spunta il Set',
                        onPressed: () {
                          setState(() {
                            if (isSelezionato) {
                              _indiciCompletati.remove(index);
                            } else {
                              _indiciCompletati.add(index);
                              pesoSelezionatoPerBilanciere = pesoArrotondato;
                            }

                            _percentualeAttuale = 0.0;
                            for (int i in _indiciCompletati) {
                              double p = _modalitaWarmup
                                  ? progressioneWarmup[i]['perc']
                                  : (110 - (i * 5)).toDouble();
                              if (p > _percentualeAttuale) {
                                _percentualeAttuale = p;
                              }
                            }
                          });

                          if (!isSelezionato && !_isTimerOpen) {
                            _isTimerOpen = true;

                            int secondiRecupero = 150;
                            if (percentuale >= 90) {
                              secondiRecupero = 300;
                            } else if (percentuale >= 70) {
                              secondiRecupero = 210;
                            }

                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) =>
                                  PRTimerWidget(secondiTotali: secondiRecupero),
                            ).then((_) {
                              _isTimerOpen = false;
                            });
                          }
                        },
                      ),
                      onTap: () {
                        setState(() {
                          pesoSelezionatoPerBilanciere = pesoArrotondato;
                        });
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        bottomNavigationBar: _indiciCompletati.isNotEmpty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    onPressed: () => _concludiSessione(false),
                    icon: const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 28,
                    ),
                    label: const Text(
                      'Finito PR 🏆',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

// ============================================================================
// WIDGET DEL TIMER DI RECUPERO
// ============================================================================
class PRTimerWidget extends StatefulWidget {
  final int secondiTotali;
  const PRTimerWidget({super.key, required this.secondiTotali});

  @override
  State<PRTimerWidget> createState() => _PRTimerWidgetState();
}

class _PRTimerWidgetState extends State<PRTimerWidget> {
  late int _rimanenti;
  Timer? _timerCount;

  @override
  void initState() {
    super.initState();
    _rimanenti = widget.secondiTotali;

    _timerCount = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rimanenti > 0) {
        if (mounted) setState(() => _rimanenti--);
      } else {
        _timerCount?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timerCount?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int m = _rimanenti ~/ 60;
    int s = _rimanenti % 60;
    bool isAllarme = _rimanenti == 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(30),
      height: 280,
      child: Column(
        children: [
          Text(
            isAllarme
                ? 'SVEGLIA! SOTTO IL BILANCIERE! 🔥'
                : 'RECUPERO SISTEMA NERVOSO 🧠',
            style: TextStyle(
              letterSpacing: 2,
              color: isAllarme ? Colors.redAccent : Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.bold,
              color: isAllarme ? Colors.redAccent : Colors.white,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isAllarme ? Colors.redAccent : Colors.deepOrange,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              isAllarme ? "LET'S GO!" : 'SALTA TIMER',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
