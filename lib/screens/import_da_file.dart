import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/scheda.dart';
import '../services/ai_service.dart';
import 'crea_scheda.dart';

/// Fa scegliere un file (foto, PDF, Word) e lo manda all'import AI.
/// `null` se l'utente annulla la scelta.
Future<EsitoAi<List<Scheda>>?> importaSchedaDaFile(BuildContext context) async {
  final scelta = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: AiService.estensioniSupportate,
    withData: true,
  );
  final file = scelta?.files.single;
  if (file == null || file.bytes == null || !context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
  );
  final esito = await AiService.instance.analizzaFile(nomeFile: file.name, bytes: file.bytes!);
  if (context.mounted) Navigator.pop(context);
  return esito;
}

/// Revisione lato coach dei giorni importati prima dell'invio.
/// Restituisce con `Navigator.pop` la lista da inviare.
class RevisioneSchedeImportateScreen extends StatefulWidget {
  const RevisioneSchedeImportateScreen({super.key, required this.schede});

  final List<Scheda> schede;

  @override
  State<RevisioneSchedeImportateScreen> createState() => _RevisioneSchedeImportateScreenState();
}

class _RevisioneSchedeImportateScreenState extends State<RevisioneSchedeImportateScreen> {
  late final List<Scheda> _schede = List.of(widget.schede);

  Future<void> _modifica(int i) async {
    final rivista = await Navigator.push<Scheda>(
      context,
      MaterialPageRoute(builder: (_) => CreaSchedaScreen(schedaDaModificare: _schede[i])),
    );
    if (rivista != null) setState(() => _schede[i] = rivista);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schede importate')),
      body: ListView.builder(
        itemCount: _schede.length,
        itemBuilder: (context, i) {
          final s = _schede[i];
          final settimane = s.programma?.length ?? 0;
          return ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(s.nome),
            subtitle: Text(
              '${s.esercizi.length} esercizi'
              '${settimane > 0 ? ' • $settimane settimane nel piano' : ''}',
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => _modifica(i),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send),
            label: Text('Invia tutti (${_schede.length})'),
            onPressed: () => Navigator.pop(context, _schede),
          ),
        ),
      ),
    );
  }
}
