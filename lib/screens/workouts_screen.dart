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
import '../services/ai_service.dart';
import '../services/dizionario_esercizi.dart';
import 'dettaglio_scheda_screen.dart';
import 'storico_screen.dart';
import 'crea_scheda.dart';
import 'pr_mode_screen.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  List<Scheda> mieSchede = [];
  List<Allenamento> storico = []; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _caricaDati().then((_) => _sincronizzaColCoach(silenzioso: true));
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
    if (mounted) {
      setState(() {
        if (datiSalvati != null) mieSchede = (jsonDecode(datiSalvati) as List).map((e) => Scheda.fromJson(e)).toList();
        if (storicoSalvato != null) storico = (jsonDecode(storicoSalvato) as List).map((e) => Allenamento.fromJson(e)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _salvaDati() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schede_salvate', jsonEncode(mieSchede.map((e) => e.toJson()).toList()));
    await prefs.setString('storico_salvato', jsonEncode(storico.map((e) => e.toJson()).toList()));
  }

  void _duplicaScheda(Scheda schedaOriginale) {
    final Map<String, dynamic> jsonCopia = schedaOriginale.toJson();
    jsonCopia['nome'] = '${schedaOriginale.nome} (Copia)';
    
    final Scheda nuovaScheda = Scheda.fromJson(jsonCopia);
    
    setState(() {
      mieSchede.add(nuovaScheda);
    });
    
    _salvaDati();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scheda duplicata con successo! 📄🔄'), backgroundColor: Colors.blueAccent)
    );
  }

  Future<void> _rinominaScheda(Scheda scheda) async {
    TextEditingController controller = TextEditingController(text: scheda.nome);
    String? nuovoNome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rinomina Scheda', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller, 
          decoration: const InputDecoration(hintText: 'Nuovo nome...', border: OutlineInputBorder()), 
          autofocus: true
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white), 
            onPressed: () => Navigator.pop(context, controller.text.trim()), 
            child: const Text('Salva')
          ),
        ],
      )
    );

    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != scheda.nome) {
      setState(() {
        scheda.nome = nuovoNome;
      });
      _salvaDati();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nome aggiornato! ✏️'), backgroundColor: Colors.green));
    }
  }

  Future<void> _rinominaCategoria(String vecchioNome) async {
    TextEditingController controller = TextEditingController(text: vecchioNome);
    String? nuovoNome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rinomina Cartella', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Es: Settimana 1...', border: OutlineInputBorder()), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Salva')),
        ],
      )
    );
    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != vecchioNome) {
      setState(() { for (var scheda in mieSchede) { if (scheda.categoria == vecchioNome) scheda.categoria = nuovoNome; } });
      _salvaDati();
    }
  }

  Future<void> _esportaCartellaInPDF(String nomeCategoria, List<Scheda> schede) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)));
    try {
      final pdf = pw.Document();
      final purpleColor = PdfColor.fromHex('#9C27B0');
      final greyText = PdfColor.fromHex('#757575');
      final dividerColor = PdfColor.fromHex('#E0E0E0');

      for (var scheda in schede) {
        pdf.addPage(
          pw.MultiPage(
            maxPages: 100, pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40), 
            build: (pw.Context context) {
              List<pw.Widget> foglio = [];
              foglio.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(scheda.nome.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text(nomeCategoria, style: pw.TextStyle(fontSize: 12, color: greyText)),
              ]));
              foglio.add(pw.Divider(thickness: 1, color: dividerColor));
              
              if (scheda.livello.isNotEmpty) foglio.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 20, top: 4), child: pw.Text('Livello: ${scheda.livello}', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: greyText))));
              else foglio.add(pw.SizedBox(height: 20));

              for (int i = 0; i < scheda.esercizi.length; i++) {
                var es = scheda.esercizi[i];
                int numAvvicinamento = es.serieAttive.where((s) => s.tipo == 'Avvicinamento').length;
                int numWorking = es.serieAttive.where((s) => s.tipo != 'Avvicinamento').length;
                if(numWorking == 0) numWorking = es.serieAttive.length; 

                bool isSuperSet = es.tecniche.any((t) => t.toLowerCase().contains('super'));
                bool prevIsSuperSet = i > 0 && scheda.esercizi[i - 1].tecniche.any((t) => t.toLowerCase().contains('super'));
                var altreTecniche = es.tecniche.where((t) => !t.toLowerCase().contains('super')).toList();

                if (isSuperSet && !prevIsSuperSet) foglio.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 8, bottom: 8), child: pw.Text('>>> INIZIO SUPERSET', style: pw.TextStyle(color: purpleColor, fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2))));

                foglio.add(
                  pw.Padding(
                    padding: pw.EdgeInsets.only(left: isSuperSet ? 20 : 0, bottom: 16),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                          pw.Text('- ${es.nome}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(width: 10),
                          pw.Text('$numWorking set  |  ${es.ripetizioni} reps  |  Rec: ${es.recupero}s', style: const pw.TextStyle(fontSize: 11)),
                        ]),
                        if (numAvvicinamento > 0 || altreTecniche.isNotEmpty || (es.note != null && es.note!.isNotEmpty))
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 12, top: 4),
                            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                              if (numAvvicinamento > 0) pw.Text('Avvicinamento: $numAvvicinamento set', style: pw.TextStyle(fontSize: 10, color: greyText)),
                              if (altreTecniche.isNotEmpty) pw.Text('Tecniche: ${altreTecniche.join(", ")}', style: pw.TextStyle(fontSize: 10, color: greyText)),
                              if (es.note != null && es.note!.isNotEmpty) pw.Text('Note: ${es.note}', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: greyText)),
                            ])
                          ),
                        pw.SizedBox(height: 8),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 12),
                          child: pw.Wrap(spacing: 20, runSpacing: 8, children: List.generate(numWorking, (idx) => pw.Text('Set ${idx + 1}:  ____ kg  x  ____', style: const pw.TextStyle(fontSize: 11, color: PdfColors.black)))),
                        ),
                      ]
                    )
                  )
                );
              }
              return foglio;
            },
          ),
        );
      }
      final directory = await getTemporaryDirectory();
      String nomeFile = nomeCategoria.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_'); 
      final file = File('${directory.path}/$nomeFile.pdf');
      await file.writeAsBytes(await pdf.save());
      if (!mounted) return;
      Navigator.pop(context); 
      await Share.shareXFiles([XFile(file.path)], text: 'Ecco le tue schede per il blocco: $nomeCategoria 💪', subject: 'Schede Allenamento Tiger');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore creazione PDF: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<Scheda>> schedeRaggruppate = {};
    for (var scheda in mieSchede) {
      if (!schedeRaggruppate.containsKey(scheda.categoria)) schedeRaggruppate[scheda.categoria] = [];
      schedeRaggruppate[scheda.categoria]!.add(scheda);
    }
    List<String> categorie = schedeRaggruppate.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le tue Schede'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.greenAccent),
            onPressed: () async {
              showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
              await _sincronizzaColCoach(silenzioso: false);
              if (mounted) Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.document_scanner, color: Colors.blueAccent),
            onPressed: () async {
            final picker = ImagePicker();
            final XFile? foto = await picker.pickImage(source: ImageSource.gallery);
            if (foto != null) {
              if (!mounted) return;
              showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)));
              List<Scheda>? schedeImportate = await AiService.analizzaFotoScheda(foto);
              if (!mounted) return; 
              Navigator.pop(context); 
              if (schedeImportate != null && schedeImportate.isNotEmpty) {
                setState(() { mieSchede.addAll(schedeImportate); });
                _salvaDati();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${schedeImportate.length} schede importate! 🤖💪')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore durante la scansione. Riprova! ❌')));
              }
            }
          },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => StoricoScreen(storico: storico, onUpdate: () => _salvaDati()))).then((_) { setState(() {}); });
            },
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (c) => const PRModeScreen()));
                    _caricaDati(); 
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.deepOrange, Colors.redAccent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.deepOrange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.fitness_center, color: Colors.white, size: 36),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MODALITÀ PR', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                              Text('Calcola % e carica il bilanciere', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: categorie.isEmpty 
                  ? const Center(child: Text('Nessuna scheda. Premi + o chiedi al tuo Coach!', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: categorie.length, 
                      itemBuilder: (context, index) {
                        String nomeCategoria = categorie[index];
                        List<Scheda> schedeDiQuestaCategoria = schedeRaggruppate[nomeCategoria]!;

                        return DragTarget<Scheda>(
                          onWillAcceptWithDetails: (details) => details.data.categoria != nomeCategoria,
                          onAcceptWithDetails: (details) {
                            setState(() { details.data.categoria = nomeCategoria; });
                            _salvaDati();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scheda spostata in "$nomeCategoria"! 📂'), backgroundColor: Colors.green));
                          },
                          builder: (context, candidateData, rejectedData) {
                            bool isHovering = candidateData.isNotEmpty;

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                              decoration: BoxDecoration(
                                color: isHovering ? Colors.deepOrange.withOpacity(0.1) : Colors.transparent,
                                border: isHovering ? Border.all(color: Colors.deepOrange, width: 2) : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ExpansionTile(
                                initiallyExpanded: true, 
                                leading: Icon(nomeCategoria == 'Dal Coach 🐯' ? Icons.local_fire_department : Icons.folder, color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(nomeCategoria, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange))),
                                    IconButton(icon: const Icon(Icons.picture_as_pdf, size: 22, color: Colors.redAccent), onPressed: () => _esportaCartellaInPDF(nomeCategoria, schedeDiQuestaCategoria)),
                                    IconButton(
                                      icon: const Icon(Icons.auto_awesome, size: 22, color: Colors.purpleAccent),
                                      onPressed: () async {
                                        showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
                                        String? recensione = await AiService.valutaCartella(nomeCategoria, schedeDiQuestaCategoria);
                                        if (!context.mounted) return;
                                        Navigator.pop(context); 
                                        showModalBottomSheet(
                                          context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1E1E1E),
                                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                          builder: (context) => Padding(
                                            padding: const EdgeInsets.all(24.0),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start, 
                                              children: [
                                                const Row(children: [Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 28), SizedBox(width: 8), Text('Analisi del Coach AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.purpleAccent))]),
                                                const SizedBox(height: 16),
                                                Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6), child: SingleChildScrollView(child: Text(recensione ?? 'Errore.', style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.white)))),
                                                const SizedBox(height: 24),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                                                  onPressed: () => Navigator.pop(context), 
                                                  child: const Text('Ho capito, grazie Coach!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                )
                                              ],
                                            ),
                                          )
                                        );
                                      },
                                    ),
                                    IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.grey), onPressed: () => _rinominaCategoria(nomeCategoria)),
                                  ],
                                ),
                                children: schedeDiQuestaCategoria.map((scheda) {
                                  int indiceReale = mieSchede.indexOf(scheda);
                                  Widget cardScheda = Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      child: ListTile(
                                        leading: const CircleAvatar(child: Icon(Icons.list_alt)),
                                        title: Text(scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)), 
                                        subtitle: Text('${scheda.esercizi.length} esercizi • ${scheda.livello}\n(Tieni premuto per spostare)'), 
                                        
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit, size: 20, color: Colors.orangeAccent),
                                              tooltip: 'Rinomina scheda',
                                              onPressed: () => _rinominaScheda(scheda),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 20, color: Colors.lightBlueAccent),
                                              tooltip: 'Duplica questa scheda',
                                              onPressed: () => _duplicaScheda(scheda),
                                            ),
                                            const Icon(Icons.arrow_forward_ios, size: 16),
                                          ],
                                        ),
                                        
                                        onTap: () async {
                                          final completato = await Navigator.push(context, MaterialPageRoute(builder: (context) => DettaglioSchedaScreen(scheda: scheda, storico: storico)));
                                          if (completato == true) {
                                            final copiaScheda = Scheda.fromJson(scheda.toJson());
                                            final nuovoAllenamento = Allenamento(data: DateTime.now(), scheda: copiaScheda);
                                            storico.add(nuovoAllenamento);
                                            _inviaAllenamentoAlCloud(nuovoAllenamento);
                                            for (var es in scheda.esercizi) { for (var s in es.serieAttive) { s.isCompletata = false; } }
                                          }
                                          setState(() {}); 
                                          _salvaDati();
                                        },
                                      ),
                                    );

                                  return LongPressDraggable<Scheda>(
                                    data: scheda,
                                    delay: const Duration(milliseconds: 250), 
                                    feedback: Material(color: Colors.transparent, elevation: 8, child: SizedBox(width: MediaQuery.of(context).size.width, child: Opacity(opacity: 0.8, child: cardScheda))),
                                    childWhenDragging: Opacity(opacity: 0.3, child: cardScheda),
                                    child: Dismissible(
                                      key: UniqueKey(), 
                                      direction: DismissDirection.endToStart, 
                                      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete, color: Colors.white, size: 30)),
                                      onDismissed: (direction) { 
                                        String nomeDaEliminare = mieSchede[indiceReale].nome;
                                        setState(() { mieSchede.removeAt(indiceReale); }); 
                                        _salvaDati(); 
                                        _eliminaSchedaDalCloud(nomeDaEliminare);
                                      },
                                      child: cardScheda,
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }
                        );
                      },
                    ),
              ),
            ],
          ),
          
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final nuovaScheda = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaSchedaScreen()));
          if (nuovaScheda != null) { setState(() { mieSchede.add(nuovaScheda); }); _salvaDati(); }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}