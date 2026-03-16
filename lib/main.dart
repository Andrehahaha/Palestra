import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'services/dizionario_esercizi.dart'; 
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/scheda.dart';
import 'models/allenamento.dart';
import 'screens/crea_scheda.dart';
import 'screens/dettaglio_scheda_screen.dart';
import 'screens/storico_screen.dart';
import 'screens/profilo_screen.dart';
import 'services/ai_service.dart';
import 'services/api_esercizi.dart';
import 'screens/login_screen.dart';
import 'screens/coach_dashboard.dart';

// ... (lascia intatti tutti i tuoi import, vanno benissimo!) ...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 👇 ECCOLA QUI! Apri la cassaforte PRIMA di chiamare Firebase
  await dotenv.load(fileName: ".env");

  // Ora Firebase parte e va a leggere le chiavi in modo sicuro
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepOrange,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
          );
        }
        if (snapshot.hasData) {
          return const RoleController();
        }
        return const LoginScreen();
      },
    );
  }
}

class RoleController extends StatelessWidget {
  const RoleController({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.deepOrange)));
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Errore: Profilo non trovato nel database.', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                    icon: const Icon(Icons.logout),
                    label: const Text('Esci e riprova'),
                    onPressed: () async { await FirebaseAuth.instance.signOut(); },
                  )
                ],
              ),
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final String ruolo = userData['ruolo'] ?? 'atleta';

        if (ruolo == 'coach') {
          return const CoachDashboardScreen(); 
        } else {
          return const MainNavigationScreen(); 
        }
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // 👇 IL SEGRETO PER AGGIORNARE TUTTO ISTANTANEAMENTE QUANDO CAMBI SCHERMATA
    final List<Widget> screens = [
      HomeScreen(key: UniqueKey()),
      WorkoutsScreen(key: UniqueKey()),
      ProfiloScreen(key: UniqueKey()),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        onTap: (index) { setState(() { _currentIndex = index; }); },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Allenamenti'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profilo'),
        ],
      ),
    );
  }
}

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
  
  // 👇 IMPOSTATO A PANCA PIANA PULITO
  final List<String> prDiDefault = [
    'Panca Piana', 'Squat', 'Stacco da Terra', 'Military Press',
  ];

  @override
  void initState() {
    super.initState();
    _caricaDati();
    _caricaDatabasePerRicerca();
  }

  Future<void> _caricaDatabasePerRicerca() async {
    List<String> nomiTrovati = [];
    final datiJson = await ApiEsercizi.ottieniEserciziTradotti();
    
    // 👇 INTERCETTA IL NOME LUNGO DELLA PANCA DAL DATABASE E LO ACCORCIA
    nomiTrovati.addAll(datiJson.map((e) {
      String n = e['nome'].toString();
      if (n.toLowerCase().contains('panca piana con bilanciere')) return 'Panca Piana';
      return n;
    }));
    
    final prefs = await SharedPreferences.getInstance();
    final String? customSalvati = prefs.getString('esercizi_custom_db_v2');
    if (customSalvati != null) {
      List<dynamic> customList = jsonDecode(customSalvati);
      nomiTrovati.addAll(customList.map((e) {
        String n = e['nome'].toString();
        if (n.toLowerCase().contains('panca piana con bilanciere')) return 'Panca Piana';
        return n;
      }));
    }
    if (mounted) setState(() { _tuttiNomiDatabase = nomiTrovati.toSet().toList(); });
  }
Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tracciatiSalvati = prefs.getString('esercizi_tracciati_pr');
    if (tracciatiSalvati != null) {
      eserciziTracciati = List<String>.from(jsonDecode(tracciatiSalvati));
    } else {
      eserciziTracciati = List.from(prDiDefault);
    }

    final String? storicoSalvato = prefs.getString('storico_salvato');
    
    final String? prGlobaliJson = prefs.getString('personal_records');
    tuttiIPR.clear();
    if (prGlobaliJson != null) {
      Map<String, dynamic> dec = jsonDecode(prGlobaliJson);
      dec.forEach((k, v) => tuttiIPR[k] = (v as num).toDouble());
    }

    if (storicoSalvato != null) {
      final List<dynamic> jsonDecodificato = jsonDecode(storicoSalvato);
      final storico = jsonDecodificato.map((e) => Allenamento.fromJson(e)).toList();
      
      if (storico.isNotEmpty) {
        // 👇 ECCO IL FILTRO: Separa gli allenamenti veri dai Test PR!
        final allenamentiVeri = storico.where((a) => !a.scheda.nome.contains('🏆 TEST PR')).toList();
        
        // Il contatore e l'ultimo allenamento guardano SOLO quelli veri
        allenamentiTotali = allenamentiVeri.length;
        ultimoAllenamento = allenamentiVeri.isNotEmpty ? allenamentiVeri.last : null;
        
        // I massimali invece li cerchiamo in TUTTO lo storico (veri + PR)
        for (var allenamento in storico) {
          for (var esercizio in allenamento.scheda.esercizi) {
            bool ignoraPerPR = esercizio.tecniche.contains('Back off') || esercizio.tecniche.contains('Drop Set') || esercizio.tecniche.contains('Stripping');
            if (ignoraPerPR) continue;

            for (var serie in esercizio.serieAttive) {
              if (serie.isCompletata && serie.peso.isNotEmpty && serie.tipo != 'Avvicinamento') {
                double pesoCorrente = double.tryParse(serie.peso.replaceAll(',', '.')) ?? 0.0;
                if (pesoCorrente > 0) {
                  String nomePulito = (DizionarioEsercizi.daIngleseAItaliano[esercizio.nome] ?? esercizio.nome).trim();
                  
                  if (nomePulito.toLowerCase().contains('panca piana con bilanciere')) {
                    nomePulito = 'Panca Piana';
                  }

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
    }
    _sincronizzaPRConCloud(tuttiIPR);
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
        title: const Text('Traccia nuovo Record', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cerca dal database l\'esercizio:', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue text) {
                if (text.text.isEmpty) return const Iterable<String>.empty();
                return _tuttiNomiDatabase.where((nome) => nome.toLowerCase().contains(text.text.toLowerCase()));
              },
              onSelected: (String selection) { cercaController.text = selection; },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.addListener(() { cercaController.text = controller.text; });
                return TextField(
                  controller: controller, focusNode: focusNode,
                  decoration: const InputDecoration(hintText: 'Es: Stacco da Terra...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
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
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)));
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
      await Share.shareXFiles([XFile(file.path)], text: 'Trasloco completo Tiger: Schede, Storico e PR! 💪🐯', subject: 'Backup Totale Palestra');
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
        showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.lightBlue)));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bentornato! 🏋️‍♂️'),
        actions: [
          IconButton(icon: const Icon(Icons.file_upload, color: Colors.lightBlue), tooltip: 'Importa Backup', onPressed: _importaBackup),
          IconButton(icon: const Icon(Icons.save_alt, color: Colors.deepOrange), tooltip: 'Esporta Backup', onPressed: _eseguiBackup),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent), tooltip: 'Esci',
            onPressed: () async {
              bool confermato = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Vuoi uscire?'),
                  content: const Text('Dovrai fare di nuovo il login per accedere alle tue schede.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, true), child: const Text('Esci')),
                  ],
                ),
              ) ?? false;
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
                const Text('Riepilogo Attività', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  color: Colors.deepOrange.withOpacity(0.2),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Icon(Icons.local_fire_department, size: 48, color: Colors.orange),
                        const SizedBox(height: 8),
                        Text('$allenamentiTotali', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                        const Text('Allenamenti Completati', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                if (ultimoAllenamento != null) ...[
                  const Text('Ultimo Allenamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                      title: Text(ultimoAllenamento!.scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text('Data: ${ultimoAllenamento!.data.day}/${ultimoAllenamento!.data.month}/${ultimoAllenamento!.data.year}'),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [Icon(Icons.emoji_events, color: Colors.amber), SizedBox(width: 8), Text('I Tuoi Record (PR)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.deepOrange, size: 28), onPressed: _mostraAggiungiPR)
                  ],
                ),
                const SizedBox(height: 16),

                if (eserciziTracciati.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Nessun esercizio in bacheca. Premi il tasto + per aggiungerne uno!', style: TextStyle(color: Colors.grey, fontSize: 16), textAlign: TextAlign.center),
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: eserciziTracciati.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black26),
                      itemBuilder: (context, index) {
                        String nomeEsercizio = DizionarioEsercizi.daIngleseAItaliano[eserciziTracciati[index]] ?? eserciziTracciati[index];
                        
                        // 👇 PULIZIA VISIVA DELLA PANCA
                        if (nomeEsercizio.toLowerCase().contains('panca piana con bilanciere')) {
                          nomeEsercizio = 'Panca Piana';
                        }

                        var matches = tuttiIPR.keys.where((k) => k.toLowerCase() == nomeEsercizio.toLowerCase());
                        double maxPeso = matches.isNotEmpty ? tuttiIPR[matches.first]! : 0.0;
                        String pesoMostrato = maxPeso == 0.0 ? '--' : (maxPeso == maxPeso.truncateToDouble() ? maxPeso.toInt().toString() : maxPeso.toString());

                        return ListTile(
                          leading: const Icon(Icons.fitness_center, color: Colors.deepOrange),
                          title: Text(nomeEsercizio, style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(maxPeso > 0 ? '$pesoMostrato kg' : 'Nessun dato', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: maxPeso > 0 ? Colors.green : Colors.grey)),
                              const SizedBox(width: 8),
                              IconButton(icon: const Icon(Icons.close, color: Colors.redAccent, size: 20), onPressed: () { setState(() { eserciziTracciati.removeAt(index); }); _salvaTracciati(); })
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

  // 👇 NUOVA FUNZIONE: DUPLICA SCHEDA
  void _duplicaScheda(Scheda schedaOriginale) {
    // Trasforma in JSON e ricrea, così è un clone perfetto "staccato" dall'originale
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
                                        
                                        // 👇 QUI ABBIAMO INSERITO IL BOTTONE DUPLICA
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
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
// ============================================================================
// SCHERMATA MODALITÀ PR (VERSIONE ANTI-CRASH)
// ============================================================================
class PRModeScreen extends StatefulWidget {
  const PRModeScreen({super.key});

  @override
  State<PRModeScreen> createState() => _PRModeScreenState();
}

class _PRModeScreenState extends State<PRModeScreen> {
  Map<String, double> iMieiPRStorici = {};
  Map<String, double> prManuali = {};

  final List<String> _eserciziFissi = ['Panca', 'Squat', 'Stacco'];
  String _esercizioSelezionato = 'Panca';

  final TextEditingController _maxController = TextEditingController();
  
  double pesoSelezionatoPerBilanciere = 0.0;
  double pesoBilanciereVuoto = 20.0; 

  bool _modalitaWarmup = true; 
  Set<int> _indiciCompletati = {};
  
  double _prInizialeSessione = 0.0;
  double _percentualeAttuale = 0.0;
  
  // 👇 LUCCHETTO ANTI-CRASH PER I TIMER MULTIPLI
  bool _isTimerOpen = false;

  final List<Map<String, dynamic>> progressioneWarmup = [
    {'sets': '1', 'reps': '5', 'perc': 50.0},
    {'sets': '1', 'reps': '4', 'perc': 60.0},
    {'sets': '1', 'reps': '3', 'perc': 70.0},
    {'sets': '1', 'reps': '2', 'perc': 80.0},
    {'sets': '1', 'reps': '1', 'perc': 90.0},
    {'sets': '2', 'reps': '1', 'perc': 95.0},
    {'sets': '1', 'reps': '1', 'perc': 100.0},
    {'sets': '1', 'reps': '1', 'perc': 102.5, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 105.0, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 107.5, 'pr': true},
    {'sets': '1', 'reps': '1', 'perc': 110.0, 'pr': true},
  ];

  @override
  void initState() {
    super.initState();
    _caricaDatiMemoria();
  }

  String _getNomeEsteso(String es) {
    if (es == 'Panca') return 'Panca Piana';
    if (es == 'Stacco') return 'Stacco da Terra';
    return es; 
  }

  Future<void> _caricaDatiMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? prStoriciJson = prefs.getString('personal_records');
    if (prStoriciJson != null) {
      Map<String, dynamic> decodificati = jsonDecode(prStoriciJson);
      decodificati.forEach((key, value) { iMieiPRStorici[key] = (value as num).toDouble(); });
    }

    final String? manualiJson = prefs.getString('pr_manuali_salvati');
    if (manualiJson != null) {
      Map<String, dynamic> decodificati = jsonDecode(manualiJson);
      decodificati.forEach((key, value) { prManuali[key] = (value as num).toDouble(); });
    }
    
    _aggiornaUI();
    
    setState(() {
      _prInizialeSessione = prManuali[_esercizioSelezionato] ?? iMieiPRStorici[_getNomeEsteso(_esercizioSelezionato)] ?? 0.0;
    });
  }

  Future<void> _salvaPRInStorico(String nomeEs, double peso, double perc, String reps) async {
    String nomeEsteso = _getNomeEsteso(nomeEs);
    String dataIso = DateTime.now().toIso8601String();
    String nomeScheda = '🏆 TEST PR: $nomeEsteso';
    String feedback = 'Miglior alzata: $nomeEsteso a $peso kg ($perc%)';
    
    Map<String, dynamic> fakeJson = {
      'data': dataIso,
      'note': feedback,
      'scheda': {
        'nome': nomeScheda,
        'livello': 'Massimale',
        'categoria': 'Test PR',
        'esercizi': [
          {
            'nome': nomeEsteso,
            'avvicinamento': 0,
            'workingSet': 1,
            'ripetizioni': reps,
            'recupero': '0',
            'tecniche': ['Test PR'],
            'note': '',
            'serieAttive': [
              {
                'tipo': 'Nuovo PR',
                'peso': peso.toString(),
                'ripetizioniFatte': reps,
                'isCompletata': true,
                'rpe': '10'
              }
            ]
          }
        ]
      }
    };

    final nuovoAll = Allenamento.fromJson(fakeJson);
    final prefs = await SharedPreferences.getInstance();
    final String? storicoJson = prefs.getString('storico_salvato');
    List<dynamic> listaLocale = storicoJson != null ? jsonDecode(storicoJson) : [];
    listaLocale.add(nuovoAll.toJson());
    await prefs.setString('storico_salvato', jsonEncode(listaLocale));

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('storico_atleti').add({
          'atletaId': user.uid,
          'atletaEmail': user.email,
          'data': dataIso,
          'nomeScheda': nomeScheda,
          'feedback_atleta': feedback, 
          'esercizi': [
            {
              'nome': nomeEsteso,
              'target_ripetizioni': reps,
              'tecniche': ['Test PR'],
              'serie': [
                {
                  'peso': peso.toString(),
                  'tipo': 'Nuovo PR'
                }
              ]
            }
          ]
        });
      } catch (e) {
        debugPrint("Errore invio PR al database: $e");
      }
    }
  }

  Future<void> _salvaPRManuale(String es, double peso) async {
    prManuali[es] = peso;
    String nomeEsteso = _getNomeEsteso(es);
    iMieiPRStorici[nomeEsteso] = peso; 

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pr_manuali_salvati', jsonEncode(prManuali));

    String? prJson = prefs.getString('personal_records');
    Map<String, dynamic> prGlobali = prJson != null ? jsonDecode(prJson) : {};
    prGlobali[nomeEsteso] = peso;
    await prefs.setString('personal_records', jsonEncode(prGlobali));

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'personal_records': prGlobali, 
          'ultimo_aggiornamento_pr': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Errore sync PR: $e");
      }
    }
  }

  void _aggiornaUI() {
    String nomeEsteso = _getNomeEsteso(_esercizioSelezionato);
    double pesoCaricato = prManuali[_esercizioSelezionato] ?? iMieiPRStorici[nomeEsteso] ?? 0.0;
    
    setState(() {
      if (pesoCaricato > 0) {
        _maxController.text = pesoCaricato == pesoCaricato.truncateToDouble() ? pesoCaricato.toInt().toString() : pesoCaricato.toString();
        pesoSelezionatoPerBilanciere = pesoCaricato;
      } else {
        _maxController.text = '';
        pesoSelezionatoPerBilanciere = 0.0;
      }
    });
  }

  // 👇 SICUREZZA ANTI-CRASH 1: Capped dischi calculation
  List<double> _calcolaDischi(double pesoTotale) {
    List<double> dischiDaCaricare = [];
    if (pesoTotale <= pesoBilanciereVuoto || pesoTotale > 2000) return dischiDaCaricare; // Evita loop su pesi impossibili
    
    double pesoDaAggiungere = (pesoTotale - pesoBilanciereVuoto) / 2;
    List<double> pezzature = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
    
    for (var disco in pezzature) {
      while (pesoDaAggiungere >= disco) {
        dischiDaCaricare.add(disco);
        pesoDaAggiungere -= disco;
        if (dischiDaCaricare.length > 30) break; // Limite di sicurezza: max 30 dischi a lato
      }
    }
    return dischiDaCaricare;
  }

  Color _coloreDisco(double peso) {
    if (peso == 25.0) return Colors.red.shade700;
    if (peso == 20.0) return Colors.blue.shade700;
    if (peso == 15.0) return Colors.yellow.shade700;
    if (peso == 10.0) return Colors.green.shade700;
    if (peso == 5.0) return Colors.white;
    if (peso == 2.5) return Colors.black;
    return Colors.grey.shade400; 
  }

  double _altezzaDisco(double peso) {
    if (peso >= 15.0) return 100.0; 
    if (peso == 10.0) return 80.0;
    if (peso == 5.0) return 60.0;
    if (peso == 2.5) return 50.0;
    return 40.0; 
  }

  Widget _disegnaBilanciere(double pesoTotale) {
    List<double> dischi = _calcolaDischi(pesoTotale);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepOrange.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Text(pesoTotale > 0 ? '$pesoTotale kg' : 'Inserisci il Massimale', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          if (pesoTotale >= pesoBilanciereVuoto)
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 15, width: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600, Colors.grey.shade400], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(4)),
                  ),
                  Positioned(left: MediaQuery.of(context).size.width * 0.25, child: Container(height: 40, width: 10, color: Colors.grey.shade800)),
                  Positioned(
                    left: MediaQuery.of(context).size.width * 0.25 + 12,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.5,
                      // 👇 SICUREZZA ANTI-CRASH 2: Bilanciere scrollabile se ha troppi dischi
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: dischi.map((d) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1), height: _altezzaDisco(d), width: 16,
                            decoration: BoxDecoration(color: _coloreDisco(d), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black54, width: 1)),
                            child: Center(child: RotatedBox(quarterTurns: 3, child: Text(d.toString().replaceAll('.0', ''), style: TextStyle(color: d == 5.0 || d == 15.0 || d == 1.25 ? Colors.black : Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
                          )).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Text('Troppo leggero per il bilanciere!', style: TextStyle(color: Colors.amber)),
        ],
      ),
    );
  }

  Widget _buildBarraProgresso() {
    Color barColor = Colors.grey;
    if (_percentualeAttuale >= 102.5) barColor = Colors.purpleAccent;
    else if (_percentualeAttuale == 100) barColor = Colors.redAccent;
    else if (_percentualeAttuale >= 90) barColor = Colors.orange;
    else if (_percentualeAttuale >= 70) barColor = Colors.blueAccent;
    else if (_percentualeAttuale > 0) barColor = Colors.green;

    double fillRatio = (_percentualeAttuale / 110.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _percentualeAttuale > 0 
            ? 'Intensità Massima Raggiunta: ${_percentualeAttuale.toString().replaceAll('.0', '')}%' 
            : 'Seleziona una spunta per riempire la barra',
          style: TextStyle(color: barColor, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              height: 14,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 1000), 
                    curve: Curves.elasticOut, 
                    width: constraints.maxWidth * fillRatio,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        if (_percentualeAttuale > 0)
                          BoxShadow(color: barColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 1) 
                      ]
                    ),
                  ),
                ],
              ),
            );
          }
        ),
      ],
    );
  }

 Future<bool> _concludiSessione(bool dalTastoIndietro) async {
    double maxAttuale = double.tryParse(_maxController.text.replaceAll(',', '.')) ?? 0.0;
    double maxPesoRaggiunto = 0.0;
    double maxPercRaggiunta = 0.0;
    String repsPerStorico = '1';

    for (int i in _indiciCompletati) {
      double perc = _modalitaWarmup ? progressioneWarmup[i]['perc'] : (110 - (i * 5)).toDouble();
      String reps = _modalitaWarmup ? progressioneWarmup[i]['reps'] : '1';
      double pesoCalcolato = (maxAttuale * (perc / 100));
      double pesoArrotondato = (pesoCalcolato / 2.5).round() * 2.5;

      if (pesoArrotondato > maxPesoRaggiunto) {
        maxPesoRaggiunto = pesoArrotondato;
        maxPercRaggiunta = perc;
        repsPerStorico = reps;
      }
    }

    if (maxPesoRaggiunto == 0.0) {
      if (!dalTastoIndietro) Navigator.pop(context);
      return true; 
    }

    bool isNuovoPR = maxPesoRaggiunto > _prInizialeSessione;
    bool aggiornaMassimale = isNuovoPR || _prInizialeSessione == 0;

    int? scelta = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(dalTastoIndietro ? 'Uscire dal Test?' : 'Finito PR? 🏆', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hai sollevato un carico massimo di $maxPesoRaggiunto kg.', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: CheckboxListTile(
                    activeColor: Colors.deepOrange,
                    title: const Text('Imposta come nuovo Massimale', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: aggiornaMassimale,
                    onChanged: (val) {
                      setDialogState(() => aggiornaMassimale = val ?? false);
                    },
                  ),
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
              // 👇 TASTO ROSSO PER SCARTARE TUTTO SE PREMI INDIETRO
              if (dalTastoIndietro)
                TextButton(onPressed: () => Navigator.pop(context, 1), child: const Text('Scarta ed Esci', style: TextStyle(color: Colors.redAccent))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, 2), 
                child: const Text('Salva Sessione')
              ),
            ],
          );
        }
      ),
    );

    if (scelta == null || scelta == 0) return false; // 0 = Annulla, resta lì

    // 👇 SE SCEGLIE SCARTA, ESCE E BASTA! Nessun salvataggio in cronologia.
    if (scelta == 1) {
      return true; 
    }

    // 👇 SE SCEGLIE SALVA, FA IL SALVATAGGIO
    if (scelta == 2) {
      if (aggiornaMassimale) {
        setState(() {
          _maxController.text = maxPesoRaggiunto == maxPesoRaggiunto.truncateToDouble() ? maxPesoRaggiunto.toInt().toString() : maxPesoRaggiunto.toString();
        });
        await _salvaPRManuale(_esercizioSelezionato, maxPesoRaggiunto);
        _prInizialeSessione = maxPesoRaggiunto; 
      }
      
      await _salvaPRInStorico(_esercizioSelezionato, maxPesoRaggiunto, maxPercRaggiunta, repsPerStorico);

      if (!mounted) return true;

      if (aggiornaMassimale && isNuovoPR) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nuovo Record di $_esercizioSelezionato: $maxPesoRaggiunto kg! 🏆🔥'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ottimo lavoro! $maxPesoRaggiunto kg salvati in cronologia 💪'), backgroundColor: Colors.blueAccent, duration: const Duration(seconds: 4)));
      }

      if (!dalTastoIndietro) {
        Navigator.pop(context); 
      }
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    double maxAttuale = double.tryParse(_maxController.text.replaceAll(',', '.')) ?? 0.0;

    return WillPopScope(
      onWillPop: () async {
        if (_indiciCompletati.isEmpty) return true; 
        return await _concludiSessione(true);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Modalità PR 👑')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: _eserciziFissi.map((es) {
                  bool isSelected = _esercizioSelezionato == es;
                  return ChoiceChip(
                    label: Text(es, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSelected ? Colors.white : Colors.grey)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() { 
                        _esercizioSelezionato = es; 
                        _indiciCompletati.clear(); 
                        _percentualeAttuale = 0.0; 
                      });
                      _aggiornaUI();
                      
                      setState(() {
                        _prInizialeSessione = prManuali[_esercizioSelezionato] ?? iMieiPRStorici[_getNomeEsteso(_esercizioSelezionato)] ?? 0.0;
                      });
                    },
                    selectedColor: Colors.deepOrange,
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _maxController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.amber),
                decoration: InputDecoration(
                  labelText: 'Massimale (1RM) $_esercizioSelezionato in Kg', labelStyle: const TextStyle(fontSize: 16),
                  border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.fitness_center, color: Colors.amber),
                  
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save, color: Colors.greenAccent),
                    tooltip: 'Salva il peso sul bilanciere come Massimale',
                    onPressed: () {
                      double p = pesoSelezionatoPerBilanciere; 
                      if (p > 0) {
                        _salvaPRManuale(_esercizioSelezionato, p);
                        setState(() { 
                          _prInizialeSessione = p; 
                          _maxController.text = p == p.truncateToDouble() ? p.toInt().toString() : p.toString();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Massimale aggiornato a $p kg! 💾'), backgroundColor: Colors.green));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessun peso selezionato sul bilanciere!'), backgroundColor: Colors.red));
                      }
                    }
                  )
                ),
                onChanged: (val) {
                  double p = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                  setState(() { 
                    pesoSelezionatoPerBilanciere = p; 
                    _indiciCompletati.clear(); 
                    _percentualeAttuale = 0.0; 
                  });
                },
              ),
              const SizedBox(height: 16),

              _disegnaBilanciere(pesoSelezionatoPerBilanciere),
              const SizedBox(height: 20),

              _buildBarraProgresso(),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Protocollo PR', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _modalitaWarmup,
                    onSelected: (val) => setState(() { _modalitaWarmup = true; _indiciCompletati.clear(); _percentualeAttuale = 0.0; }),
                    selectedColor: Colors.blueAccent, backgroundColor: Colors.black26,
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Tutte le %', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: !_modalitaWarmup,
                    onSelected: (val) => setState(() { _modalitaWarmup = false; _indiciCompletati.clear(); _percentualeAttuale = 0.0; }),
                    selectedColor: Colors.blueAccent, backgroundColor: Colors.black26,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), 
                itemCount: _modalitaWarmup ? progressioneWarmup.length + 1 : 13, 
                itemBuilder: (context, index) {
                  
                  if (_modalitaWarmup && index == progressioneWarmup.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black45, foregroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.blueAccent)),
                        ),
                        onPressed: () {
                          setState(() {
                            double ultimaPerc = progressioneWarmup.last['perc'];
                            progressioneWarmup.add({'sets': '1', 'reps': '1', 'perc': ultimaPerc + 2.5, 'pr': true});
                          });
                        }, 
                        icon: const Icon(Icons.add), label: const Text('Aggiungi tentativo (+2.5%)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }

                  double percentuale = 0.0;
                  String titoloSetsReps = "";
                  bool isNuovoPR = false;

                  if (_modalitaWarmup) {
                    var step = progressioneWarmup[index];
                    percentuale = step['perc'];
                    titoloSetsReps = "${step['sets']} x ${step['reps']} ";
                    isNuovoPR = step['pr'] == true;
                  } else {
                    percentuale = (110 - (index * 5)).toDouble(); 
                  }

                  double pesoCalcolato = (maxAttuale * (percentuale / 100));
                  double pesoArrotondato = (pesoCalcolato / 2.5).round() * 2.5;

                  Color avatarColor = Colors.green;
                  if (percentuale >= 102.5) avatarColor = Colors.purpleAccent;
                  else if (percentuale == 100) avatarColor = Colors.redAccent;
                  else if (percentuale >= 90) avatarColor = Colors.orange;
                  else if (percentuale >= 70) avatarColor = Colors.blueAccent;

                  bool isSelezionato = _indiciCompletati.contains(index);

                  return Card(
                    color: pesoSelezionatoPerBilanciere == pesoArrotondato ? Colors.deepOrange.withOpacity(0.3) : const Color(0xFF1E1E1E),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: avatarColor,
                        child: Text('${percentuale.toString().replaceAll('.0', '')}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      title: Row(
                        children: [
                          if (_modalitaWarmup) Text(titoloSetsReps, style: TextStyle(fontSize: 18, color: Colors.grey.shade400)),
                          Text('$pesoArrotondato kg', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text('Esatto: ${pesoCalcolato.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12)),
                          if (isNuovoPR) ...[
                            const SizedBox(width: 8),
                            const Text('🌟 TENTATIVO PR', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold))
                          ]
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isSelezionato ? Icons.check_circle : Icons.radio_button_unchecked, 
                          color: isSelezionato ? Colors.greenAccent : Colors.grey, 
                          size: 28
                        ),
                        tooltip: 'Spunta il Set',
                        onPressed: () {
                          setState(() {
                            if (isSelezionato) {
                              _indiciCompletati.remove(index);
                            } else {
                              _indiciCompletati.add(index);
                              pesoSelezionatoPerBilanciere = pesoArrotondato;
                            }
                            
                            _percentualeAttuale = 0.0;
                            for (int i in _indiciCompletati) {
                              double p = _modalitaWarmup ? progressioneWarmup[i]['perc'] : (110 - (i * 5)).toDouble();
                              if (p > _percentualeAttuale) _percentualeAttuale = p;
                            }
                          });
                          
                          // 👇 SICUREZZA ANTI-CRASH 3: Impedisce l'apertura di più Timer simultanei
                          if (!isSelezionato && !_isTimerOpen) {
                            _isTimerOpen = true; 
                            
                            int secondiRecupero = 150; 
                            if (percentuale >= 90) secondiRecupero = 300; 
                            else if (percentuale >= 70) secondiRecupero = 210; 

                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => PRTimerWidget(secondiTotali: secondiRecupero),
                            ).then((_) {
                              // Quando il timer si chiude (o lo chiudi tu), sblocca il lucchetto
                              _isTimerOpen = false;
                            });
                          }
                        },
                      ),
                      onTap: () { setState(() { pesoSelezionatoPerBilanciere = pesoArrotondato; }); },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        bottomNavigationBar: _indiciCompletati.isNotEmpty 
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                  ),
                  onPressed: () => _concludiSessione(false),
                  icon: const Icon(Icons.emoji_events, color: Colors.white, size: 28),
                  label: const Text('Finito PR 🏆', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ),
            )
          : const SizedBox.shrink(),
      ),
    );
  }
}

// ============================================================================
// WIDGET DEL TIMER DI RECUPERO DEDICATO ALLA MODALITÀ PR
// ============================================================================
class PRTimerWidget extends StatefulWidget {
  final int secondiTotali;
  const PRTimerWidget({super.key, required this.secondiTotali});

  @override
  State<PRTimerWidget> createState() => _PRTimerWidgetState();
}

class _PRTimerWidgetState extends State<PRTimerWidget> {
  late int _rimanenti;
  Timer? _timerCount;

  @override
  void initState() {
    super.initState();
    _rimanenti = widget.secondiTotali;
    
    _timerCount = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rimanenti > 0) { 
        if (mounted) setState(() => _rimanenti--); 
      } else {
        _timerCount?.cancel(); 
      }
    });
  }

  @override
  void dispose() { 
    _timerCount?.cancel(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    int m = _rimanenti ~/ 60; 
    int s = _rimanenti % 60;
    bool isAllarme = _rimanenti == 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E), 
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      padding: const EdgeInsets.all(30), 
      height: 280,
      child: Column(
        children: [
          Text(
            isAllarme ? 'SVEGLIA! SOTTO IL BILANCIERE! 🔥' : 'RECUPERO SISTEMA NERVOSO 🧠', 
            style: TextStyle(
              letterSpacing: 2, 
              color: isAllarme ? Colors.redAccent : Colors.grey, 
              fontSize: 14, 
              fontWeight: FontWeight.bold
            )
          ),
          const SizedBox(height: 10),
          Text(
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}', 
            style: TextStyle(
              fontSize: 80, 
              fontWeight: FontWeight.bold, 
              color: isAllarme ? Colors.redAccent : Colors.white
            )
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isAllarme ? Colors.redAccent : Colors.deepOrange, 
              minimumSize: const Size(double.infinity, 60), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () => Navigator.pop(context), 
            child: Text(
              isAllarme ? "LET'S GO!" : 'SALTA TIMER', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)
            )
          ),
        ],
      ),
    );
  }
}