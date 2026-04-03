import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'libreria_schede_screen.dart';
import 'invia_scheda_screen.dart';

// ============================================================================
// 1. SCHERMATA PRINCIPALE (HUB COACH)
// ============================================================================
class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagina Allenatore', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
            tooltip: 'Esci',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // CARDA LIBRERIA
            _buildMenuCard(
              title: "Libreria Schede",
              subtitle: "Crea e gestisci i tuoi template master",
              icon: Icons.library_books,
              color: Colors.blueAccent,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => const LibreriaSchedeScreen())); 
              },
            ),
            const SizedBox(height: 20),
            // CARDA ATLETI
            _buildMenuCard(
              title: "I miei Atleti",
              subtitle: "Gestisci allievi, vedi log e invia schede",
              icon: Icons.people_alt,
              color: Colors.deepOrange,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ListaAtletiScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 2. LISTA DEGLI ATLETI COLLEGATI
// ============================================================================
class ListaAtletiScreen extends StatefulWidget {
  const ListaAtletiScreen({super.key});

  @override
  State<ListaAtletiScreen> createState() => _ListaAtletiScreenState();
}

class _ListaAtletiScreenState extends State<ListaAtletiScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  void _aggiungiAtletaDialog() {
    TextEditingController emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Aggiungi Atleta 🏃‍♂️', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Inserisci l\'email dell\'atleta registrato su Tiger.', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'email@atleta.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email, color: Colors.deepOrange),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            onPressed: () => _collegaAtleta(emailController.text.trim()),
            child: const Text('Collega'),
          ),
        ],
      ),
    );
  }

  Future<void> _collegaAtleta(String email) async {
    if (email.isEmpty) return;
    Navigator.pop(context);
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)));

    try {
      final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).where('ruolo', isEqualTo: 'atleta').get();
      if (!mounted) return;
      Navigator.pop(context);

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessun atleta trovato con questa email.'), backgroundColor: Colors.red));
        return;
      }

      final atletaDoc = query.docs.first;
      if (atletaDoc['coachId'] != null && atletaDoc['coachId'].toString().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Questo atleta ha già un coach!'), backgroundColor: Colors.orange));
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(atletaDoc.id).update({'coachId': currentUser!.uid});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atleta collegato con successo! 🎉'), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('I miei Atleti')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepOrange,
        onPressed: _aggiungiAtletaDialog,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('ruolo', isEqualTo: 'atleta').where('coachId', isEqualTo: currentUser?.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Non hai ancora collegato nessun atleta.", style: TextStyle(color: Colors.grey, fontSize: 16)));
          }

          final atleti = snapshot.data!.docs;
          return ListView.builder(
            itemCount: atleti.length,
            itemBuilder: (context, index) {
              var atleta = atleti[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.person, color: Colors.white)),
                  title: Text(atleta['email'] ?? 'Senza email', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => HubAtletaScreen(
                        atletaId: atleti[index].id,
                        atletaEmail: atleta['email'] ?? 'Atleta',
                      ),
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 3. HUB DEL SINGOLO ATLETA (Scelta: Log o Invia Scheda)
// ============================================================================
class HubAtletaScreen extends StatelessWidget {
  final String atletaId;
  final String atletaEmail;

  const HubAtletaScreen({super.key, required this.atletaId, required this.atletaEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(atletaEmail, style: const TextStyle(fontSize: 18))),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                leading: const Icon(Icons.history_outlined, color: Colors.greenAccent, size: 36),
                title: const Text("Log Allenamenti", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: const Text("Vedi lo storico e i carichi sollevati"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => LogAtletaSpecificoScreen(atletaId: atletaId, atletaEmail: atletaEmail)));
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                leading: const Icon(Icons.send_rounded, color: Colors.deepOrange, size: 36),
                title: const Text("Invia Nuova Scheda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: const Text("Assegna un allenamento dalla libreria"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (c) => InviaSchedaScreen(
                        atletaId: atletaId, 
                        atletaEmail: atletaEmail
                      )
                    ));
                  },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. LOG ALLENAMENTI FILTRATI PER ATLETA (CON FILTRO 30 GIORNI E TAG VISIBILI)
// ============================================================================
class LogAtletaSpecificoScreen extends StatelessWidget {
  final String atletaId;
  final String atletaEmail;

  const LogAtletaSpecificoScreen({super.key, required this.atletaId, required this.atletaEmail});

  Widget _buildListaLog(BuildContext context, List<Map<String, dynamic>> logs) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          "Nessun allenamento completato negli ultimi 30 giorni.",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final bool hasFeedback =
            log['feedback_atleta'] != null && log['feedback_atleta'].toString().trim().isNotEmpty;

        return Card(
          child: ListTile(
            leading: const Icon(Icons.fitness_center, color: Colors.deepOrange),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    log['nomeScheda'] ?? 'Allenamento',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (hasFeedback) const Icon(Icons.chat_bubble, color: Colors.amber, size: 16),
              ],
            ),
            subtitle: Text("Data: ${log['data'].toString().split('T')[0]}"),
            trailing: const Icon(Icons.visibility, color: Colors.grey),
            onTap: () => _mostraDettaglioLog(context, log),
          ),
        );
      },
    );
  }

  void _mostraDettaglioLog(BuildContext context, Map<String, dynamic> log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        List esercizi = log['esercizi'] ?? [];
        String? notaAtleta = log['feedback_atleta']; 

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text("Dettaglio: ${log['nomeScheda']}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Completato il: ${log['data'].toString().split('T')[0]}", style: const TextStyle(color: Colors.grey)),
                  const Divider(height: 30),

                  // BOX GIALLO PER IL FEEDBACK
                  if (notaAtleta != null && notaAtleta.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        border: const Border(left: BorderSide(color: Colors.amber, width: 4)),
                        borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💬 Feedback dell\'Atleta:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(notaAtleta, style: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),

                  // LISTA ESERCIZI CON TECNICHE (TAG) VISIBILI AL COACH
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: esercizi.length,
                      itemBuilder: (context, i) {
                        var es = esercizi[i];
                        List serie = es['serie'] ?? [];
                        
                        // ESTRAZIONE DELLE TECNICHE USATE (Es. Monopodalico, Drop Set)
                        List tecniche = es['tecniche'] ?? [];
                        String tecnicheStr = tecniche.isNotEmpty ? "\n🔹 Tecniche: ${tecniche.join(', ')}" : "";

                        return ExpansionTile(
                          initiallyExpanded: true,
                          title: Text(es['nome'] ?? 'Esercizio', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                          
                          // SOTTOTITOLO CON TARGET E TECNICHE
                          subtitle: Text("Target: ${es['target_ripetizioni'] ?? '?'} rip$tecnicheStr", 
                            style: TextStyle(color: tecniche.isNotEmpty ? Colors.cyanAccent : Colors.grey, fontSize: 13)
                          ),
                          
                          children: serie.map((s) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            title: Text("Sollevato: ${s['peso']} kg (${s['tipo']})", style: const TextStyle(fontSize: 16)),
                          )).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentCoachId = FirebaseAuth.instance.currentUser?.uid;
    final DateTime dataLimite = DateTime.now().subtract(const Duration(days: 30));
    final String dataLimiteStr = dataLimite.toIso8601String();

    if (currentCoachId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Storico (Ultimi 30 gg)")),
        body: const Center(
          child: Text('Sessione scaduta. Rientra come coach.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Storico (Ultimi 30 gg)")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('coaches')
            .doc(currentCoachId)
            .collection('athletes')
            .doc(atletaId)
            .collection('progress')
            .where('sessionAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dataLimite))
            .orderBy('sessionAt', descending: true)
            .snapshots(),
        builder: (context, snapshotNuovoSchema) {
          if (snapshotNuovoSchema.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final nuoviLogs = snapshotNuovoSchema.data?.docs
                  .map((doc) => doc.data())
                  .where((log) => (log['data'] ?? '').toString().isNotEmpty)
                  .toList() ??
              const <Map<String, dynamic>>[];

          if (nuoviLogs.isNotEmpty) {
            return _buildListaLog(context, nuoviLogs);
          }

          // Fallback compatibile con storico precedente durante la migrazione.
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('storico_atleti')
                .where('atletaId', isEqualTo: atletaId)
                .where('data', isGreaterThanOrEqualTo: dataLimiteStr)
                .orderBy('data', descending: true)
                .snapshots(),
            builder: (context, snapshotLegacy) {
              if (snapshotLegacy.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final legacyLogs = snapshotLegacy.data?.docs
                      .map((doc) => doc.data() as Map<String, dynamic>)
                      .toList() ??
                  const <Map<String, dynamic>>[];

              return _buildListaLog(context, legacyLogs);
            },
          );
        },
      ),
    );
  }
}