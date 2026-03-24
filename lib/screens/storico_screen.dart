import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/allenamento.dart';
import '../services/dizionario_esercizi.dart'; 
import '../services/athlete_progress_service.dart';

class StoricoScreen extends StatefulWidget {
  final List<Allenamento> storico;
  final VoidCallback onUpdate; 

  const StoricoScreen({super.key, required this.storico, required this.onUpdate});

  @override
  State<StoricoScreen> createState() => _StoricoScreenState();
}

class _StoricoScreenState extends State<StoricoScreen> {

  Future<String?> _caricaCoachIdAtleta(String atletaId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(atletaId).get();
      if (!doc.exists) return null;
      final coachId = doc.data()?['coachId']?.toString().trim() ?? '';
      return coachId.isEmpty ? null : coachId;
    } catch (e) {
      debugPrint("Errore lettura coachId: $e");
      return null;
    }
  }

  // 👇 FUNZIONE CHE ELIMINA DAL CLOUD
  Future<void> _eliminaDaCloud(Allenamento allenamento) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final coachId = await _caricaCoachIdAtleta(user.uid);
      if (coachId != null && coachId.isNotEmpty) {
        final progressDocId = AthleteProgressService.buildDateKey(allenamento.data);
        final progressRef = FirebaseFirestore.instance
            .collection('coaches')
            .doc(coachId)
            .collection('athletes')
            .doc(user.uid)
            .collection('progress')
            .doc(progressDocId);

        final progressDoc = await progressRef.get();
        if (progressDoc.exists) {
          await progressRef.delete();
        }
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('storico_atleti')
          .where('atletaId', isEqualTo: user.uid)
          .where('data', isEqualTo: allenamento.data.toIso8601String())
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete(); // Uccide il file nel cloud!
      }
    } catch (e) {
      debugPrint("Errore eliminazione storico cloud: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final storicoInvertito = widget.storico.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Storico Allenamenti')),
      body: storicoInvertito.isEmpty
          ? const Center(child: Text('Nessun allenamento completato. Inizia ad allenarti!'))
          : ListView.builder(
              itemCount: storicoInvertito.length,
              itemBuilder: (context, index) {
                final allenamento = storicoInvertito[index];
                final d = allenamento.data;
                final dataFormat = '${d.day}/${d.month}/${d.year} - ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

                bool isTestPR = allenamento.scheda.nome.contains('🏆 TEST PR');

                return Dismissible(
                  key: ObjectKey(allenamento), 
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Elimina dalla cronologia"),
                        content: const Text("Vuoi davvero cancellare questo allenamento? Verrà rimosso anche dal database del Coach."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true), 
                            child: const Text("Elimina", style: TextStyle(color: Colors.red))
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) {
                    
                    // 👇 ELIMINA DAL DATABASE PRIMA DI ELIMINARE LOCALMENTE
                    _eliminaDaCloud(allenamento);

                    setState(() {
                      int originalIndex = widget.storico.indexOf(allenamento);
                      widget.storico.removeAt(originalIndex);
                    });
                    
                    widget.onUpdate(); 

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Rimossa definitivamente 🗑️")),
                    );
                  },
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white, size: 30),
                  ),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isTestPR ? Colors.purpleAccent.withOpacity(0.15) : const Color(0xFF1E1E1E),
                    shape: isTestPR 
                        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.purpleAccent, width: 2)) 
                        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: isTestPR ? Colors.purpleAccent : Colors.green,
                        child: Icon(isTestPR ? Icons.workspace_premium : Icons.emoji_events, color: Colors.white),
                      ),
                      title: Text(allenamento.scheda.nome, style: TextStyle(fontWeight: FontWeight.bold, color: isTestPR ? Colors.white : null)),
                      subtitle: Text(dataFormat, style: TextStyle(color: isTestPR ? Colors.purple.shade200 : Colors.grey)),
                      children: [
                        
                        if (allenamento.note != null && allenamento.note!.trim().isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 12),
                            padding: const EdgeInsets.all(12),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isTestPR ? Colors.purpleAccent.withOpacity(0.2) : Colors.amber.withOpacity(0.08),
                              border: Border(left: BorderSide(color: isTestPR ? Colors.purpleAccent : Colors.amber, width: 4)),
                              borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isTestPR ? '🏆 Dettagli:' : '📝 Note Allenamento:', style: TextStyle(color: isTestPR ? Colors.purpleAccent : Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(allenamento.note!, style: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),

                        ...allenamento.scheda.esercizi.map((es) {
                          final serieFatte = es.serieAttive.where((s) => s.isCompletata).toList();
                          if (serieFatte.isEmpty) return const SizedBox.shrink();

                          String nomeVisualizzato = DizionarioEsercizi.daIngleseAItaliano[es.nome] ?? es.nome;

                          return ListTile(
                            dense: true,
                            title: Text('🔹 $nomeVisualizzato', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              serieFatte.map((s) {
                                String p = s.peso.isEmpty ? '0' : s.peso;
                                String r = s.ripetizioniFatte.isEmpty ? '0' : s.ripetizioniFatte;
                                return '${p}kg x $r';
                              }).join('  |  '),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}