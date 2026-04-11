import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/scheda.dart';
import '../training/crea_scheda.dart';

class LibreriaSchedeScreen extends StatefulWidget {
  const LibreriaSchedeScreen({super.key});

  @override
  State<LibreriaSchedeScreen> createState() => _LibreriaSchedeScreenState();
}

class _LibreriaSchedeScreenState extends State<LibreriaSchedeScreen> {
  List<dynamic> libreriaLocale = []; 
  bool _isLoading = true;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _caricaSchedeInMemoria().then((_) => _sincronizzaCloud(silenzioso: true));
  }

  // 👇 1. CARICA VELOCEMENTE DAL LOCALE
  Future<void> _caricaSchedeInMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? datiSalvati = prefs.getString('schede_salvate');

    if (mounted) {
      setState(() {
        if (datiSalvati != null) {
          libreriaLocale = jsonDecode(datiSalvati);
        }
        _isLoading = false;
      });
    }
  }

  // 👇 2. SINCRONIZZAZIONE LOCALE <--> CLOUD
  Future<void> _sincronizzaCloud({bool silenzioso = false}) async {
    if (currentUser == null) return;
    
    if (!silenzioso) {
      showDialog(
        context: context, 
        barrierDismissible: false, 
        builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
      );
    }

    try {
      final collectionRef = FirebaseFirestore.instance
          .collection('libreria_coach')
          .doc(currentUser!.uid)
          .collection('schede');

      // FASE A: Aggiorniamo Firebase con i dati locali
      for (var scheda in libreriaLocale) {
        String nome = scheda['nome'] ?? 'Senza Nome';
        await collectionRef.doc(nome).set(scheda, SetOptions(merge: true));
      }

      // FASE B: Scarichiamo le ultime novità dal Cloud
      final snapshot = await collectionRef.get();
      List<dynamic> schedeCloud = snapshot.docs.map((doc) => doc.data()).toList();

      // FASE C: Aggiorniamo la memoria locale
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schede_salvate', jsonEncode(schedeCloud));

      if (mounted) {
        setState(() {
          libreriaLocale = schedeCloud;
        });
        if (!silenzioso) {
          Navigator.pop(context); // Chiude la rotella
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronizzazione completata! ☁️🔄'), backgroundColor: Colors.green)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (!silenzioso) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore Sync: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  // 👇 3. ELIMINA DA LOCALE E DA CLOUD
  Future<void> _eliminaScheda(int index) async {
    if (currentUser == null) return;
    
    var schedaDaEliminare = libreriaLocale[index];
    String nomeScheda = schedaDaEliminare['nome'] ?? 'Senza Nome';

    setState(() {
      libreriaLocale.removeAt(index);
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schede_salvate', jsonEncode(libreriaLocale));
    
    try {
      await FirebaseFirestore.instance
          .collection('libreria_coach')
          .doc(currentUser!.uid)
          .collection('schede')
          .doc(nomeScheda)
          .delete();
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scheda eliminata 🗑️')));
      }
    } catch (e) {
      debugPrint("Errore eliminazione cloud: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Libreria Schede 📚', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: Colors.blueAccent),
            onPressed: () => _sincronizzaCloud(silenzioso: false),
          )
        ],
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Crea Nuova", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          // 👇 SBLOCCATO: Ora puoi creare nuove schede master
          final nuovaScheda = await Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => const CreaSchedaScreen())
          );
          
          if (nuovaScheda != null && nuovaScheda is Scheda) {
            setState(() { 
              libreriaLocale.add(nuovaScheda.toJson()); 
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('schede_salvate', jsonEncode(libreriaLocale));
            
            _sincronizzaCloud(silenzioso: true);
          }
        },
      ),
      
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : libreriaLocale.isEmpty
            ? const Center(
                child: Text(
                  "Nessuna scheda master.\nPremi 'Crea Nuova' per iniziare!", 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey, fontSize: 16)
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: libreriaLocale.length,
                itemBuilder: (context, index) {
                  var schedaJson = libreriaLocale[index];
                  String nomeScheda = schedaJson['nome'] ?? 'Scheda Senza Nome';
                  String categoria = schedaJson['categoria'] ?? 'Senza categoria';
                  int numeroEsercizi = (schedaJson['esercizi'] as List?)?.length ?? 0;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), 
                      side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3))
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blueAccent, 
                        child: Icon(Icons.fitness_center, color: Colors.white)
                      ),
                      title: Text(nomeScheda, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text("$numeroEsercizi esercizi • $categoria"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _eliminaScheda(index),
                      ),
                      onTap: () async {
                        // 👇 MODIFICA SCHEDA ESISTENTE
                        Scheda schedaOriginale = Scheda.fromJson(schedaJson);

                        final schedaModificata = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreaSchedaScreen(schedaDaModificare: schedaOriginale), 
                          ),
                        );

                        if (schedaModificata != null && schedaModificata is Scheda) {
                          if (!mounted) return;
                          setState(() {
                            libreriaLocale[index] = schedaModificata.toJson();
                          });
                          
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('schede_salvate', jsonEncode(libreriaLocale));
                          
                          _sincronizzaCloud(silenzioso: true);
                        }
                      },
                    ),
                  );
                },
              ),
    );
  }
}