import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/allenamento.dart';
import '../../services/api_esercizi.dart';
import '../../services/dizionario_esercizi.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int allenamentiTotali = 0;
  Allenamento? ultimoAllenamento;
  bool _isLoading = true;
  Map<String, double> tuttiIPR = {};
  List<String> eserciziTracciati = [];
  List<String> _tuttiNomiDatabase = [];

  final List<String> prDiDefault = [
    'Panca Piana',
    'Squat',
    'Stacco da Terra',
    'Military Press',
  ];

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

  String _canonicalExerciseName(String rawName) {
    final translated =
        DizionarioEsercizi.daIngleseAItaliano[rawName] ?? rawName;
    final n = _norm(translated);

    if (n.contains('panca piana') ||
        (n.contains('panca') && n.contains('bilanciere'))) {
      return 'Panca Piana';
    }
    if (n == 'squat' || (n.contains('squat') && n.contains('bilanciere'))) {
      return 'Squat';
    }
    if (n.contains('stacco da terra') ||
        n.contains('deadlift') ||
        (n.contains('stacco') && n.contains('bilanciere'))) {
      return 'Stacco da Terra';
    }
    return translated.trim();
  }

  List<String> _prAliasesForExercise(String canonicalName) {
    final n = _norm(canonicalName);
    if (n == 'panca piana') {
      return const [
        'Panca Piana',
        'Panca piana con bilanciere(presa media)',
        'Panca piana con bilanciere - presa media',
        'Panca piana con bilanciere (presa media)',
      ];
    }
    if (n == 'squat') {
      return const [
        'Squat',
        'Squat Completo con Bilanciere',
        'Squat completo con bilanciere',
      ];
    }
    if (n == 'stacco da terra') {
      return const [
        'Stacco da Terra',
        'Stacco da Terra con Bilanciere',
        'Stacco da terra con bilanciere',
        'Deadlift',
        'Conventional Deadlift',
      ];
    }
    return [canonicalName];
  }

  double _readPrValueForExercise(String displayExerciseName) {
    final canonical = _canonicalExerciseName(displayExerciseName);
    final aliases = _prAliasesForExercise(canonical).map(_norm).toList();

    double best = 0.0;
    for (final entry in tuttiIPR.entries) {
      final keyNorm = _norm(entry.key);
      if (aliases.any(
        (a) => keyNorm == a || keyNorm.contains(a) || a.contains(keyNorm),
      )) {
        if (entry.value > best) best = entry.value;
      }
    }
    return best;
  }

  Map<String, double> _parsePrMap(dynamic raw) {
    final out = <String, double>{};
    if (raw is! Map) return out;

    raw.forEach((k, v) {
      if (v is num) {
        out[k.toString()] = v.toDouble();
      } else {
        final parsed = double.tryParse(v.toString().replaceAll(',', '.'));
        if (parsed != null) {
          out[k.toString()] = parsed;
        }
      }
    });
    return out;
  }

  void _mergePrMapsMax(Map<String, double> target, Map<String, double> source) {
    for (final entry in source.entries) {
      final existing = target[entry.key];
      if (existing == null || entry.value > existing) {
        target[entry.key] = entry.value;
      }
    }
  }

  Future<Map<String, double>> _caricaPrDaCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String, double>{};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      return _parsePrMap(doc.data()?['personal_records']);
    } catch (e) {
      debugPrint('Errore caricamento PR cloud: $e');
      return <String, double>{};
    }
  }

  Future<Map<String, double>> _ricostruisciPrDaStoricoCloud(
    String atletaId,
  ) async {
    final out = <String, double>{};
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('storico_atleti')
          .where('atletaId', isEqualTo: atletaId)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Schema Allenamento completo (scheda/esercizi/serieAttive).
        final schedaRaw = data['scheda'];
        if (schedaRaw is Map) {
          try {
            final allenamento = Allenamento.fromJson(
              Map<String, dynamic>.from(data),
            );
            for (final esercizio in allenamento.scheda.esercizi) {
              final canonical = _canonicalExerciseName(
                DizionarioEsercizi.daIngleseAItaliano[esercizio.nome] ??
                    esercizio.nome,
              );
              for (final serie in esercizio.serieAttive) {
                if (!serie.isCompletata || serie.tipo == 'Avvicinamento')
                  continue;
                final peso =
                    double.tryParse(serie.peso.replaceAll(',', '.')) ?? 0.0;
                if (peso <= 0) continue;
                final prev = out[canonical] ?? 0.0;
                if (peso > prev) out[canonical] = peso;
              }
            }
            continue;
          } catch (_) {
            // Fallback su schema compatto.
          }
        }

        // Schema compatto storico_atleti (esercizi/serie).
        final eserciziRaw = data['esercizi'];
        if (eserciziRaw is! List) continue;
        for (final es in eserciziRaw.whereType<Map>()) {
          final nomeRaw = es['nome']?.toString() ?? '';
          final canonical = _canonicalExerciseName(nomeRaw);
          final serieRaw = es['serie'];
          if (serieRaw is! List) continue;
          for (final s in serieRaw.whereType<Map>()) {
            final tipo = s['tipo']?.toString() ?? '';
            if (tipo.toLowerCase() == 'avvicinamento') continue;
            final peso =
                double.tryParse(
                  (s['peso']?.toString() ?? '').replaceAll(',', '.'),
                ) ??
                0.0;
            if (peso <= 0) continue;
            final prev = out[canonical] ?? 0.0;
            if (peso > prev) out[canonical] = peso;
          }
        }
      }
    } catch (e) {
      debugPrint('Errore ricostruzione PR da storico cloud: $e');
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _caricaDati();
    _caricaDatabasePerRicerca();
  }

  Future<void> _caricaDatabasePerRicerca() async {
    List<String> nomiTrovati = [];
    final datiJson = await ApiEsercizi.ottieniEserciziTradotti();

    nomiTrovati.addAll(
      datiJson.map((e) {
        String n = e['nome'].toString();
        return _canonicalExerciseName(n);
      }),
    );

    final prefs = await SharedPreferences.getInstance();
    final String? customSalvati = prefs.getString('esercizi_custom_db_v2');
    if (customSalvati != null) {
      List<dynamic> customList = jsonDecode(customSalvati);
      nomiTrovati.addAll(
        customList.map((e) {
          String n = e['nome'].toString();
          return _canonicalExerciseName(n);
        }),
      );
    }
    if (mounted)
      setState(() {
        _tuttiNomiDatabase = nomiTrovati.toSet().toList();
      });
  }

  Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final String? tracciatiSalvati = prefs.getString('esercizi_tracciati_pr');
    if (tracciatiSalvati != null) {
      eserciziTracciati = List<String>.from(jsonDecode(tracciatiSalvati));
    } else {
      eserciziTracciati = List.from(prDiDefault);
    }

    final String? storicoSalvato = prefs.getString('storico_salvato');

    final String? prGlobaliJson = prefs.getString('personal_records');
    final localPr = prGlobaliJson != null
        ? _parsePrMap(jsonDecode(prGlobaliJson))
        : <String, double>{};
    final cloudPr = await _caricaPrDaCloud();

    tuttiIPR.clear();
    _mergePrMapsMax(tuttiIPR, cloudPr);
    _mergePrMapsMax(tuttiIPR, localPr);

    // Dopo reinstall locale, provo a recuperare PR dallo storico cloud se necessario.
    if (tuttiIPR.isEmpty && user != null) {
      final ricostruiti = await _ricostruisciPrDaStoricoCloud(user.uid);
      _mergePrMapsMax(tuttiIPR, ricostruiti);
    }

    if (storicoSalvato != null) {
      final List<dynamic> jsonDecodificato = jsonDecode(storicoSalvato);
      final storico = jsonDecodificato
          .map((e) => Allenamento.fromJson(e))
          .toList();

      if (storico.isNotEmpty) {
        final allenamentiVeri =
            storico.where((a) => !a.scheda.nome.contains('🏆 TEST PR')).toList()
              ..sort((a, b) => a.data.compareTo(b.data));

        allenamentiTotali = allenamentiVeri.length;
        ultimoAllenamento = allenamentiVeri.isNotEmpty
            ? allenamentiVeri.last
            : null;

        for (var allenamento in storico) {
          for (var esercizio in allenamento.scheda.esercizi) {
            bool ignoraPerPR =
                esercizio.tecniche.contains('Back off') ||
                esercizio.tecniche.contains('Drop Set') ||
                esercizio.tecniche.contains('Stripping');
            if (ignoraPerPR) continue;

            for (var serie in esercizio.serieAttive) {
              if (serie.isCompletata &&
                  serie.peso.isNotEmpty &&
                  serie.tipo != 'Avvicinamento') {
                double pesoCorrente =
                    double.tryParse(serie.peso.replaceAll(',', '.')) ?? 0.0;
                if (pesoCorrente > 0) {
                  String nomePulito =
                      (DizionarioEsercizi.daIngleseAItaliano[esercizio.nome] ??
                              esercizio.nome)
                          .trim();
                  nomePulito = _canonicalExerciseName(nomePulito);

                  var matches = tuttiIPR.keys.where(
                    (k) => k.toLowerCase() == nomePulito.toLowerCase(),
                  );
                  String? keyEsistente = matches.isNotEmpty
                      ? matches.first
                      : null;

                  if (keyEsistente != null) {
                    if (pesoCorrente > tuttiIPR[keyEsistente]!)
                      tuttiIPR[keyEsistente] = pesoCorrente;
                  } else {
                    tuttiIPR[nomePulito] = pesoCorrente;
                  }
                }
              }
            }
          }
        }
      }
    }
    await prefs.setString('personal_records', jsonEncode(tuttiIPR));
    await _sincronizzaPRConCloud(tuttiIPR);
    if (mounted)
      setState(() {
        _isLoading = false;
      });
  }

  Future<void> _salvaTracciati() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'esercizi_tracciati_pr',
      jsonEncode(eserciziTracciati),
    );
  }

  Future<void> _sincronizzaPRConCloud(Map<String, double> pr) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (pr.isEmpty) return;

    try {
      final cloudPr = await _caricaPrDaCloud();
      final merged = <String, double>{};
      _mergePrMapsMax(merged, cloudPr);
      _mergePrMapsMax(merged, pr);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'personal_records': merged,
        'ultimo_aggiornamento_pr': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Errore sync PR: $e");
    }
  }

  void _mostraAggiungiPR() {
    TextEditingController cercaController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Traccia nuovo Record',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cerca dal database l\'esercizio:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue text) {
                if (text.text.isEmpty) return const Iterable<String>.empty();
                return _tuttiNomiDatabase.where(
                  (nome) =>
                      nome.toLowerCase().contains(text.text.toLowerCase()),
                );
              },
              onSelected: (String selection) {
                cercaController.text = selection;
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    controller.addListener(() {
                      cercaController.text = controller.text;
                    });
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Es: Stacco da Terra...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    );
                  },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              String val = cercaController.text.trim();
              if (val.isNotEmpty) {
                bool giaPresente = eserciziTracciati.any(
                  (e) => e.toLowerCase() == val.toLowerCase(),
                );
                if (!giaPresente) {
                  setState(() {
                    eserciziTracciati.add(val);
                  });
                  _salvaTracciati();
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
  }

  Future<void> _eseguiBackup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.deepOrange),
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final String schedeJson = prefs.getString('schede_salvate') ?? '[]';
      final String storicoJson = prefs.getString('storico_salvato') ?? '[]';
      final String prJson = prefs.getString('personal_records') ?? '{}';

      Map<String, dynamic> datiBackup = {
        'schede': jsonDecode(schedeJson),
        'storico': jsonDecode(storicoJson),
        'carichi': jsonDecode(prJson),
        'data_backup': DateTime.now().toIso8601String(),
      };

      String jsonString = jsonEncode(datiBackup);
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/backup_tiger_full_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonString);

      if (!mounted) return;
      Navigator.pop(context);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Trasloco completo Tiger: Schede, Storico e PR! 💪🐯',
          subject: 'Backup Totale Palestra',
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante il backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _importaBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Colors.lightBlue),
          ),
        );
        File file = File(result.files.single.path!);
        String contenuto = await file.readAsString();
        Map<String, dynamic> datiImportati = jsonDecode(contenuto);

        if (datiImportati.containsKey('schede') &&
            datiImportati.containsKey('storico')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'schede_salvate',
            jsonEncode(datiImportati['schede']),
          );
          await prefs.setString(
            'storico_salvato',
            jsonEncode(datiImportati['storico']),
          );
          if (datiImportati.containsKey('carichi'))
            await prefs.setString(
              'personal_records',
              jsonEncode(datiImportati['carichi']),
            );
          await _caricaDati();
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup importato con successo! 🎉'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          if (!mounted) return;
          Navigator.pop(context);
          throw Exception("Formato file non valido.");
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore importazione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bentornato! 🏋️‍♂️'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload, color: Colors.lightBlue),
            tooltip: 'Importa Backup',
            onPressed: _importaBackup,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.deepOrange),
            tooltip: 'Esporta Backup',
            onPressed: _eseguiBackup,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Esci',
            onPressed: () async {
              bool confermato =
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Vuoi uscire?'),
                      content: const Text(
                        'Dovrai fare di nuovo il login per accedere alle tue schede.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(
                            'Annulla',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Esci'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (confermato) await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Riepilogo Attività',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.deepOrange.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            size: 48,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$allenamentiTotali',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Allenamenti Completati',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (ultimoAllenamento != null) ...[
                    const Text(
                      'Ultimo Allenamento',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 30,
                        ),
                        title: Text(
                          ultimoAllenamento!.scheda.nome,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Text(
                          'Data: ${ultimoAllenamento!.data.day}/${ultimoAllenamento!.data.month}/${ultimoAllenamento!.data.year}',
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.emoji_events, color: Colors.amber),
                          SizedBox(width: 8),
                          Text(
                            'I Tuoi Record (PR)',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.deepOrange,
                          size: 28,
                        ),
                        onPressed: _mostraAggiungiPR,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (eserciziTracciati.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Nessun esercizio in bacheca. Premi il tasto + per aggiungerne uno!',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: eserciziTracciati.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Colors.black26),
                        itemBuilder: (context, index) {
                          String nomeEsercizio = _canonicalExerciseName(
                            eserciziTracciati[index],
                          );

                          double maxPeso = _readPrValueForExercise(
                            nomeEsercizio,
                          );
                          String pesoMostrato = maxPeso == 0.0
                              ? '--'
                              : (maxPeso == maxPeso.truncateToDouble()
                                    ? maxPeso.toInt().toString()
                                    : maxPeso.toString());

                          return ListTile(
                            leading: const Icon(
                              Icons.fitness_center,
                              color: Colors.deepOrange,
                            ),
                            title: Text(
                              nomeEsercizio,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  maxPeso > 0
                                      ? '$pesoMostrato kg'
                                      : 'Nessun dato',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: maxPeso > 0
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      eserciziTracciati.removeAt(index);
                                    });
                                    _salvaTracciati();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
