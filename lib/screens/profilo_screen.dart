import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/allenamento.dart';
import '../models/catalogo_esercizi.dart';
import '../services/api_esercizi.dart';
import '../services/dizionario_esercizi.dart'; 

class ProfiloScreen extends StatefulWidget {
  const ProfiloScreen({super.key});

  @override
  State<ProfiloScreen> createState() => _ProfiloScreenState();
}

class _ProfiloScreenState extends State<ProfiloScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nuovoEsercizioController = TextEditingController();
  
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
  String _searchQuery = ""; 
  
  DateTime _focusedDay = DateTime.now();
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? ''; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() { setState(() {}); });
    _caricaDati();
  }

  IconData _prendiIconaMuscolo(String categoria) {
    final cat = categoria.toLowerCase();
    if (cat.contains('addominali')) return Icons.grid_view;
    if (cat.contains('gambe') || cat.contains('polpacci') || cat.contains('glutei')) return Icons.directions_run;
    if (cat.contains('petto')) return Icons.view_headline;
    if (cat.contains('dorsali') || cat.contains('schiena') || cat.contains('lombari') || cat.contains('trapezi')) return Icons.format_align_center;
    if (cat.contains('bicipiti') || cat.contains('tricipiti') || cat.contains('avambracci') || cat.contains('spalle')) return Icons.fitness_center;
    return Icons.list;
  }

  Map<String, String> _classificaEsercizio(String categoriaGrezza) {
    String cat = categoriaGrezza.toLowerCase();

    if (cat.contains('petto') || cat.contains('pettorali') || cat.contains('spinte')) {
      return {'macro': 'Petto', 'micro': 'Pettorali'};
    }
    if (cat.contains('schiena') || cat.contains('dorsali') || cat.contains('trapezi') || cat.contains('lombari') || cat.contains('upper back')) {
      String micro = 'Dorso (Generale)';
      if (cat.contains('lombari') || cat.contains('bassa')) micro = 'Lombari';
      if (cat.contains('trapezi')) micro = 'Trapezi';
      return {'macro': 'Schiena', 'micro': micro};
    }
    if (cat.contains('gambe') || cat.contains('quadricipiti') || cat.contains('femorali') || cat.contains('glutei') || cat.contains('polpacci') || cat.contains('adduttori') || cat.contains('calf')) {
      String micro = 'Gambe (Generale)';
      if (cat.contains('quadricipiti')) micro = 'Quadricipiti';
      if (cat.contains('femorali') || cat.contains('ischiocrurali')) micro = 'Femorali';
      if (cat.contains('glutei')) micro = 'Glutei';
      if (cat.contains('polpacci') || cat.contains('calf')) micro = 'Polpacci';
      if (cat.contains('adduttori') || cat.contains('abduttori')) micro = 'Adduttori / Abduttori';
      return {'macro': 'Gambe', 'micro': micro};
    }
    if (cat.contains('spalle') || cat.contains('spalla') || cat.contains('deltoidi')) {
      String micro = 'Spalle (Generale)';
      if (cat.contains('frontali')) micro = 'Deltoidi Anteriori';
      if (cat.contains('laterali')) micro = 'Deltoidi Laterali';
      if (cat.contains('posteriori')) micro = 'Deltoidi Posteriori';
      if (cat.contains('cuffia')) micro = 'Cuffia dei Rotatori';
      return {'macro': 'Spalle', 'micro': micro};
    }
    if (cat.contains('bicipiti') || cat.contains('tricipiti') || cat.contains('avambracci') || cat.contains('braccia') || cat.contains('polsi')) {
      String micro = 'Braccia (Generale)';
      if (cat.contains('bicipiti')) micro = 'Bicipiti';
      if (cat.contains('tricipiti')) micro = 'Tricipiti';
      if (cat.contains('avambracci') || cat.contains('polsi')) micro = 'Avambracci';
      return {'macro': 'Braccia', 'micro': micro};
    }
    if (cat.contains('addom') || cat.contains('core') || cat.contains('obliqui')) {
      String micro = 'Addome Centrale';
      if (cat.contains('obliqui')) micro = 'Obliqui';
      return {'macro': 'Addome e Core', 'micro': micro};
    }
    
    String micro = 'Vari ed Eventuali';
    if (cat.contains('stretching') || cat.contains('flessibilità') || cat.contains('massaggio') || cat.contains('smr')) micro = 'Stretching & Mobilità';
    if (cat.contains('cardio') || cat.contains('corsa') || cat.contains('atletica')) micro = 'Cardio';
    if (cat.contains('olimpico') || cat.contains('strongman') || cat.contains('potenza') || cat.contains('pliometria')) micro = 'Pesistica / Potenza';
    if (cat.contains('total body')) micro = 'Total Body';
    return {'macro': 'Funzionale & Altro', 'micro': micro};
  }

  String _traduciNome(String nomeOriginale) {
    return DizionarioEsercizi.daIngleseAItaliano[nomeOriginale] ?? nomeOriginale;
  }

  String _normalizzaNome(String nome) {
    return nome.trim().toLowerCase();
  }

  Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? storicoSalvato = prefs.getString('storico_salvato');
    if (storicoSalvato != null) {
      final List<dynamic> jsonDecodificato = jsonDecode(storicoSalvato);
      storico = jsonDecodificato.map((e) => Allenamento.fromJson(e)).toList();
      
      Map<String, String> nomiUnivoci = {}; 
      for (var allenamento in storico) {
        for (var es in allenamento.scheda.esercizi) {
          bool ignoraPerGrafico = es.tecniche.contains('Back off') || es.tecniche.contains('Drop Set') || es.tecniche.contains('Stripping');
          if (ignoraPerGrafico) continue;

          if (es.serieAttive.any((s) => s.isCompletata && s.peso.isNotEmpty && s.tipo != 'Avvicinamento')) {
            String nomeTradotto = _traduciNome(es.nome);
            String nomePulito = _normalizzaNome(nomeTradotto);
            nomiUnivoci[nomePulito] = nomeTradotto.trim(); 
          }
        }
      }
      
      List<String> listaNomi = nomiUnivoci.values.toList();
      listaNomi.sort();
      nomiEserciziGrafico = listaNomi;

      if (nomiEserciziGrafico.isNotEmpty) esercizioSelezionato = nomiEserciziGrafico.first;
    }

    final String? customSalvati = prefs.getString('esercizi_custom_db_v2');
    if (customSalvati != null) {
      eserciziCustom = List<Map<String, String>>.from(jsonDecode(customSalvati).map((item) => Map<String, String>.from(item)));
    }

    final String? datiProfiloStr = prefs.getString('profilo_dati_utente');
    if (datiProfiloStr != null) {
      Map<String, dynamic> dati = jsonDecode(datiProfiloStr);
      _nomeUtenteController.text = dati['nome'] ?? '';
      _pesoController.text = dati['peso'] ?? '';
      _altezzaController.text = dati['altezza'] ?? '';
      _misureController.text = dati['misure'] ?? '';
      _noteExtraController.text = dati['note'] ?? '';
    } else {
      final String? notevecchie = prefs.getString('note_generali');
      if (notevecchie != null) _noteExtraController.text = notevecchie;
    }

    eserciziDalWeb = await ApiEsercizi.ottieniEserciziTradotti();

    if (mounted) setState(() { _isLoading = false; });

    _sincronizzaCloud();
  }

  Future<void> _sincronizzaCloud() async {
    if (userId.isEmpty) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('storico_atleti')
          .where('atletaId', isEqualTo: userId)
          .orderBy('data', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        List<Allenamento> storicoCloud = snapshot.docs.map((doc) => Allenamento.fromJson(doc.data())).toList();
        if (storicoCloud.length > storico.length) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('storico_salvato', jsonEncode(storicoCloud.map((e) => e.toJson()).toList()));
          if (mounted) {
            setState(() {
              storico = storicoCloud;
              _aggiornaInterfacciaGrafici();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Sincronizzazione fallita: $e");
    }
  }

  void _aggiornaInterfacciaGrafici() {
    Map<String, String> nomiUnivoci = {}; 
    for (var allenamento in storico) {
      for (var es in allenamento.scheda.esercizi) {
        if (es.serieAttive.any((s) => s.isCompletata && s.peso.isNotEmpty)) {
          String nomeTradotto = _traduciNome(es.nome);
          nomiUnivoci[_normalizzaNome(nomeTradotto)] = nomeTradotto.trim();
        }
      }
    }
    List<String> listaNomi = nomiUnivoci.values.toList();
    listaNomi.sort();
    nomiEserciziGrafico = listaNomi;
    if (nomiEserciziGrafico.isNotEmpty && esercizioSelezionato == null) {
      esercizioSelezionato = nomiEserciziGrafico.first;
    }
  }

  Future<void> _aggiungiEsercizioManualmente() async {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo Esercizio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nuovoEsercizioController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome Esercizio', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _categoriaNuovoEsercizio, 
                decoration: const InputDecoration(labelText: 'Gruppo Muscolare', border: OutlineInputBorder()),
                items: ['Petto', 'Schiena', 'Gambe', 'Spalle', 'Bicipiti', 'Tricipiti', 'Addominali', 'Altro']
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setDialogState(() => _categoriaNuovoEsercizio = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () async {
                String nome = _nuovoEsercizioController.text.trim();
                if (nome.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  setState(() {
                    eserciziCustom.add({'nome': nome, 'categoria': _categoriaNuovoEsercizio});
                  });
                  await prefs.setString('esercizi_custom_db_v2', jsonEncode(eserciziCustom));
                  _nuovoEsercizioController.clear();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvaDatiProfilo() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> datiPersonali = {
      'nome': _nomeUtenteController.text.trim(),
      'peso': _pesoController.text.trim(),
      'altezza': _altezzaController.text.trim(),
      'misure': _misureController.text.trim(),
      'note': _noteExtraController.text.trim(),
    };
    
    await prefs.setString('profilo_dati_utente', jsonEncode(datiPersonali));

    if (userId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('utenti').doc(userId).set({
        'datiFisici': datiPersonali,
        'ultimaModifica': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus(); 
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dati salvati con successo! ✅'), backgroundColor: Colors.green));
  }

  List<FlSpot> _generaPuntiGraficoLineare() {
    if (esercizioSelezionato == null) return [];
    List<FlSpot> punti = [];
    List<Allenamento> storicoOrdinato = List.from(storico)..sort((a, b) => a.data.compareTo(b.data));
    int numeroSessione = 0;
    String selezPulito = _normalizzaNome(esercizioSelezionato!);

    for (var allenamento in storicoOrdinato) {
      for (var es in allenamento.scheda.esercizi) {
        
        String nomeStoricoTradotto = _normalizzaNome(_traduciNome(es.nome));
        
        if (nomeStoricoTradotto == selezPulito) {
          bool ignoraPerGrafico = es.tecniche.contains('Back off') || es.tecniche.contains('Drop Set') || es.tecniche.contains('Stripping');
          if (ignoraPerGrafico) continue;

          double maxPeso = 0;
          for (var s in es.serieAttive) {
            if (s.isCompletata && s.peso.isNotEmpty && s.tipo != 'Avvicinamento') {
              double? p = double.tryParse(s.peso.replaceAll(',', '.')); 
              if (p != null && p > maxPeso) maxPeso = p;
            }
          }
          if (maxPeso > 0) {
            punti.add(FlSpot(numeroSessione.toDouble(), maxPeso));
            numeroSessione++;
          }
        }
      }
    }
    return punti;
  }

  List<PieChartSectionData> _generaDatiTorta() {
    Map<String, int> conteggio = {};
    int totaleSerie = 0;

    for (var allenamento in storico) {
      for (var es in allenamento.scheda.esercizi) {
        String cat = 'Altro';
        
        String nomeTradotto = _traduciNome(es.nome);
        var matchDb = eserciziDalWeb.where((e) => e['nome'] == nomeTradotto);
        
        if (matchDb.isNotEmpty) {
          var classificazione = _classificaEsercizio(matchDb.first['categoria']);
          cat = classificazione['macro']!; 
        } else {
          var matchCustom = eserciziCustom.where((e) => e['nome'] == nomeTradotto);
          if (matchCustom.isNotEmpty) {
            var classificazione = _classificaEsercizio(matchCustom.first['categoria'] ?? 'Altro');
            cat = classificazione['macro']!;
          }
        }
        
        int serieFatte = es.serieAttive.where((s) => s.isCompletata && s.tipo != 'Avvicinamento').length;
        if (serieFatte > 0) {
          conteggio[cat] = (conteggio[cat] ?? 0) + serieFatte;
          totaleSerie += serieFatte;
        }
      }
    }

    if (totaleSerie == 0) return [];

    List<Color> colori = [Colors.deepOrange, Colors.blue, Colors.green, Colors.purple, Colors.amber, Colors.teal, Colors.redAccent, Colors.indigo];
    int i = 0;
    
    return conteggio.entries.map((e) {
      final double percentuale = (e.value / totaleSerie) * 100;
      final color = colori[i % colori.length];
      i++;
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${percentuale.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        badgeWidget: Text(e.key, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        badgePositionPercentageOffset: 1.3,
      );
    }).toList();
  }

  Widget _buildImmagineAnimata(String url1, String url2) {
    if (url2.isEmpty) {
      return CachedNetworkImage(
        imageUrl: url1, height: 200, fit: BoxFit.contain,
        placeholder: (c, u) => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        errorWidget: (c, u, e) => const SizedBox(height: 200, child: Center(child: Icon(Icons.fitness_center, color: Colors.grey, size: 50))),
      );
    }
    return ImageSwitcher(url1: url1, url2: url2);
  }

  void _mostraDettagliEsercizio(Map<String, dynamic> esercizio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        bool haImmagine1 = esercizio['video'] != null && esercizio['video'].toString().isNotEmpty;
        bool haImmagine2 = esercizio['video2'] != null && esercizio['video2'].toString().isNotEmpty;

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(esercizio['nome'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              
              if (haImmagine1)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white,
                    child: _buildImmagineAnimata(esercizio['video'], haImmagine2 ? esercizio['video2'] : ''),
                  ),
                ),
                
              const SizedBox(height: 20),
              
              if (esercizio['note'] != null && esercizio['note'].toString().isNotEmpty) ...[
                const Text('Esecuzione:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                  child: SingleChildScrollView(
                    child: Text(esercizio['note'], style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _eliminaEsercizio(String nome) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      eserciziCustom.removeWhere((e) => e['nome'] == nome);
    });
    await prefs.setString('esercizi_custom_db_v2', jsonEncode(eserciziCustom));
  }

  // 👇 LA TAB DEI GRAFICI AGGIORNATA CON I MARKER DEL CALENDARIO
  Widget _buildGraficiTab() {
    List<FlSpot> puntiLineari = _generaPuntiGraficoLineare();
    List<PieChartSectionData> puntiTorta = _generaDatiTorta();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Calendario Allenamenti', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TableCalendar(
                firstDay: DateTime.utc(2023, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Mese'},
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerStyle: const HeaderStyle(titleCentered: true, formatButtonVisible: false, titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                ),
                onPageChanged: (focusedDay) { _focusedDay = focusedDay; },
                
                eventLoader: (day) {
                  return storico.where((a) => a.data.year == day.year && a.data.month == day.month && a.data.day == day.day).toList();
                },
                
                // IL COSTRUTTORE DEI PALLINI SOTTO I GIORNI
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    if (events.isEmpty) return const SizedBox();

                    bool haAllenamento = false;
                    bool haPR = false;

                    // Controlla il tipo di evento
                    for (var event in events) {
                      Allenamento a = event as Allenamento;
                      if (a.scheda.nome.contains('🏆 TEST PR')) {
                        haPR = true;
                      } else {
                        haAllenamento = true;
                      }
                    }

                    return Positioned(
                      bottom: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (haAllenamento)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              width: 8, height: 8,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                            ),
                          if (haPR)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              width: 8, height: 8,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.purpleAccent),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          const Text('Distribuzione Muscolare (Set)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 16),
          if (puntiTorta.isEmpty)
            const Text('Nessun dato muscolare disponibile.', style: TextStyle(color: Colors.grey))
          else
            SizedBox(
              height: 250,
              child: PieChart(PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, sections: puntiTorta)),
            ),
          const SizedBox(height: 40),

          const Text('Curva della Forza', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 8),
          if (nomiEserciziGrafico.isEmpty)
            const Text('Completa un allenamento per vedere i progressi.', style: TextStyle(color: Colors.grey))
          else ...[
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Seleziona Esercizio', 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.fitness_center, color: Colors.deepOrange),
                filled: true, fillColor: Colors.black12,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: esercizioSelezionato, isDense: true,
                  items: nomiEserciziGrafico.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => esercizioSelezionato = v),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: puntiLineari.isEmpty 
                ? const Center(child: Text('Nessun dato di peso.', style: TextStyle(color: Colors.grey)))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1)), 
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), 
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('#${value.toInt() + 1}', style: const TextStyle(fontSize: 12, color: Colors.grey))))),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, getTitlesWidget: (value, meta) => Text('${value.toInt()}kg', style: const TextStyle(fontSize: 12, color: Colors.grey)))), 
                      ),
                      borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.5), width: 1), left: BorderSide(color: Colors.grey.withOpacity(0.5), width: 1))),
                      lineBarsData: [
                        LineChartBarData(
                          spots: puntiLineari, isCurved: true, color: Colors.deepOrange, barWidth: 4, 
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: Colors.deepOrange.withOpacity(0.15))
                        )
                      ],
                    ),
                  ),
            ),
          ],
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildLibreriaTab() {
    List<Map<String, dynamic>> tuttiEsercizi = [];
    for (var e in catalogoEsercizi) { tuttiEsercizi.add({'nome': e.nome, 'categoria': e.categoria, 'video': '', 'video2': '', 'note': ''}); }
    for (var e in eserciziCustom) { tuttiEsercizi.add({'nome': e['nome'], 'categoria': e['categoria'], 'video': '', 'video2': '', 'note': ''}); }
    tuttiEsercizi.addAll(eserciziDalWeb);

    String q = _searchQuery.toLowerCase().trim();
    var eserciziFiltrati = tuttiEsercizi.where((e) => e['nome'].toString().toLowerCase().contains(q)).toList();

    Map<String, Map<String, dynamic>> eserciziUnici = {};
    for (var e in eserciziFiltrati) { eserciziUnici[e['nome']] = e; }

    Map<String, Map<String, List<Map<String, dynamic>>>> libreriaOrganizzata = {};

    for (var es in eserciziUnici.values) {
      String catGrezza = es['categoria']?.toString() ?? 'Altro';
      var classificazione = _classificaEsercizio(catGrezza);
      String macro = classificazione['macro']!;
      String micro = classificazione['micro']!;

      libreriaOrganizzata.putIfAbsent(macro, () => {});
      libreriaOrganizzata[macro]!.putIfAbsent(micro, () => []);
      libreriaOrganizzata[macro]![micro]!.add(es);
    }

    List<String> macroOrdinate = libreriaOrganizzata.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Cerca esercizio...', 
              prefixIcon: const Icon(Icons.search, color: Colors.deepOrange), 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)), 
              contentPadding: const EdgeInsets.symmetric(vertical: 0), 
              filled: true, 
              fillColor: Colors.black.withOpacity(0.1)
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: macroOrdinate.length,
            itemBuilder: (context, i) {
              String macro = macroOrdinate[i];
              var microMap = libreriaOrganizzata[macro]!;
              List<String> microOrdinate = microMap.keys.toList()..sort();

              int totMacro = microMap.values.fold(0, (sum, list) => sum + list.length);

              return ExpansionTile(
                leading: Icon(_prendiIconaMuscolo(macro), color: Colors.deepOrange, size: 28),
                title: Text("$macro ($totMacro)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                children: microOrdinate.map((micro) {
                  var eserciziMicro = microMap[micro]!..sort((a,b) => a['nome'].compareTo(b['nome']));

                  return Padding(
                    padding: const EdgeInsets.only(left: 20.0), 
                    child: ExpansionTile(
                      iconColor: Colors.grey,
                      collapsedIconColor: Colors.grey,
                      title: Text("$micro (${eserciziMicro.length})", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70, fontSize: 15)),
                      children: eserciziMicro.map((esercizio) {
                        bool isCustom = eserciziCustom.any((e) => e['nome'] == esercizio['nome']);
                        bool haVideo = esercizio['video'] != null && esercizio['video'].toString().isNotEmpty;
                        
                        return ListTile(
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          title: Text(esercizio['nome'], style: const TextStyle(fontSize: 14)),
                          leading: haVideo ? const Icon(Icons.play_circle_outline, color: Colors.deepOrange, size: 20) : const Icon(Icons.fitness_center, size: 16, color: Colors.grey),
                          trailing: isCustom ? IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _eliminaEsercizio(esercizio['nome'])) : null,
                          onTap: () => _mostraDettagliEsercizio(esercizio),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNoteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [Icon(Icons.assignment_ind, color: Colors.deepOrange), SizedBox(width: 8), Text('I Tuoi Dati Fisici', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 20),
          TextField(controller: _nomeUtenteController, decoration: const InputDecoration(labelText: 'Il tuo Nome', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: TextField(controller: _pesoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Peso Corporeo (kg)', prefixIcon: Icon(Icons.monitor_weight), border: OutlineInputBorder()))),
              const SizedBox(width: 16),
              Expanded(child: TextField(controller: _altezzaController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Altezza (cm)', prefixIcon: Icon(Icons.height), border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _misureController, maxLines: 4, decoration: const InputDecoration(labelText: 'Misure (Petto, Braccia, Vita, Gambe...)', alignLabelWithHint: true, prefixIcon: Icon(Icons.straighten), border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _noteExtraController, maxLines: 4, decoration: const InputDecoration(labelText: 'Note Generali / Obiettivi', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes), border: OutlineInputBorder())),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white), 
            onPressed: _salvaDatiProfilo, 
            icon: const Icon(Icons.save), 
            label: const Text('Salva e Sincronizza Cloud', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nuovoEsercizioController.dispose();
    _nomeUtenteController.dispose();
    _pesoController.dispose();
    _altezzaController.dispose();
    _misureController.dispose();
    _noteExtraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo Personale'),
        bottom: TabBar(
          controller: _tabController, indicatorColor: Colors.deepOrange,
          tabs: const [Tab(icon: Icon(Icons.show_chart), text: 'Grafici'), Tab(icon: Icon(Icons.menu_book), text: 'Esercizi'), Tab(icon: Icon(Icons.assignment_ind), text: 'Dati')],
        ),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(
        controller: _tabController,
        children: [ _buildGraficiTab(), _buildLibreriaTab(), _buildNoteTab() ],
      ),
      floatingActionButton: _tabController.index == 1 ? FloatingActionButton(
        backgroundColor: Colors.deepOrange,
        onPressed: _aggiungiEsercizioManualmente,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }
}

// <--- CLASSE SPOSTATA CORRETTAMENTE FUORI DALLO STATE
class ImageSwitcher extends StatefulWidget {
  final String url1;
  final String url2;

  const ImageSwitcher({super.key, required this.url1, required this.url2});

  @override
  State<ImageSwitcher> createState() => _ImageSwitcherState();
}

class _ImageSwitcherState extends State<ImageSwitcher> {
  bool _showFirst = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _showFirst = !_showFirst;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 500),
      crossFadeState: _showFirst ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: CachedNetworkImage(
        imageUrl: widget.url1, height: 200, fit: BoxFit.contain,
        placeholder: (c, u) => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        errorWidget: (c, u, e) => const SizedBox(height: 200, child: Center(child: Icon(Icons.fitness_center, color: Colors.grey))),
      ),
      secondChild: CachedNetworkImage(
        imageUrl: widget.url2, height: 200, fit: BoxFit.contain,
        placeholder: (c, u) => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        errorWidget: (c, u, e) => const SizedBox(height: 200, child: Center(child: Icon(Icons.fitness_center, color: Colors.grey))),
      ),
    );
  }
}