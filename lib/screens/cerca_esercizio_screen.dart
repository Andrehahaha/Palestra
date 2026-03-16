import 'package:flutter/material.dart';
import '../services/api_esercizi.dart'; 
import '../services/dizionario_esercizi.dart'; // <--- AGGIUNTO L'IMPORT MAGICO

class CercaEsercizioScreen extends StatefulWidget {
  const CercaEsercizioScreen({super.key});

  @override
  State<CercaEsercizioScreen> createState() => _CercaEsercizioScreenState();
}

class _CercaEsercizioScreenState extends State<CercaEsercizioScreen> {
  List<Map<String, dynamic>> tuttiEsercizi = [];
  List<Map<String, dynamic>> eserciziFiltrati = [];
  bool _isLoading = true;
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _caricaDati();
  }

  Future<void> _caricaDati() async {
    final dati = await ApiEsercizi.ottieniEserciziTradotti();
    
    // Mettiamo in ordine alfabetico
    dati.sort((a, b) => a['nome'].toString().compareTo(b['nome'].toString()));

    if (mounted) {
      setState(() {
        tuttiEsercizi = dati;
        eserciziFiltrati = dati;
        _isLoading = false;
      });
    }
  }

  // <--- MODIFICATO: LA RICERCA ORA È BILINGUE (ITALIANO + INGLESE)
  void _filtraEsercizi(String query) {
    setState(() {
      if (query.isEmpty) {
        eserciziFiltrati = tuttiEsercizi;
      } else {
        String queryLower = query.toLowerCase();

        eserciziFiltrati = tuttiEsercizi.where((es) {
          String nomeIta = es['nome'].toString();
          
          // 1. Cerca nel nome in italiano
          bool matchItaliano = nomeIta.toLowerCase().contains(queryLower);
          
          // 2. Cerca nel nome in inglese originale (usando il dizionario al contrario)
          bool matchInglese = false;
          for (var entry in DizionarioEsercizi.daIngleseAItaliano.entries) {
            // Se troviamo l'esercizio nel dizionario
            if (entry.value == nomeIta) {
              // Controlliamo se la chiave (il nome inglese) contiene quello che ha scritto l'utente
              if (entry.key.toLowerCase().contains(queryLower)) {
                matchInglese = true;
              }
              break; // Fermiamo il ciclo, abbiamo trovato il corrispondente inglese
            }
          }

          // Ritorna l'esercizio se fa match con l'italiano OPPURE con l'inglese
          return matchItaliano || matchInglese;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Libreria Esercizi'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filtraEsercizi,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Cerca (es. Bench Press, Squat)...',
                prefixIcon: const Icon(Icons.search, color: Colors.deepOrange),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _filtraEsercizi('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1), // Corretto withOpacity per compatibilità
              ),
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
                : eserciziFiltrati.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('Nessun esercizio trovato.', style: TextStyle(color: Colors.grey, fontSize: 18)),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                              onPressed: () {
                                Navigator.pop(context, _searchController.text); // Restituisce quello che hai scritto!
                              },
                              child: const Text('Usa questo nome personalizzato', style: TextStyle(color: Colors.white)),
                            )
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: eserciziFiltrati.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
                        itemBuilder: (context, index) {
                          final es = eserciziFiltrati[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.deepOrange,
                              child: Icon(Icons.fitness_center, color: Colors.white, size: 20),
                            ),
                            title: Text(es['nome'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.add_circle_outline, color: Colors.deepOrange),
                            onTap: () {
                              Navigator.pop(context, es['nome']); // Restituisce il nome cliccato (in italiano!)
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}