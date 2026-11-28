import 'package:flutter/material.dart';

import '../services/correzioni_nomi.dart';

/// Dopo un import: i nomi cambiati rispetto al documento o senza foto nel
/// database. Ognuno si può correggere scegliendo dal database o tenendo il
/// nome del documento. Restituisce "nome nel documento" -> "nome scelto".
class RevisioneNomiScreen extends StatefulWidget {
  const RevisioneNomiScreen({super.key, required this.voci, required this.database});

  final List<VoceNome> voci;
  final List<String> database;

  @override
  State<RevisioneNomiScreen> createState() => _RevisioneNomiScreenState();
}

class _RevisioneNomiScreenState extends State<RevisioneNomiScreen> {
  late final Map<String, String> _scelte = {for (final v in widget.voci) v.originale: v.scelto};
  late final Set<String> _nelDatabase = widget.database.toSet();

  Future<void> _scegli(VoceNome voce) async {
    final scelto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (_) => _SceltaNome(originale: voce.originale, database: widget.database),
    );
    if (scelto != null) setState(() => _scelte[voce.originale] = scelto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controlla i nomi')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Questi nomi sono stati cambiati rispetto al documento o non hanno foto nel database. '
              'Tocca un nome per correggerlo: la scelta viene ricordata per i prossimi import.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          for (final voce in widget.voci)
            ListTile(
              leading: _nelDatabase.contains(_scelte[voce.originale])
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.help_outline, color: Colors.amber),
              title: Text(_scelte[voce.originale]!),
              subtitle: Text('Nel documento: ${voce.originale}'),
              trailing: const Icon(Icons.edit),
              onTap: () => _scegli(voce),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check),
            label: const Text('Conferma nomi'),
            onPressed: () => Navigator.pop(context, Map<String, String>.of(_scelte)),
          ),
        ),
      ),
    );
  }
}

class _SceltaNome extends StatefulWidget {
  const _SceltaNome({required this.originale, required this.database});

  final String originale;
  final List<String> database;

  @override
  State<_SceltaNome> createState() => _SceltaNomeState();
}

class _SceltaNomeState extends State<_SceltaNome> {
  late String _ricerca = widget.originale;

  List<String> get _trovati {
    final parole = _ricerca.toLowerCase().split(RegExp(r'\s+')).where((p) => p.length > 2).toList();
    if (parole.isEmpty) return widget.database.take(50).toList();
    final punteggi = {
      for (final n in widget.database) n: parole.where((p) => n.toLowerCase().contains(p)).length,
    };
    final trovati = widget.database.where((n) => punteggi[n]! > 0).toList()
      ..sort((a, b) => punteggi[b]!.compareTo(punteggi[a]!));
    return trovati.take(50).toList();
  }

  @override
  Widget build(BuildContext context) {
    final trovati = _trovati;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                initialValue: widget.originale,
                decoration: const InputDecoration(labelText: 'Cerca nel database', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _ricerca = v),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('Tieni "${widget.originale}"'),
              subtitle: const Text('Nome del documento, senza foto'),
              onTap: () => Navigator.pop(context, widget.originale),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final n in trovati)
                    ListTile(title: Text(n), onTap: () => Navigator.pop(context, n)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
