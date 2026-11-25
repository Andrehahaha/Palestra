import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scheda.dart';
import '../models/allenamento.dart';
import '../models/esercizio.dart';
import '../services/ai_service.dart';
import '../services/archivio_atleta.dart';
import '../services/carichi.dart';
import '../services/pdf_schede.dart';
import 'dettaglio_scheda_screen.dart';
import 'storico_screen.dart';
import 'crea_scheda.dart';
import 'crea_esercizio.dart';
import 'pr_mode_screen.dart';
import 'settimana_successiva_screen.dart';

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

  Future<void> _creaCartellaVuota() async {
    final controller = TextEditingController();
    final String? nomeCartella = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuova cartella vuota'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome cartella',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crea'),
          ),
        ],
      ),
    );

    final nome = nomeCartella?.trim() ?? '';
    if (nome.isEmpty || !mounted) return;

    final esisteGia = cartelleVuote.contains(nome) || mieSchede.any((s) => s.categoria == nome);
    if (esisteGia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esiste già una cartella con questo nome.'), backgroundColor: Colors.orange),
      );
      return;
    }

    _updateState(() {
      cartelleVuote.add(nome);
    });
    await _salvaDati();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cartella vuota creata ✅'), backgroundColor: Colors.green),
    );
  }

  Future<bool> _confermaEliminazioneCloud(String target) async {
    final bool? conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione cloud'),
        content: Text('Vuoi eliminare $target anche sul cloud?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sì, elimina'),
          ),
        ],
      ),
    );

    return conferma == true;
  }

  Future<void> _eliminaCartellaVuota(String nomeCategoria) async {
    final conferma = await _confermaEliminazioneCloud('la cartella "$nomeCategoria"');
    if (!conferma || !mounted) return;

    _updateState(() {
      cartelleVuote.remove(nomeCategoria);
    });
    await _salvaDati();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cartella vuota eliminata 🗑️'), backgroundColor: Colors.green),
    );
  }

  Future<void> _creaSchedaCompleta() async {
    final nuovaScheda = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaSchedaScreen()));
    if (nuovaScheda != null && nuovaScheda is Scheda) {
      _updateState(() {
        mieSchede.add(nuovaScheda);
      });
      _salvaDati();
    }
  }

  Future<void> _creaSchedaSingola() async {
    final Esercizio? esercizio = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreaEsercizioScreen()),
    );

    if (esercizio == null || !mounted) return;

    final nomeController = TextEditingController(text: 'Scheda ${esercizio.nome}');
    final categoriaController = TextEditingController(text: 'Generale');
    String livelloSelezionato = 'Principiante';

    final bool? conferma = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crea scheda singola'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome scheda', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoriaController,
                decoration: const InputDecoration(labelText: 'Categoria / Cartella', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: livelloSelezionato,
                decoration: const InputDecoration(labelText: 'Livello', border: OutlineInputBorder()),
                items: ['Principiante', 'Intermedio', 'Avanzato']
                    .map((livello) => DropdownMenuItem(value: livello, child: Text(livello)))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setDialogState(() => livelloSelezionato = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crea')),
          ],
        ),
      ),
    );

    final nomeScheda = nomeController.text.trim();
    final categoria = categoriaController.text.trim();
    nomeController.dispose();
    categoriaController.dispose();

    if (conferma != true || nomeScheda.isEmpty || !mounted) return;

    final nuovaScheda = Scheda(
      nome: nomeScheda,
      livello: livelloSelezionato,
      categoria: categoria.isEmpty ? 'Generale' : categoria,
      esercizi: [esercizio],
    );

    _updateState(() {
      mieSchede.add(nuovaScheda);
    });
    _salvaDati();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scheda singola creata! ✅'), backgroundColor: Colors.green),
    );
  }

  Future<void> _apriMenuCreazione() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_list, color: Colors.deepOrange),
              title: const Text('Nuovo workout completo'),
              subtitle: const Text('Crea una scheda con più esercizi'),
              onTap: () {
                Navigator.pop(context);
                _creaSchedaCompleta();
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add, color: Colors.lightBlueAccent),
              title: const Text('Nuova scheda singola'),
              subtitle: const Text('Crea una scheda con un solo esercizio'),
              onTap: () {
                Navigator.pop(context);
                _creaSchedaSingola();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder, color: Colors.amber),
              title: const Text('Nuova cartella vuota'),
              subtitle: const Text('Crea una cartella senza schede'),
              onTap: () {
                Navigator.pop(context);
                _creaCartellaVuota();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _duplicaScheda(Scheda schedaOriginale) {
    final Map<String, dynamic> jsonCopia = schedaOriginale.toJson();
    jsonCopia['nome'] = '${schedaOriginale.nome} (Copia)';
    // Id nuovo: altrimenti la copia condivide lo storico settimane dell'originale.
    jsonCopia['id'] = 'sch_${DateTime.now().microsecondsSinceEpoch}';

    final Scheda nuovaScheda = Scheda.fromJson(jsonCopia);

    _updateState(() {
      mieSchede.add(nuovaScheda);
    });

    _salvaDati();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scheda duplicata con successo! 📄🔄'), backgroundColor: Colors.blueAccent),
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
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != scheda.nome) {
      if (!context.mounted || !mounted) return;
      _updateState(() {
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
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Es: Settimana 1...', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != vecchioNome) {
      _updateState(() {
        for (var scheda in mieSchede) {
          if (scheda.categoria == vecchioNome) scheda.categoria = nuovoNome;
        }
      });
      _salvaDati();
    }
  }

  Future<void> _esportaCartellaInPDF(String nomeCategoria, List<Scheda> schede) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)));
    try {
      final bytes = await PdfSchede.cartella(nomeCategoria, schede);
      final directory = await getTemporaryDirectory();
      String nomeFile = nomeCategoria.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${directory.path}/$nomeFile.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      Navigator.pop(context);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Ecco le tue schede per il blocco: $nomeCategoria 💪',
          subject: 'Schede Allenamento Tiger',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore creazione PDF: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _apriSettimanaSuccessiva(Scheda scheda) async {
    final aggiornata = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettimanaSuccessivaScreen(scheda: scheda)),
    );

    if (aggiornata is Scheda && mounted) {
      _updateState(() {});
      await _salvaDati();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Progressione applicata alla settimana ${aggiornata.settimanaCorrente}.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Map<String, List<Scheda>> _raggruppaSchedePerCategoria() {
    final Map<String, List<Scheda>> schedeRaggruppate = {};
    for (var scheda in mieSchede) {
      schedeRaggruppate.putIfAbsent(scheda.categoria, () => []).add(scheda);
    }
    for (var cartella in cartelleVuote) {
      schedeRaggruppate.putIfAbsent(cartella, () => []);
    }
    return schedeRaggruppate;
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.sync, color: Colors.greenAccent),
        onPressed: () async {
          showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
          await _sincronizzaColCoach(silenzioso: false);
          if (!context.mounted) return;
          Navigator.pop(context);
        },
      ),
      IconButton(
        icon: const Icon(Icons.document_scanner, color: Colors.blueAccent),
        onPressed: () async {
          final picker = ImagePicker();
          final XFile? foto = await picker.pickImage(source: ImageSource.gallery);
          if (!context.mounted) return;
          if (foto != null) {
            if (!mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
            );
            final esito = await AiService.instance.analizzaFotoScheda(foto);
            if (!context.mounted || !mounted) return;
            Navigator.pop(context);
            final schedeImportate = esito.valore;
            if (schedeImportate != null) {
              _updateState(() {
                mieSchede.addAll(schedeImportate);
              });
              _salvaDati();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${schedeImportate.length} schede importate! 🤖💪')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(esito.errore ?? 'Errore durante la scansione. Riprova! ❌')));
            }
          }
        },
      ),
      IconButton(
        icon: const Icon(Icons.history),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => StoricoScreen(storico: storico, onUpdate: () => _salvaDati())),
          ).then((_) {
            _updateState(() {});
          });
        },
      ),
    ];
  }

  Widget _buildQuickAccessCards(BuildContext context) {
    return Column(
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
                boxShadow: [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
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
      ],
    );
  }

  Widget _buildCategorieList(BuildContext context, Map<String, List<Scheda>> schedeRaggruppate, List<String> categorie) {
    if (categorie.isEmpty) {
      return const Center(child: Text('Nessuna scheda. Premi + o chiedi al tuo Coach!', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: categorie.length,
      itemBuilder: (context, index) {
        final nomeCategoria = categorie[index];
        final schedeDiQuestaCategoria = schedeRaggruppate[nomeCategoria]!;

        return DragTarget<Scheda>(
          onWillAcceptWithDetails: (details) => details.data.categoria != nomeCategoria,
          onAcceptWithDetails: (details) {
            _updateState(() {
              details.data.categoria = nomeCategoria;
              cartelleVuote.remove(nomeCategoria);
            });
            _salvaDati();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scheda spostata in "$nomeCategoria"! 📂'), backgroundColor: Colors.green),
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
              decoration: BoxDecoration(
                color: isHovering ? Colors.deepOrange.withValues(alpha: 0.1) : Colors.transparent,
                border: isHovering ? Border.all(color: Colors.deepOrange, width: 2) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: Icon(
                  nomeCategoria == 'Dal Coach 🐯' ? Icons.local_fire_department : Icons.folder,
                  color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        nomeCategoria,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, size: 22, color: Colors.redAccent),
                      onPressed: () => _esportaCartellaInPDF(nomeCategoria, schedeDiQuestaCategoria),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, size: 22, color: Colors.purpleAccent),
                      onPressed: () => _mostraAnalisiCartella(context, nomeCategoria, schedeDiQuestaCategoria),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                      onPressed: () => _rinominaCategoria(nomeCategoria),
                    ),
                    if (schedeDiQuestaCategoria.isEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        tooltip: 'Elimina cartella vuota',
                        onPressed: () => _eliminaCartellaVuota(nomeCategoria),
                      ),
                  ],
                ),
                children: schedeDiQuestaCategoria.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text('Cartella vuota', style: TextStyle(color: Colors.grey)),
                        ),
                      ]
                    : schedeDiQuestaCategoria.map((scheda) => _buildSchedaCard(context, scheda)).toList(),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostraAnalisiCartella(BuildContext context, String nomeCategoria, List<Scheda> schedeDiQuestaCategoria) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),
    );
    final esito = await AiService.instance.valutaCartella(nomeCategoria, schedeDiQuestaCategoria);
    final String recensione = esito.valore ?? esito.errore!;
    if (!context.mounted) return;
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 28),
                SizedBox(width: 8),
                Text('Analisi del Coach AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SingleChildScrollView(
                child: Text(recensione, style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Ho capito, grazie Coach!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedaCard(BuildContext context, Scheda scheda) {
    final indiceReale = mieSchede.indexOf(scheda);
    final cardScheda = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.list_alt)),
        title: Text(scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${scheda.esercizi.length} esercizi • ${scheda.livello} • W${scheda.settimanaCorrente}\n'
          '${scheda.continuativa ? 'Continuativa' : 'Non continuativa'} • (Tieni premuto per spostare)',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_next, size: 20, color: Colors.greenAccent),
              tooltip: 'Settimana successiva',
              onPressed: () => _apriSettimanaSuccessiva(scheda),
            ),
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
          final completato = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DettaglioSchedaScreen(scheda: scheda, storico: storico)),
          );
          // La sessione è già registrata da SessioniAllenamento.completa.
          if (completato == true) _updateState(() {});
          _salvaDati();
        },
      ),
    );

    return LongPressDraggable<Scheda>(
      data: scheda,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: SizedBox(width: MediaQuery.of(context).size.width, child: Opacity(opacity: 0.8, child: cardScheda)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cardScheda),
      child: Dismissible(
        key: UniqueKey(),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete, color: Colors.white, size: 30),
        ),
        confirmDismiss: (direction) async {
          return _confermaEliminazioneCloud('la scheda "${scheda.nome}"');
        },
        onDismissed: (direction) {
          String nomeDaEliminare = mieSchede[indiceReale].nome;
          _updateState(() {
            mieSchede.removeAt(indiceReale);
          });
          _salvaDati();
          _eliminaSchedaDalCloud(nomeDaEliminare);
        },
        child: cardScheda,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedeRaggruppate = _raggruppaSchedePerCategoria();
    List<String> categorie = schedeRaggruppate.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le tue Schede'),
        actions: _buildAppBarActions(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildQuickAccessCards(context),
                Expanded(child: _buildCategorieList(context, schedeRaggruppate, categorie)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _apriMenuCreazione,
        child: const Icon(Icons.add),
      ),
    );
  }
}