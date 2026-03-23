import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math'; 
import '../models/scheda.dart';
import '../models/allenamento.dart';
import '../models/esercizio.dart';
import '../models/serie.dart';
import 'crea_esercizio.dart';
import '../services/api_esercizi.dart';
import '../services/dizionario_esercizi.dart';

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
  List<Map<String, dynamic>> _databaseEsercizi = [];
  Timer? _bozzaDebounce;

  String get _bozzaKey => 'workout_bozza_${widget.scheda.nome}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _caricaDatabase(); 
    _caricaBozzaWorkout();
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

  Future<void> _caricaBozzaWorkout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bozzaJson = prefs.getString(_bozzaKey);
      if (bozzaJson == null || !mounted) return;

      final decoded = jsonDecode(bozzaJson);
      if (decoded is! Map<String, dynamic>) return;
      final schedaMap = decoded['scheda'];
      if (schedaMap is! Map) return;

      final bozza = Scheda.fromJson(Map<String, dynamic>.from(schedaMap));
      setState(() {
        widget.scheda.nome = bozza.nome;
        widget.scheda.livello = bozza.livello;
        widget.scheda.categoria = bozza.categoria;
        widget.scheda.esercizi = bozza.esercizi;
      });
    } catch (e) {
      debugPrint('Errore caricamento bozza workout: $e');
    }
  }

  Future<void> _salvaBozzaWorkout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _bozzaKey,
        jsonEncode({
          'scheda': widget.scheda.toJson(),
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
    final dati = await ApiEsercizi.ottieniEserciziTradotti();
    if (mounted) {
      setState(() {
        _databaseEsercizi = dati;
      });
    }
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
        
        await FirebaseFirestore.instance.collection('storico_atleti').add(datiCloud);
      }

      if (!mounted) return;
      await _pulisciBozzaWorkout();
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

  Map<String, String>? _getDatiPrecedenti(String nomeEs, int indiceSerie) {
    String nomeTargetIta = _traduciNome(nomeEs).toLowerCase().trim();

    for (var allenamento in widget.storico.reversed) {
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
    
    for (var allenamento in widget.storico.reversed) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)), 
        actions: [
          IconButton(icon: const Icon(Icons.calculate, color: Colors.white), tooltip: 'Calcola Dischi', onPressed: _apriCalcolatoreDischi),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final nuovo = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaEsercizioScreen()));
              if (nuovo != null) {
                setState(() {
                  widget.scheda.esercizi.add(nuovo);
                });
                _scheduleBozzaSave();
              }
            },
          ),
        ],
      ),
      body: ReorderableListView(
        padding: const EdgeInsets.only(bottom: 100),
        onReorder: (int oldIndex, int newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final esercizio = widget.scheda.esercizi.removeAt(oldIndex);
            widget.scheda.esercizi.insert(newIndex, esercizio);
          });
          _scheduleBozzaSave();
        },
        children: [
          for (int i = 0; i < widget.scheda.esercizi.length; i++)
            _buildEsercizioItem(widget.scheda.esercizi[i], i),
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
    
    bool isSuperSet = esercizio.tecniche.any((t) => t.toLowerCase().contains('super'));
    bool prevIsSuperSet = index > 0 && widget.scheda.esercizi[index - 1].tecniche.any((t) => t.toLowerCase().contains('super'));
    bool nextIsSuperSet = index < widget.scheda.esercizi.length - 1 && widget.scheda.esercizi[index + 1].tecniche.any((t) => t.toLowerCase().contains('super'));

    // 👇 RICERCA NEL DATABASE BLINDATA (Ignora maiuscole)
    String nomeTargetIta = _traduciNome(esercizio.nome).toLowerCase().trim();
    final matchDb = _databaseEsercizi.cast<Map<String, dynamic>?>().firstWhere(
      (e) {
        if (e == null) return false;
        String dbNome = e['nome'].toString().toLowerCase().trim();
        String dbNomeTradotto = _traduciNome(e['nome'].toString()).toLowerCase().trim();
        String targetOriginale = esercizio.nome.toLowerCase().trim();

        return dbNomeTradotto == nomeTargetIta || 
               dbNome == nomeTargetIta || 
               dbNomeTradotto == targetOriginale || 
               dbNome == targetOriginale;
      }, 
      orElse: () => null
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
          onDismissed: (direction) { setState(() { widget.scheda.esercizi.removeAt(index); }); },
          onUpdate: (details) {
            if (details.reached == 1.0) {
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
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.drag_indicator, color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(esercizio.nome, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: tuttoFatto ? Colors.green : Colors.white))),
                      if (matchDb != null) IconButton(icon: const Icon(Icons.swap_horiz, color: Colors.blueAccent, size: 22), onPressed: () => _mostraAlternative(esercizio.nome, matchDb['categoria'])),
                      IconButton(icon: const Icon(Icons.history, color: Colors.amber, size: 22), onPressed: () => _mostraStoricoEsercizio(esercizio.nome)),
                      if (matchDb != null) IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.deepOrange, size: 28), onPressed: () => _mostraDettagliEsercizio(matchDb)),
                      IconButton(icon: const Icon(Icons.edit, color: Colors.lightBlueAccent, size: 20), onPressed: () async {
                        final mod = await Navigator.push(context, MaterialPageRoute(builder: (c) => CreaEsercizioScreen(esercizioDaModificare: esercizio)));
                        if (mod != null) {
                          setState(() => widget.scheda.esercizi[index] = mod);
                          _scheduleBozzaSave();
                        }
                      }),
                    ],
                  ),
                  
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

                  const Divider(height: 20),
                  ...esercizio.serieAttive.asMap().entries.map((entry) {
                    int sIdx = entry.key;
                    Serie serie = entry.value;
                    final prev = _getDatiPrecedenti(esercizio.nome, sIdx);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: serie.isCompletata ? Colors.green.withValues(alpha: 0.1) : Colors.black12, borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          SizedBox(width: 30, child: Text('${sIdx + 1}º', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          Expanded(flex: 3, child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: prev != null ? '${prev['peso']}kg' : 'Kg', border: InputBorder.none, isDense: true, hintStyle: const TextStyle(color: Colors.white24)),
                            controller: TextEditingController(text: serie.peso)..selection = TextSelection.collapsed(offset: serie.peso.length),
                            onChanged: (v) {
                              serie.peso = v;
                              _scheduleBozzaSave();
                            },
                          )),
                          Expanded(flex: 3, child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: prev != null ? '${prev['reps']}r' : 'Reps', border: InputBorder.none, isDense: true, hintStyle: const TextStyle(color: Colors.white24)),
                            controller: TextEditingController(text: serie.ripetizioniFatte)..selection = TextSelection.collapsed(offset: serie.ripetizioniFatte.length),
                            onChanged: (v) {
                              serie.ripetizioniFatte = v;
                              _scheduleBozzaSave();
                            },
                          )),
                          Expanded(flex: 2, child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: prev != null && prev['rpe'] != null ? 'RPE ${prev['rpe']}' : 'RPE', border: InputBorder.none, isDense: true, hintStyle: const TextStyle(color: Colors.white12, fontSize: 11)),
                            style: const TextStyle(color: Colors.amber, fontSize: 14),
                            controller: TextEditingController(text: serie.rpe)..selection = TextSelection.collapsed(offset: serie.rpe.length),
                            onChanged: (v) {
                              serie.rpe = v;
                              _scheduleBozzaSave();
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
                    );
                  }).toList(),
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