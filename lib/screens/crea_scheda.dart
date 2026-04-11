import 'package:flutter/material.dart';
import '../models/scheda.dart';
import '../models/esercizio.dart';
import 'crea_esercizio.dart'; 
import '../services/dizionario_esercizi.dart'; // <--- 1. AGGIUNTO IL DIZIONARIO MAGICO

class CreaSchedaScreen extends StatefulWidget {
  final Scheda? schedaDaModificare;

  const CreaSchedaScreen({super.key, this.schedaDaModificare});

  @override
  State<CreaSchedaScreen> createState() => _CreaSchedaScreenState();
}

class _CreaSchedaScreenState extends State<CreaSchedaScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _categoriaController = TextEditingController();
  String _livelloSelezionato = 'Principiante';
  bool _continuativa = true;
  int _settimanaCorrente = 1;
  
  List<Esercizio> _eserciziAggiunti = [];

  @override
  void initState() {
    super.initState();
    if (widget.schedaDaModificare != null) {
      _nomeController.text = widget.schedaDaModificare!.nome;
      _categoriaController.text = widget.schedaDaModificare!.categoria;
      _livelloSelezionato = widget.schedaDaModificare!.livello;
      _continuativa = widget.schedaDaModificare!.continuativa;
      _settimanaCorrente = widget.schedaDaModificare!.settimanaCorrente;
      _eserciziAggiunti = List.from(widget.schedaDaModificare!.esercizi); 
    }
  }

  void _gestisciEsercizio({Esercizio? esercizio, int? index}) async {
    final risultato = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreaEsercizioScreen(esercizioDaModificare: esercizio),
      ),
    );

    if (risultato != null && risultato is Esercizio) {
      setState(() {
        if (index != null) {
          _eserciziAggiunti[index] = risultato; // Modifica esistente
        } else {
          _eserciziAggiunti.add(risultato); // Aggiungi nuovo
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedaDaModificare != null ? 'Modifica Scheda ✏️' : 'Nuova Scheda'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _nomeController,
                  decoration: const InputDecoration(labelText: 'Nome della scheda', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _categoriaController,
                  decoration: const InputDecoration(labelText: 'Categoria / Cartella', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _livelloSelezionato, 
                  decoration: const InputDecoration(labelText: 'Livello', border: OutlineInputBorder()),
                  items: ['Principiante', 'Intermedio', 'Avanzato'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (val) => setState(() => _livelloSelezionato = val!),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scheda continuativa'),
                  subtitle: const Text('Se attiva, la scheda non ha scadenza e procede per settimane progressive.'),
                  value: _continuativa,
                  onChanged: (value) => setState(() => _continuativa = value),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settimana corrente: $_settimanaCorrente',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          Expanded(
            child: _eserciziAggiunti.isEmpty
                ? const Center(child: Text("Nessun esercizio. Aggiungine uno! 🏋️‍♂️", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _eserciziAggiunti.length,
                    itemBuilder: (context, index) {
                      final es = _eserciziAggiunti[index];
                      
                      // <--- 2. TRADUZIONE AL VOLO PER LA VISUALIZZAZIONE
                      final String nomeVisualizzato = DizionarioEsercizi.daIngleseAItaliano[es.nome] ?? es.nome;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          // Usiamo il nomeVisualizzato tradotto invece di es.nome originale
                          title: Text(nomeVisualizzato, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${es.serieAttive.length} serie • ${es.recupero}s rec"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => setState(() => _eserciziAggiunti.removeAt(index)),
                          ),
                          onTap: () => _gestisciEsercizio(esercizio: es, index: index),
                        ),
                      );
                    },
                  ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white
              ),
              onPressed: () {
                if (_nomeController.text.isNotEmpty) {
                  final nuovaScheda = Scheda(
                    nome: _nomeController.text,
                    livello: _livelloSelezionato,
                    categoria: _categoriaController.text.isEmpty ? 'Generale' : _categoriaController.text,
                    continuativa: _continuativa,
                    settimanaCorrente: _settimanaCorrente,
                    esercizi: _eserciziAggiunti, 
                  );
                  Navigator.pop(context, nuovaScheda);
                }
              },
              child: const Text('SALVA SCHEDA', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () => _gestisciEsercizio(),
        child: const Icon(Icons.add_task, color: Colors.white),
      ),
    );
  }
}