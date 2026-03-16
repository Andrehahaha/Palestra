import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/scheda.dart';

class SelezionaSchedaLibreria extends StatefulWidget {
  const SelezionaSchedaLibreria({super.key});

  @override
  State<SelezionaSchedaLibreria> createState() => _SelezionaSchedaLibreriaState();
}

class _SelezionaSchedaLibreriaState extends State<SelezionaSchedaLibreria> {
  List<Scheda> _schedeSalvate = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _caricaLibreria();
  }

  // Peschiamo le schede salvate in locale dal Coach
  Future<void> _caricaLibreria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? dati = prefs.getString('schede_salvate');
    if (dati != null) {
      setState(() {
        _schedeSalvate = (jsonDecode(dati) as List).map((e) => Scheda.fromJson(e)).toList();
      });
    }
    setState(() { _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seleziona dalla Libreria 📚')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
          : _schedeSalvate.isEmpty
              ? const Center(child: Text('Nessuna scheda nella tua libreria.\nCreale prima dal tab "Allenamenti"!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _schedeSalvate.length,
                  itemBuilder: (context, index) {
                    final scheda = _schedeSalvate[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.library_books, color: Colors.deepOrange),
                        title: Text(scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${scheda.esercizi.length} esercizi • ${scheda.categoria}'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // Restituisce la scheda selezionata alla pagina precedente!
                          Navigator.pop(context, scheda);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}