import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scheda.dart';
import '../models/allenamento.dart';
import '../models/esercizio.dart';
import '../services/ai_service.dart';
import '../services/dizionario_esercizi.dart';
import '../services/dolore_data.dart';
import '../services/carichi.dart';
import 'dettaglio_scheda_screen.dart';
import 'storico_screen.dart';
import 'crea_scheda.dart';
import 'crea_esercizio.dart';
import 'pr_mode_screen.dart';
import 'settimana_successiva_screen.dart';

part 'workouts_screen_actions.dart';
part 'workouts_screen_view.dart';
part 'workouts_screen_sections.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  static const String _cartelleVuoteKey = 'cartelle_vuote';
  static const String _appStateUpdatedAtLocalKey = 'app_state_updated_at_local';
  static const String _weekHistoryStoreKey = 'week_history_store_v1';

  List<Scheda> mieSchede = [];
  List<Allenamento> storico = []; 
  List<String> cartelleVuote = [];
  bool _isLoading = true;

  String _zonaStretchingSelezionata = 'Lombare';

  Future<Map<String, double>> _caricaPrAtleta() async {
    final out = <String, double>{};
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('personal_records');
    if (local != null) {
      final decoded = jsonDecode(local);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          final val = e.value;
          if (val is num) out[e.key.toString()] = val.toDouble();
        }
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final prCloud = doc.data()?['personal_records'];
        if (prCloud is Map) {
          for (final e in prCloud.entries) {
            final val = e.value;
            if (val is num) out[e.key.toString()] = val.toDouble();
          }
        }
      } catch (_) {}
    }

    return out;
  }

  Scheda _applicaFallbackPrSuSchedaCoach(Scheda scheda, Map<String, double> prs) {
    Carichi.applicaPrAScheda(scheda, prs);
    return scheda;
  }

  Set<String> _big3MancantiDaSchede(List<Scheda> schede) {
    final out = <String>{};
    for (final scheda in schede) {
      for (final es in scheda.esercizi) {
        if (es.modalitaIntensita != 'percentuale') continue;
        if (es.massimaleKg != null && es.massimaleKg! > 0) continue;
        final lift = Carichi.riconosciBig3(es.nome);
        if (lift != null) out.add(lift.nome);
      }
    }
    return out;
  }

  Future<void> _chiediPrMancantiSeNecessario(List<Scheda> nuoveSchede) async {
    final mancanti = _big3MancantiDaSchede(nuoveSchede).toList()..sort();
    if (mancanti.isEmpty || !mounted) return;

    final controllers = <String, TextEditingController>{
      for (final nome in mancanti) nome: TextEditingController(),
    };

    final conferma = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Imposta i tuoi PR'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Per calcolare i carichi in percentuale inserisci i tuoi massimali:'),
              const SizedBox(height: 12),
              ...mancanti.map(
                (nome) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[nome],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '$nome (kg)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Dopo')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salva e calcola')),
        ],
      ),
    );

    if (conferma == true) {
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

      for (final nome in mancanti) {
        final v = controllers[nome]!.text.replaceAll(',', '.').trim();
        final parsed = double.tryParse(v);
        if (parsed != null && parsed > 0) {
          records.addAll(Carichi.recordPerPr(nome, parsed));
        }
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

      final prs = await _caricaPrAtleta();
      _updateState(() {
        for (final scheda in mieSchede.where((s) => s.categoria == 'Dal Coach 🐯')) {
          _applicaFallbackPrSuSchedaCoach(scheda, prs);
        }
      });
      await _salvaDati();
    }

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  void _updateState(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

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
    _caricaDati().then((_) => _sincronizzaColCoach(silenzioso: true));
  }

  @override
  void dispose() {
    zonaStretchingNotifier.removeListener(_onZonaCondivisaChanged);
    super.dispose();
  }

  Future<void> _sincronizzaColCoach({bool silenzioso = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final prs = await _caricaPrAtleta();
      final snapshot = await FirebaseFirestore.instance.collection('schede_assegnate').where('atletaId', isEqualTo: user.uid).get();
      int nuoveSchede = 0;
      final schedeNuove = <Scheda>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        bool giaPresente = mieSchede.any((s) => s.nome == data['nome']);
        if (!giaPresente) {
          final schedaDalCoach = _applicaFallbackPrSuSchedaCoach(Scheda.fromJson(data), prs);
          schedaDalCoach.categoria = 'Dal Coach 🐯'; 
          _updateState(() {
            mieSchede.add(schedaDalCoach);
          });
          schedeNuove.add(schedaDalCoach);
          nuoveSchede++;
        }
      }
      if (nuoveSchede > 0) {
        await _salvaDati();
        await _chiediPrMancantiSeNecessario(schedeNuove);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hai ricevuto $nuoveSchede nuove schede! 🎁'), backgroundColor: Colors.green));
      } else if (!silenzioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessuna nuova scheda dal Coach.'), backgroundColor: Colors.grey));
      }
    } catch (e) {
      debugPrint("Errore sync: $e");
    }
  }

  Future<void> _eliminaSchedaDalCloud(String nomeScheda) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schede_assegnate')
          .where('atletaId', isEqualTo: user.uid)
          .where('nome', isEqualTo: nomeScheda)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete(); 
      }
    } catch (e) {
      debugPrint("Errore eliminazione scheda cloud: $e");
    }
  }

  Future<void> _inviaAllenamentoAlCloud(Allenamento allenamento) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('storico_atleti').add({
        'atletaId': user.uid,
        'data': allenamento.data.toIso8601String(),
        'nomeScheda': allenamento.scheda.nome,
        'esercizi': allenamento.scheda.esercizi.map((e) => {
          'nome': DizionarioEsercizi.daIngleseAItaliano[e.nome] ?? e.nome,
          'target_ripetizioni': e.ripetizioni, 
          'serie': e.serieAttive.where((s) => s.isCompletata).map((s) => { 'peso': s.peso, 'tipo': s.tipo }).toList(),
        }).toList(),
      });
    } catch (e) {
      debugPrint("Errore invio allenamento: $e");
    }
  }

  Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    final String? datiSalvati = prefs.getString('schede_salvate');
    final String? storicoSalvato = prefs.getString('storico_salvato');
    final String? cartelleVuoteSalvate = prefs.getString(_cartelleVuoteKey);
    final String? zonaSalvata = prefs.getString(zonaStretchingSharedKey);
    final String? localWeekHistoryRaw = prefs.getString(_weekHistoryStoreKey);
    final String? localUpdatedAtRaw = prefs.getString(_appStateUpdatedAtLocalKey);
    final DateTime? localUpdatedAt = DateTime.tryParse(localUpdatedAtRaw ?? '');

    List<Scheda> schedeCaricate = datiSalvati != null
        ? (jsonDecode(datiSalvati) as List).map((e) => Scheda.fromJson(e)).toList()
        : [];
    List<Allenamento> storicoCaricato = storicoSalvato != null
        ? (jsonDecode(storicoSalvato) as List).map((e) => Allenamento.fromJson(e)).toList()
        : [];
    List<String> cartelleCaricate = cartelleVuoteSalvate != null
        ? List<String>.from(jsonDecode(cartelleVuoteSalvate))
        : [];
    String zonaCaricata = zoneDolore.contains(zonaSalvata) ? zonaSalvata! : _zonaStretchingSelezionata;
    final hasLocalState =
      schedeCaricate.isNotEmpty || storicoCaricato.isNotEmpty || cartelleCaricate.isNotEmpty;
    DateTime? chosenUpdatedAt = localUpdatedAt;
    String? chosenWeekHistoryRaw = localWeekHistoryRaw;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = doc.data();
        final appState = data?['app_state'];

        if (appState is Map<String, dynamic>) {
          DateTime? cloudUpdatedAt;
          final rawUpdated = appState['updated_at'];
          if (rawUpdated is Timestamp) {
            cloudUpdatedAt = rawUpdated.toDate();
          } else if (rawUpdated != null) {
            cloudUpdatedAt = DateTime.tryParse(rawUpdated.toString());
          }

          final shouldUseCloud = !hasLocalState ||
              (cloudUpdatedAt != null &&
                  (localUpdatedAt == null || cloudUpdatedAt.isAfter(localUpdatedAt)));
          if (shouldUseCloud) {
            final cloudSchede = appState['schede_salvate'];
            final cloudStorico = appState['storico_salvato'];
            final cloudCartelle = appState['cartelle_vuote'];
            final cloudZona = appState['zona_stretching'];
            final cloudWeekHistory = appState['week_history_store'];

            if (cloudSchede is List) {
              schedeCaricate = cloudSchede
                  .map((e) => Scheda.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList();
            }
            if (cloudStorico is List) {
              storicoCaricato = cloudStorico
                  .map((e) => Allenamento.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList();
            }
            if (cloudCartelle is List) {
              cartelleCaricate = cloudCartelle.map((e) => e.toString()).toList();
            }
            if (cloudZona is String && zoneDolore.contains(cloudZona)) {
              zonaCaricata = cloudZona;
            }
            if (cloudWeekHistory is Map) {
              chosenWeekHistoryRaw = jsonEncode(Map<String, dynamic>.from(cloudWeekHistory));
              await prefs.setString(
                _weekHistoryStoreKey,
                chosenWeekHistoryRaw,
              );
            }

            chosenUpdatedAt = cloudUpdatedAt ?? localUpdatedAt;
          }
        }
      } catch (e) {
        debugPrint('Errore caricamento stato cloud: $e');
      }
    }

    if (mounted) {
      setState(() {
        mieSchede = schedeCaricate;
        storico = storicoCaricato;
        cartelleVuote = cartelleCaricate;
        _zonaStretchingSelezionata = zonaCaricata;
        aggiornaZonaStretchingCondivisa(zonaCaricata);
        _isLoading = false;
      });
    }

    await prefs.setString('schede_salvate', jsonEncode(schedeCaricate.map((e) => e.toJson()).toList()));
    await prefs.setString('storico_salvato', jsonEncode(storicoCaricato.map((e) => e.toJson()).toList()));
    await prefs.setString(_cartelleVuoteKey, jsonEncode(cartelleCaricate));
    await prefs.setString(zonaStretchingSharedKey, zonaCaricata);
    if (chosenWeekHistoryRaw != null && chosenWeekHistoryRaw.trim().isNotEmpty) {
      await prefs.setString(_weekHistoryStoreKey, chosenWeekHistoryRaw);
    }
    await prefs.setString(
      _appStateUpdatedAtLocalKey,
      (chosenUpdatedAt ?? DateTime.now()).toIso8601String(),
    );
  }

  Future<void> _sincronizzaStatoLocaleSuCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> weekHistoryStore = {};
    final rawWeekHistory = prefs.getString(_weekHistoryStoreKey);
    if (rawWeekHistory != null) {
      try {
        final decoded = jsonDecode(rawWeekHistory);
        if (decoded is Map<String, dynamic>) {
          weekHistoryStore = decoded;
        } else if (decoded is Map) {
          weekHistoryStore = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        weekHistoryStore = {};
      }
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'app_state': {
          'schede_salvate': mieSchede.map((e) => e.toJson()).toList(),
          'storico_salvato': storico.map((e) => e.toJson()).toList(),
          'cartelle_vuote': cartelleVuote,
          'zona_stretching': _zonaStretchingSelezionata,
          'week_history_store': weekHistoryStore,
          'updated_at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Errore sync stato cloud: $e');
    }
  }

  Future<void> _salvaDati() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schede_salvate', jsonEncode(mieSchede.map((e) => e.toJson()).toList()));
    await prefs.setString('storico_salvato', jsonEncode(storico.map((e) => e.toJson()).toList()));
    await prefs.setString(_cartelleVuoteKey, jsonEncode(cartelleVuote));
    await prefs.setString(_appStateUpdatedAtLocalKey, DateTime.now().toIso8601String());
    await _sincronizzaStatoLocaleSuCloud();
  }

  @override
  Widget build(BuildContext context) => _buildWorkoutsScreen(context);
}