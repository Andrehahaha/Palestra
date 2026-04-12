part of 'workouts_screen.dart';

extension _WorkoutsScreenActions on _WorkoutsScreenState {
  Future<void> _creaCartellaVuota() async {
    final controller = TextEditingController();
    final String? nomeCartella = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuova cartella vuota'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome cartella',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crea'),
          ),
        ],
      ),
    );

    final nome = nomeCartella?.trim() ?? '';
    if (nome.isEmpty || !mounted) return;

    final esisteGia =
        cartelleVuote.contains(nome) ||
        mieSchede.any((s) => s.categoria == nome);
    if (esisteGia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esiste già una cartella con questo nome.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _updateState(() {
      cartelleVuote.add(nome);
    });
    await _salvaDati();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cartella vuota creata ✅'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<bool> _confermaEliminazioneCloud(String target) async {
    final bool? conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione cloud'),
        content: Text('Vuoi eliminare $target anche sul cloud?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sì, elimina'),
          ),
        ],
      ),
    );

    return conferma == true;
  }

  // Backward-compatible helper used by legacy sections UI.
  Future<void> _eliminaCartellaVuota(String nomeCategoria) async {
    await _eliminaCartellaConContenuto(nomeCategoria, const <Scheda>[]);
  }

  Future<bool> _confermaEliminazioneCartellaCompleta(
    String nomeCategoria,
    int schedeCount,
  ) async {
    final bool? conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina cartella'),
        content: Text(
          schedeCount > 0
              ? 'Eliminare la cartella "$nomeCategoria" e tutte le sue $schedeCount schede? Questa azione e irreversibile.'
              : 'Eliminare la cartella vuota "$nomeCategoria"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina tutto'),
          ),
        ],
      ),
    );

    return conferma == true;
  }

  Future<void> _eliminaCartellaConContenuto(
    String nomeCategoria,
    List<Scheda> schedeDiQuestaCategoria,
  ) async {
    final schedeCount = schedeDiQuestaCategoria.length;
    final conferma = await _confermaEliminazioneCartellaCompleta(
      nomeCategoria,
      schedeCount,
    );
    if (!conferma || !mounted) return;

    final nomiDaEliminareCloud = mieSchede
        .where((s) => s.categoria == nomeCategoria)
        .map((s) => s.nome)
        .toSet()
        .toList();

    _updateState(() {
      mieSchede.removeWhere((s) => s.categoria == nomeCategoria);
      cartelleVuote.remove(nomeCategoria);
    });

    await _salvaDati();

    for (final nomeScheda in nomiDaEliminareCloud) {
      await _eliminaSchedaDalCloud(nomeScheda);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          schedeCount > 0
              ? 'Cartella eliminata con $schedeCount schede 🗑️'
              : 'Cartella vuota eliminata 🗑️',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _creaSchedaCompleta() async {
    final nuovaScheda = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreaSchedaScreen()),
    );
    if (nuovaScheda != null && nuovaScheda is Scheda) {
      _updateState(() {
        mieSchede.add(nuovaScheda);
      });
      _salvaDati();
    }
  }

  Future<void> _creaSchedaSingola() async {
    final Esercizio? esercizio = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreaEsercizioScreen()),
    );

    if (esercizio == null || !mounted) return;

    final nomeController = TextEditingController(
      text: 'Scheda ${esercizio.nome}',
    );
    final categoriaController = TextEditingController(text: 'Generale');
    String livelloSelezionato = 'Principiante';

    final bool? conferma = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crea scheda singola'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome scheda',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoriaController,
                decoration: const InputDecoration(
                  labelText: 'Categoria / Cartella',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: livelloSelezionato,
                decoration: const InputDecoration(
                  labelText: 'Livello',
                  border: OutlineInputBorder(),
                ),
                items: ['Principiante', 'Intermedio', 'Avanzato']
                    .map(
                      (livello) => DropdownMenuItem(
                        value: livello,
                        child: Text(livello),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setDialogState(() => livelloSelezionato = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );

    final nomeScheda = nomeController.text.trim();
    final categoria = categoriaController.text.trim();
    nomeController.dispose();
    categoriaController.dispose();

    if (conferma != true || nomeScheda.isEmpty || !mounted) return;

    final nuovaScheda = Scheda(
      nome: nomeScheda,
      livello: livelloSelezionato,
      categoria: categoria.isEmpty ? 'Generale' : categoria,
      esercizi: [esercizio],
    );

    _updateState(() {
      mieSchede.add(nuovaScheda);
    });
    _salvaDati();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scheda singola creata! ✅'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _apriMenuCreazione() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_list, color: Colors.deepOrange),
              title: const Text('Nuovo workout completo'),
              subtitle: const Text('Crea una scheda con più esercizi'),
              onTap: () {
                Navigator.pop(context);
                _creaSchedaCompleta();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.note_add,
                color: Colors.lightBlueAccent,
              ),
              title: const Text('Nuova scheda singola'),
              subtitle: const Text('Crea una scheda con un solo esercizio'),
              onTap: () {
                Navigator.pop(context);
                _creaSchedaSingola();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder, color: Colors.amber),
              title: const Text('Nuova cartella vuota'),
              subtitle: const Text('Crea una cartella senza schede'),
              onTap: () {
                Navigator.pop(context);
                _creaCartellaVuota();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _duplicaScheda(Scheda schedaOriginale) {
    final Map<String, dynamic> jsonCopia = schedaOriginale.toJson();
    jsonCopia['nome'] = '${schedaOriginale.nome} (Copia)';

    final Scheda nuovaScheda = Scheda.fromJson(jsonCopia);

    _updateState(() {
      mieSchede.add(nuovaScheda);
    });

    _salvaDati();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scheda duplicata con successo! 📄🔄'),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _rinominaScheda(Scheda scheda) async {
    TextEditingController controller = TextEditingController(text: scheda.nome);
    String? nuovoNome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Rinomina Scheda',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Nuovo nome...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != scheda.nome) {
      if (!context.mounted || !mounted) return;
      _updateState(() {
        scheda.nome = nuovoNome;
      });
      _salvaDati();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nome aggiornato! ✏️'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _rinominaCategoria(String vecchioNome) async {
    TextEditingController controller = TextEditingController(text: vecchioNome);
    String? nuovoNome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Rinomina Cartella',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Es: Settimana 1...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (nuovoNome != null && nuovoNome.isNotEmpty && nuovoNome != vecchioNome) {
      _updateState(() {
        for (var scheda in mieSchede) {
          if (scheda.categoria == vecchioNome) scheda.categoria = nuovoNome;
        }
      });
      _salvaDati();
    }
  }

  Future<void> _esportaCartellaInPDF(
    String nomeCategoria,
    List<Scheda> schede,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      ),
    );
    try {
      final pdf = pw.Document();
      final purpleColor = PdfColor.fromHex('#9C27B0');
      final greyText = PdfColor.fromHex('#757575');
      final dividerColor = PdfColor.fromHex('#E0E0E0');

      for (var scheda in schede) {
        pdf.addPage(
          pw.MultiPage(
            maxPages: 100,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
            build: (pw.Context context) {
              List<pw.Widget> foglio = [];
              foglio.add(
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      scheda.nome.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      nomeCategoria,
                      style: pw.TextStyle(fontSize: 12, color: greyText),
                    ),
                  ],
                ),
              );
              foglio.add(pw.Divider(thickness: 1, color: dividerColor));

              if (scheda.livello.isNotEmpty) {
                foglio.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 20, top: 4),
                    child: pw.Text(
                      'Livello: ${scheda.livello}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontStyle: pw.FontStyle.italic,
                        color: greyText,
                      ),
                    ),
                  ),
                );
              } else {
                foglio.add(pw.SizedBox(height: 20));
              }

              for (int i = 0; i < scheda.esercizi.length; i++) {
                var es = scheda.esercizi[i];
                int numAvvicinamento = es.serieAttive
                    .where((s) => s.tipo == 'Avvicinamento')
                    .length;
                int numWorking = es.serieAttive
                    .where((s) => s.tipo != 'Avvicinamento')
                    .length;
                if (numWorking == 0) numWorking = es.serieAttive.length;

                bool isSuperSet = es.tecniche.any(
                  (t) => t.toLowerCase().contains('super'),
                );
                bool prevIsSuperSet =
                    i > 0 &&
                    scheda.esercizi[i - 1].tecniche.any(
                      (t) => t.toLowerCase().contains('super'),
                    );
                var altreTecniche = es.tecniche
                    .where((t) => !t.toLowerCase().contains('super'))
                    .toList();

                if (isSuperSet && !prevIsSuperSet) {
                  foglio.add(
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8, bottom: 8),
                      child: pw.Text(
                        '>>> INIZIO SUPERSET',
                        style: pw.TextStyle(
                          color: purpleColor,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  );
                }

                foglio.add(
                  pw.Padding(
                    padding: pw.EdgeInsets.only(
                      left: isSuperSet ? 20 : 0,
                      bottom: 16,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              '- ${es.nome}',
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(width: 10),
                            pw.Text(
                              '$numWorking set  |  ${es.ripetizioni} reps  |  Rec: ${es.recupero}s',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        if (numAvvicinamento > 0 ||
                            altreTecniche.isNotEmpty ||
                            (es.note != null && es.note!.isNotEmpty))
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 12, top: 4),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                if (numAvvicinamento > 0)
                                  pw.Text(
                                    'Avvicinamento: $numAvvicinamento set',
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      color: greyText,
                                    ),
                                  ),
                                if (altreTecniche.isNotEmpty)
                                  pw.Text(
                                    'Tecniche: ${altreTecniche.join(", ")}',
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      color: greyText,
                                    ),
                                  ),
                                if (es.note != null && es.note!.isNotEmpty)
                                  pw.Text(
                                    'Note: ${es.note}',
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      fontStyle: pw.FontStyle.italic,
                                      color: greyText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        pw.SizedBox(height: 8),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 12),
                          child: pw.Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: List.generate(
                              numWorking,
                              (idx) => pw.Text(
                                'Set ${idx + 1}:  ____ kg  x  ____',
                                style: const pw.TextStyle(
                                  fontSize: 11,
                                  color: PdfColors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return foglio;
            },
          ),
        );
      }
      final directory = await getTemporaryDirectory();
      String nomeFile = nomeCategoria.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${directory.path}/$nomeFile.pdf');
      await file.writeAsBytes(await pdf.save());
      if (!mounted) return;
      Navigator.pop(context);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Ecco le tue schede per il blocco: $nomeCategoria 💪',
          subject: 'Schede Allenamento Tiger',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore creazione PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
