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
import 'dettaglio_scheda_screen.dart';
import 'storico_screen.dart';
import 'crea_scheda.dart';
import 'crea_esercizio.dart';
import 'pr_mode_screen.dart';
import 'dolore_screen.dart';

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

  List<Scheda> mieSchede = [];
  List<Allenamento> storico = []; 
  List<String> cartelleVuote = [];
  bool _isLoading = true;

  String _zonaStretchingSelezionata = 'Lombare';

  void _updateState(VoidCallback callback) => setState(callback);

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
      final snapshot = await FirebaseFirestore.instance.collection('schede_assegnate').where('atletaId', isEqualTo: user.uid).get();
      int nuoveSchede = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        bool giaPresente = mieSchede.any((s) => s.nome == data['nome']);
        if (!giaPresente) {
          final schedaDalCoach = Scheda.fromJson(data);
          schedaDalCoach.categoria = 'Dal Coach 🐯'; 
          setState(() { mieSchede.add(schedaDalCoach); });
          nuoveSchede++;
        }
      }
      if (nuoveSchede > 0) {
        _salvaDati();
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

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = doc.data();
        final appState = data?['app_state'];

        if (appState is Map<String, dynamic>) {
          final cloudSchede = appState['schede_salvate'];
          final cloudStorico = appState['storico_salvato'];
          final cloudCartelle = appState['cartelle_vuote'];
          final cloudZona = appState['zona_stretching'];

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
  }

  Future<void> _salvaZonaStretching(String zona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(zonaStretchingSharedKey, zona);
    aggiornaZonaStretchingCondivisa(zona);
    await _sincronizzaStatoLocaleSuCloud();
  }

  Future<void> _sincronizzaStatoLocaleSuCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'app_state': {
          'schede_salvate': mieSchede.map((e) => e.toJson()).toList(),
          'storico_salvato': storico.map((e) => e.toJson()).toList(),
          'cartelle_vuote': cartelleVuote,
          'zona_stretching': _zonaStretchingSelezionata,
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
    await _sincronizzaStatoLocaleSuCloud();
  }

  @override
  Widget build(BuildContext context) => _buildWorkoutsScreen(context);
}