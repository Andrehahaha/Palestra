import 'package:flutter/material.dart';
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
import '../services/archivio_atleta.dart';
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
  final ArchivioAtleta _archivio = ArchivioAtleta.instance;

  List<Scheda> get mieSchede => _archivio.schede;
  List<Allenamento> get storico => _archivio.storico;
  List<String> get cartelleVuote => _archivio.cartelleVuote;
  bool _isLoading = true;

  Future<Map<String, double>> _caricaPrAtleta() => _archivio.caricaPr();

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
      final records = <String, double>{};
      for (final nome in mancanti) {
        final v = controllers[nome]!.text.replaceAll(',', '.').trim();
        final parsed = double.tryParse(v);
        if (parsed != null && parsed > 0) {
          records.addAll(Carichi.recordPerPr(nome, parsed));
        }
      }
      await _archivio.salvaPr(records);

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

  void _onArchivioChanged() => _updateState(() {});

  @override
  void initState() {
    super.initState();
    _archivio.addListener(_onArchivioChanged);
    _caricaDati().then((_) => _sincronizzaColCoach(silenzioso: true));
  }

  @override
  void dispose() {
    _archivio.removeListener(_onArchivioChanged);
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


  Future<void> _caricaDati() async {
    await _archivio.carica();
    _updateState(() => _isLoading = false);
  }

  Future<void> _salvaDati() => _archivio.salva();

  @override
  Widget build(BuildContext context) => _buildWorkoutsScreen(context);
}