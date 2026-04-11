import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/allenamento.dart';
import '../../models/catalogo_esercizi.dart';
import '../../services/api_esercizi.dart';
import '../../services/dizionario_esercizi.dart';
import 'widgets/exercise_detail_sheet.dart';
import 'widgets/profile_home_section.dart';

part 'profilo_screen_data.dart';
part 'profilo_screen_sections.dart';

enum _ProfiloSezione { home, grafici, libreria, dati }

class ProfiloScreen extends StatefulWidget {
  const ProfiloScreen({super.key});

  @override
  State<ProfiloScreen> createState() => _ProfiloScreenState();
}

class _ProfiloScreenState extends State<ProfiloScreen> {
  bool _forceRecalculateWeights = false;
  static const String _prefsKeyForceRecalc = 'force_recalculate_weights_toggle';
  final TextEditingController _nuovoEsercizioController =
      TextEditingController();
  final TextEditingController _nomeUtenteController = TextEditingController();
  final TextEditingController _pesoController = TextEditingController();
  final TextEditingController _altezzaController = TextEditingController();
  final TextEditingController _misureController = TextEditingController();
  final TextEditingController _noteExtraController = TextEditingController();
  List<Allenamento> storico = [];
  List<String> nomiEserciziGrafico = [];
  List<Map<String, String>> eserciziCustom = [];
  List<Map<String, dynamic>> eserciziDalWeb = [];
  String? esercizioSelezionato;
  String _categoriaNuovoEsercizio = 'Petto';
  bool _isLoading = true;
  String _searchQuery = '';
  DateTime _focusedDay = DateTime.now();
  _ProfiloSezione _sezioneCorrente = _ProfiloSezione.home;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _caricaDati();
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

  Future<void> _salvaPreferenzaToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyForceRecalc, value);
    setState(() {
      _forceRecalculateWeights = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isHome = _sezioneCorrente == _ProfiloSezione.home;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titoloSezioneProfilo()),
        leading: isHome
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () {
                  setState(() {
                    _sezioneCorrente = _ProfiloSezione.home;
                  });
                },
              ),
        actions: [
          if (_sezioneCorrente == _ProfiloSezione.libreria)
            IconButton(
              tooltip: 'Aggiungi esercizio',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _aggiungiEsercizioManualmente,
            ),
          IconButton(
            tooltip: 'Aggiorna dati',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _ricaricaDati,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            )
          : _buildSezioneAttiva(),
    );
  }

  String _titoloSezioneProfilo() {
    switch (_sezioneCorrente) {
      case _ProfiloSezione.home:
        return 'Profilo';
      case _ProfiloSezione.grafici:
        return 'Progressi e Grafici';
      case _ProfiloSezione.libreria:
        return 'Libreria Esercizi';
      case _ProfiloSezione.dati:
        return 'Dati Personali';
    }
  }

  Widget _buildSezioneAttiva() {
    switch (_sezioneCorrente) {
      case _ProfiloSezione.home:
        return _buildHomeProfilo();
      case _ProfiloSezione.grafici:
        return _buildGraficiTab();
      case _ProfiloSezione.libreria:
        return _buildLibreriaTab();
      case _ProfiloSezione.dati:
        return _buildDatiTab();
    }
  }

  Widget _buildHomeProfilo() {
    final String nomeUtente = _nomeUtenteController.text.trim();
    final int serieCompletate = storico.fold<int>(
      0,
      (totale, allenamento) =>
          totale +
          allenamento.scheda.esercizi.fold<int>(
            0,
            (setTotali, esercizio) =>
                setTotali +
                esercizio.serieAttive
                    .where((s) => s.isCompletata && s.tipo != 'Avvicinamento')
                    .length,
          ),
    );

    return ProfileHomeSection(
      nomeUtente: nomeUtente,
      sessioniRegistrate: storico.length,
      serieCompletate: serieCompletate,
      onApriGrafici: () {
        setState(() {
          _sezioneCorrente = _ProfiloSezione.grafici;
        });
      },
      onApriLibreria: () {
        setState(() {
          _sezioneCorrente = _ProfiloSezione.libreria;
        });
      },
      onApriDati: () {
        setState(() {
          _sezioneCorrente = _ProfiloSezione.dati;
        });
      },
    );
  }

  Future<void> _ricaricaDati() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    await _caricaDati();
  }

  void _updateState(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  @override
  void dispose() {
    _nuovoEsercizioController.dispose();
    _nomeUtenteController.dispose();
    _pesoController.dispose();
    _altezzaController.dispose();
    _misureController.dispose();
    _noteExtraController.dispose();
    super.dispose();
  }
}
