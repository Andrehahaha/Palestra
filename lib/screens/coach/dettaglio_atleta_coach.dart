import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/scheda.dart';
import '../../services/ai_service.dart';
import '../training/crea_scheda.dart';
import 'seleziona_scheda_libreria.dart'; // <-- NUOVO IMPORT

class DettaglioAtletaCoachScreen extends StatelessWidget {
  final String atletaId;
  final String atletaEmail;

  const DettaglioAtletaCoachScreen({
    super.key,
    required this.atletaId,
    required this.atletaEmail,
  });

  // --- CASELLO DI CONFERMA INVIO ---
  Future<void> _confermaEInvia(BuildContext context, List<Scheda> schedeDaInviare) async {
    bool confermato = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Conferma Invio 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Stai per inviare ${schedeDaInviare.length} scheda/e a $atletaEmail.\nVuoi procedere?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, true), child: const Text('Conferma e Invia')),
        ],
      ),
    ) ?? false;

    if (confermato && context.mounted) {
      _salvaSchedaSuFirebase(context, schedeDaInviare);
    }
  }

  // 1. FLUSSO: Da Scheda Nuova (Vuota)
  Future<void> _assegnaNuovaScheda(BuildContext context) async {
    final Scheda? nuovaScheda = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaSchedaScreen()));
    if (nuovaScheda != null && context.mounted) _confermaEInvia(context, [nuovaScheda]);
  }

  // 2. FLUSSO: Dalla Libreria del Coach 📚
  Future<void> _scegliDaLibreria(BuildContext context) async {
    // A. Scegli la scheda dalla libreria
    final Scheda? schedaSelezionata = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SelezionaSchedaLibreria()),
    );

    // B. Se l'ha scelta, aprila nell'Editor per poterla modificare!
    if (schedaSelezionata != null && context.mounted) {
      final Scheda? schedaModificata = await Navigator.push(
        context,
        MaterialPageRoute(
          // 👇 QUI IL FIX: Usiamo schedaDaModificare!
          builder: (context) => CreaSchedaScreen(schedaDaModificare: schedaSelezionata),
        ),
      );

      // C. Se l'ha salvata dopo la modifica, chiediamo conferma e inviamo
      if (schedaModificata != null && context.mounted) {
        _confermaEInvia(context, [schedaModificata]);
      }
    }
  }

  // 3. FLUSSO: Con Intelligenza Artificiale 🤖
  Future<void> _importaConAI(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? foto = await picker.pickImage(source: ImageSource.gallery);
    if (foto == null) return;

    if (!context.mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));

    List<Scheda>? schedeImportate = await AiService.analizzaFotoScheda(foto);
    
    if (!context.mounted) return;
    Navigator.pop(context); 

    if (schedeImportate != null && schedeImportate.isNotEmpty) {
      // 👇 QUI IL FIX: Usiamo schedaDaModificare!
      final Scheda? schedaRivista = await Navigator.push(context, MaterialPageRoute(builder: (context) => CreaSchedaScreen(schedaDaModificare: schedeImportate.first)));
      if (schedaRivista != null && context.mounted) _confermaEInvia(context, [schedaRivista]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore o foto poco chiara. Riprova! ❌'), backgroundColor: Colors.red));
    }
  }

  // Funzione finale che spara i dati su Firebase
  Future<void> _salvaSchedaSuFirebase(BuildContext context, List<Scheda> schedeDaSalvare) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)));

    try {
      final String coachId = FirebaseAuth.instance.currentUser!.uid;

      for (var scheda in schedeDaSalvare) {
        Map<String, dynamic> datiScheda = scheda.toJson();
        datiScheda['atletaId'] = atletaId;
        datiScheda['coachId'] = coachId;
        datiScheda['dataAssegnazione'] = DateTime.now().toIso8601String();

        await FirebaseFirestore.instance.collection('schede_assegnate').add(datiScheda);
      }

      if (!context.mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${schedeDaSalvare.length} scheda/e inviata/e con successo! 🚀'), backgroundColor: Colors.green));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore di invio: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Atleta: $atletaEmail', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.document_scanner, color: Colors.purpleAccent), tooltip: 'Scansiona Scheda con IA', onPressed: () => _importaConAI(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('schede_assegnate').where('atletaId', isEqualTo: atletaId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nessuna scheda assegnata. Sparagliene una! 🎯', style: TextStyle(color: Colors.grey, fontSize: 16)));

          final schede = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100), // Spazio per i bottoni in fondo
            itemCount: schede.length,
            itemBuilder: (context, index) {
              final data = schede[index].data() as Map<String, dynamic>;
              final scheda = Scheda.fromJson(data);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.fitness_center, color: Colors.white)),
                  title: Text(scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${scheda.esercizi.length} esercizi • ${scheda.categoria}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: 'Revoca scheda',
                    onPressed: () async => await FirebaseFirestore.instance.collection('schede_assegnate').doc(schede[index].id).delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
      
      // I NUOVI BOTTONI GEMELLI IN FONDO ALLA PAGINA!
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: const Icon(Icons.library_books, color: Colors.lightBlue),
                  label: const Text('Libreria'),
                  onPressed: () => _scegliDaLibreria(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuova'),
                  onPressed: () => _assegnaNuovaScheda(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}