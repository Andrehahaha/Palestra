import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/scheda.dart';

class InviaSchedaScreen extends StatefulWidget {
  final String atletaId;
  final String atletaEmail;

  const InviaSchedaScreen({super.key, required this.atletaId, required this.atletaEmail});

  @override
  State<InviaSchedaScreen> createState() => _InviaSchedaScreenState();
}

class _InviaSchedaScreenState extends State<InviaSchedaScreen> {
  List<Map<String, dynamic>> libreriaLocale = [];
  bool _isLoading = true;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _caricaLibreria();
  }

  // Leggiamo le schede che il coach ha già salvato in memoria
  Future<void> _caricaLibreria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? datiSalvati = prefs.getString('schede_salvate');

    List<Map<String, dynamic>> schedeCompatibili = [];
    if (datiSalvati != null) {
      final decoded = jsonDecode(datiSalvati);
      if (decoded is List) {
        schedeCompatibili = decoded
            .whereType<Map>()
            .map((raw) => Scheda.fromJson(Map<String, dynamic>.from(raw)).toJson())
            .toList();
      }
    }

    if (schedeCompatibili.isEmpty && currentUser != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('libreria_coach')
            .doc(currentUser!.uid)
            .collection('schede')
            .get();

        schedeCompatibili = snapshot.docs
            .map((doc) => Scheda.fromJson(doc.data()).toJson())
            .toList();

        if (schedeCompatibili.isNotEmpty) {
          await prefs.setString('schede_salvate', jsonEncode(schedeCompatibili));
        }
      } catch (_) {
        // Manteniamo fallback silenzioso per non bloccare la UI.
      }
    }

    if (mounted) {
      setState(() {
        libreriaLocale = schedeCompatibili;
        _isLoading = false;
      });
    }
  }

  // La magia dell'invio su Firebase
  Future<void> _inviaScheda(Map<String, dynamic> schedaMaster) async {
    if (currentUser == null) return;

    // Chiediamo conferma prima di inviare
    bool conferma = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Invio 🚀'),
        content: Text('Vuoi davvero inviare "${schedaMaster['nome']}" a ${widget.atletaEmail}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Invia'),
          ),
        ],
      ),
    ) ?? false;

    if (!conferma) return;

    // Se confermato, mostriamo la rotella e inviamo
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)));

    try {
      // Prepariamo la scheda aggiungendo l'ID dell'atleta bersaglio
      final compatibile = Scheda.fromJson(Map<String, dynamic>.from(schedaMaster)).toJson();
      Map<String, dynamic> schedaDaInviare = Map<String, dynamic>.from(compatibile);
      schedaDaInviare['atletaId'] = widget.atletaId; 
      schedaDaInviare['assegnataDa'] = currentUser!.uid;
      schedaDaInviare['dataAssegnazione'] = DateTime.now().toIso8601String();

      // La spariamo nella collezione che l'atleta "ascolta"
      await FirebaseFirestore.instance.collection('schede_assegnate').add(schedaDaInviare);

      if (!mounted) return;
      Navigator.pop(context); // Chiude rotella
      Navigator.pop(context); // Torna all'Hub dell'atleta

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scheda inviata con successo a ${widget.atletaEmail}! 🎉'), backgroundColor: Colors.green)
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Chiude rotella
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante l\'invio: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scegli Scheda da Inviare'),
        backgroundColor: Colors.deepOrange.withValues(alpha: 0.2),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
        : libreriaLocale.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.library_books, size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        "La tua libreria è vuota!", 
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Prima di poter inviare una scheda a un atleta, devi creare almeno un Template Master dalla sezione 'Libreria Schede'.", 
                        textAlign: TextAlign.center, 
                        style: TextStyle(color: Colors.grey, fontSize: 16)
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context), 
                        child: const Text("Torna Indietro")
                      )
                    ],
                  ),
                ),
              )
            : ListView.builder(
                itemCount: libreriaLocale.length,
                itemBuilder: (context, index) {
                  var scheda = libreriaLocale[index];
                  String nomeScheda = scheda['nome'] ?? 'Scheda Senza Nome';
                  int numeroEsercizi = (scheda['esercizi'] as List?)?.length ?? 0;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.deepOrange, 
                        child: Icon(Icons.send, color: Colors.white)
                      ),
                      title: Text(nomeScheda, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text("$numeroEsercizi esercizi", style: const TextStyle(color: Colors.grey)),
                      trailing: const Text("INVIA", style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                      onTap: () => _inviaScheda(scheda), // Quando clicchi, parte l'invio!
                    ),
                  );
                },
              ),
    );
  }
}