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
    'Panca Piana', 'Squat', 'Stacco da Terra', 'Military Press',
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
    final translated = DizionarioEsercizi.daIngleseAItaliano[rawName] ?? rawName;
    final n = _norm(translated);

    if (n.contains('panca piana') || (n.contains('panca') && n.contains('bilanciere'))) {
      return 'Panca Piana';
    }
    if (n == 'squat' || (n.contains('squat') && n.contains('bilanciere'))) {
      return 'Squat';
    }
    if (n.contains('stacco da terra') || n.contains('deadlift') || (n.contains('stacco') && n.contains('bilanciere'))) {
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
      if (aliases.any((a) => keyNorm == a || keyNorm.contains(a) || a.contains(keyNorm))) {
        if (entry.value > best) best = entry.value;
      }
    }
    return best;
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
    
    nomiTrovati.addAll(datiJson.map((e) {
      String n = e['nome'].toString();
      return _canonicalExerciseName(n);
    }));
    
    final prefs = await SharedPreferences.getInstance();
    final String? customSalvati = prefs.getString('esercizi_custom_db_v2');
    if (customSalvati != null) {
      List<dynamic> customList = jsonDecode(customSalvati);
      nomiTrovati.addAll(customList.map((e) {
        String n = e['nome'].toString();
        return _canonicalExerciseName(n);
      }));
    }
    if (mounted) setState(() { _tuttiNomiDatabase = nomiTrovati.toSet().toList(); });
  }

  Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tracciatiSalvati = prefs.getString('esercizi_tracciati_pr');
    try {
      eserciziTracciati = tracciatiSalvati != null
          ? List<String>.from(jsonDecode(tracciatiSalvati))
          : List.from(prDiDefault);
    } catch (_) {
      eserciziTracciati = List.from(prDiDefault);
      await prefs.remove('esercizi_tracciati_pr');
    }

    final String? storicoSalvato = prefs.getString('storico_salvato');

    final String? prGlobaliJson = prefs.getString('personal_records');
    tuttiIPR.clear();
    if (prGlobaliJson != null) {
      try {
        Map<String, dynamic> dec = jsonDecode(prGlobaliJson);
        dec.forEach((k, v) {
          if (v is num) {
            tuttiIPR[k] = v.toDouble();
          } else {
            final parsed = double.tryParse(v.toString().replaceAll(',', '.'));
            if (parsed != null) {
              tuttiIPR[k] = parsed;
            }
          }
        });
      } catch (_) {
        await prefs.remove('personal_records');
      }
    }

    if (storicoSalvato != null) {
      try {
        final List<dynamic> jsonDecodificato = jsonDecode(storicoSalvato);
        final storico = jsonDecodificato
            .map((e) => Allenamento.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (storico.isNotEmpty) {
          final allenamentiVeri = storico.where((a) => !a.scheda.nome.contains('🏆 TEST PR')).toList()
            ..sort((a, b) => a.data.compareTo(b.data));

          allenamentiTotali = allenamentiVeri.length;
          ultimoAllenamento = allenamentiVeri.isNotEmpty ? allenamentiVeri.last : null;

          for (var allenamento in storico) {
            for (var esercizio in allenamento.scheda.esercizi) {
              bool ignoraPerPR = esercizio.tecniche.contains('Back off') || esercizio.tecniche.contains('Drop Set') || esercizio.tecniche.contains('Stripping');
              if (ignoraPerPR) continue;

              for (var serie in esercizio.serieAttive) {
                if (serie.isCompletata && serie.peso.isNotEmpty && serie.tipo != 'Avvicinamento') {
                  double pesoCorrente = double.tryParse(serie.peso.replaceAll(',', '.')) ?? 0.0;
                  if (pesoCorrente > 0) {
                    String nomePulito = (DizionarioEsercizi.daIngleseAItaliano[esercizio.nome] ?? esercizio.nome).trim();
                    nomePulito = _canonicalExerciseName(nomePulito);

                    var matches = tuttiIPR.keys.where((k) => k.toLowerCase() == nomePulito.toLowerCase());
                    String? keyEsistente = matches.isNotEmpty ? matches.first : null;

                    if (keyEsistente != null) {
                      if (pesoCorrente > tuttiIPR[keyEsistente]!) tuttiIPR[keyEsistente] = pesoCorrente;
                    } else {
                      tuttiIPR[nomePulito] = pesoCorrente;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {
        await prefs.remove('storico_salvato');
      }
    }
    await _sincronizzaPRConCloud(tuttiIPR);
    if (mounted) setState(() { _isLoading = false; });
  }

  Future<void> _salvaTracciati() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esercizi_tracciati_pr', jsonEncode(eserciziTracciati));
  }

  Future<void> _sincronizzaPRConCloud(Map<String, double> pr) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'personal_records': pr, 
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
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Traccia Record', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cerca dal database esercizi:', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
            const SizedBox(height: 14),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue text) {
                if (text.text.isEmpty) return const Iterable<String>.empty();
                return _tuttiNomiDatabase.where((nome) => nome.toLowerCase().contains(text.text.toLowerCase()));
              },
              onSelected: (String selection) { cercaController.text = selection; },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.addListener(() { cercaController.text = controller.text; });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Es: Stacco da Terra...',
                    hintStyle: const TextStyle(color: Color(0xFF444444)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF555555), size: 20),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFF6B1A), width: 1.5),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Color(0xFF666666))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B1A), foregroundColor: Colors.white),
            onPressed: () {
              String val = cercaController.text.trim();
              if (val.isNotEmpty) {
                bool giaPresente = eserciziTracciati.any((e) => e.toLowerCase() == val.toLowerCase());
                if (!giaPresente) {
                  setState(() { eserciziTracciati.add(val); });
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
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B1A))));
    try {
      final prefs = await SharedPreferences.getInstance();
      final String schedeJson = prefs.getString('schede_salvate') ?? '[]';
      final String storicoJson = prefs.getString('storico_salvato') ?? '[]';
      final String prJson = prefs.getString('personal_records') ?? '{}';

      Map<String, dynamic> datiBackup = {
        'schede': jsonDecode(schedeJson), 'storico': jsonDecode(storicoJson), 'carichi': jsonDecode(prJson), 'data_backup': DateTime.now().toIso8601String(),
      };

      String jsonString = jsonEncode(datiBackup);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/backup_tiger_full_${DateTime.now().millisecondsSinceEpoch}.json');
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante il backup: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _importaBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result != null && result.files.single.path != null) {
        if (!mounted) return;
        showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B1A))));
        File file = File(result.files.single.path!);
        String contenuto = await file.readAsString();
        Map<String, dynamic> datiImportati = jsonDecode(contenuto);

        if (datiImportati.containsKey('schede') && datiImportati.containsKey('storico')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('schede_salvate', jsonEncode(datiImportati['schede']));
          await prefs.setString('storico_salvato', jsonEncode(datiImportati['storico']));
          if (datiImportati.containsKey('carichi')) await prefs.setString('personal_records', jsonEncode(datiImportati['carichi']));
          await _caricaDati();
          if (!mounted) return;
          Navigator.pop(context); 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup importato con successo! 🎉'), backgroundColor: Colors.green));
        } else {
          if (!mounted) return;
          Navigator.pop(context);
          throw Exception("Formato file non valido.");
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore importazione: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B1A);
    const red = Color(0xFFCC1A1A);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Tiger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload, color: Color(0xFF666666)),
            tooltip: 'Importa Backup',
            onPressed: _importaBackup,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, color: Color(0xFF666666)),
            tooltip: 'Esporta Backup',
            onPressed: _eseguiBackup,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF666666)),
            tooltip: 'Esci',
            onPressed: () async {
              final confermato = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF141414),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Uscire?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  content: const Text(
                    'Dovrai fare di nuovo il login per accedere.',
                    style: TextStyle(color: Color(0xFFAAAAAA)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annulla', style: TextStyle(color: Color(0xFF666666))),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Esci'),
                    ),
                  ],
                ),
              ) ?? false;
              if (confermato) await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: orange))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Stats Card ──────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: orange.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [red, orange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: orange.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.local_fire_department, size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 20),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$allenamentiTotali',
                              style: const TextStyle(
                                fontSize: 46,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            const Text(
                              'ALLENAMENTI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF666666),
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Ultimo Allenamento ────────────────────────
                  if (ultimoAllenamento != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D2A0D),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ultimoAllenamento!.scheda.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Ultimo: ${ultimoAllenamento!.data.day}/${ultimoAllenamento!.data.month}/${ultimoAllenamento!.data.year}',
                                  style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── PR Section Header ─────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.emoji_events, color: Color(0xFFFFB347), size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'I TUOI RECORD',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_rounded, color: orange, size: 28),
                        onPressed: _mostraAggiungiPR,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── PR List ───────────────────────────────────
                  if (eserciziTracciati.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: const Text(
                        'Nessun record tracciato.\nPremi + per aggiungerne uno.',
                        style: TextStyle(color: Color(0xFF555555), fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: eserciziTracciati.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, index) {
                          final nomeEsercizio = _canonicalExerciseName(eserciziTracciati[index]);
                          final maxPeso = _readPrValueForExercise(nomeEsercizio);
                          final pesoMostrato = maxPeso == 0.0
                              ? '--'
                              : (maxPeso == maxPeso.truncateToDouble()
                                  ? maxPeso.toInt().toString()
                                  : maxPeso.toString());

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.fitness_center, color: orange, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    nomeEsercizio,
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                ),
                                Text(
                                  maxPeso > 0 ? '$pesoMostrato kg' : '—',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: maxPeso > 0 ? orange : const Color(0xFF444444),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Color(0xFF555555), size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () {
                                    setState(() => eserciziTracciati.removeAt(index));
                                    _salvaTracciati();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}