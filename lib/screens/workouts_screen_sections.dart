/*
Legacy placeholder.
The active implementation lives in:
lib/screens/training/workouts_screen_sections.dart

part of 'workouts_screen.dart';

extension _WorkoutsScreenSections on _WorkoutsScreenState {
  Future<void> _apriSettimanaSuccessiva(Scheda scheda) async {
    final aggiornata = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettimanaSuccessivaScreen(scheda: scheda)),
    );

    if (aggiornata is Scheda && mounted) {
      _updateState(() {});
      await _salvaDati();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Progressione applicata alla settimana ${aggiornata.settimanaCorrente}.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Map<String, List<Scheda>> _raggruppaSchedePerCategoria() {
    final Map<String, List<Scheda>> schedeRaggruppate = {};
    for (var scheda in mieSchede) {
      schedeRaggruppate.putIfAbsent(scheda.categoria, () => []).add(scheda);
    }
    for (var cartella in cartelleVuote) {
      schedeRaggruppate.putIfAbsent(cartella, () => []);
    }
    return schedeRaggruppate;
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.sync, color: Colors.greenAccent),
        onPressed: () async {
          showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
          await _sincronizzaColCoach(silenzioso: false);
          if (!context.mounted) return;
          Navigator.pop(context);
        },
      ),
      IconButton(
        icon: const Icon(Icons.document_scanner, color: Colors.blueAccent),
        onPressed: () async {
          final picker = ImagePicker();
          final XFile? foto = await picker.pickImage(source: ImageSource.gallery);
          if (!context.mounted) return;
          if (foto != null) {
            if (!mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
            );
            List<Scheda>? schedeImportate = await AiService.analizzaFotoScheda(foto);
            if (!context.mounted || !mounted) return;
            Navigator.pop(context);
            if (schedeImportate != null && schedeImportate.isNotEmpty) {
              _updateState(() {
                mieSchede.addAll(schedeImportate);
              });
              _salvaDati();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${schedeImportate.length} schede importate! 🤖💪')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore durante la scansione. Riprova! ❌')));
            }
          }
        },
      ),
      IconButton(
        icon: const Icon(Icons.history),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => StoricoScreen(storico: storico, onUpdate: () => _salvaDati())),
          ).then((_) {
            _updateState(() {});
          });
        },
      ),
    ];
  }

  Widget _buildQuickAccessCards(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (c) => const PRModeScreen()));
              _caricaDati();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.deepOrange, Colors.redAccent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.fitness_center, color: Colors.white, size: 36),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MODALITÀ PR', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        Text('Calcola % e carica il bilanciere', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorieList(BuildContext context, Map<String, List<Scheda>> schedeRaggruppate, List<String> categorie) {
    if (categorie.isEmpty) {
      return const Center(child: Text('Nessuna scheda. Premi + o chiedi al tuo Coach!', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: categorie.length,
      itemBuilder: (context, index) {
        final nomeCategoria = categorie[index];
        final schedeDiQuestaCategoria = schedeRaggruppate[nomeCategoria]!;

        return DragTarget<Scheda>(
          onWillAcceptWithDetails: (details) => details.data.categoria != nomeCategoria,
          onAcceptWithDetails: (details) {
            _updateState(() {
              details.data.categoria = nomeCategoria;
              cartelleVuote.remove(nomeCategoria);
            });
            _salvaDati();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scheda spostata in "$nomeCategoria"! 📂'), backgroundColor: Colors.green),
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
              decoration: BoxDecoration(
                color: isHovering ? Colors.deepOrange.withValues(alpha: 0.1) : Colors.transparent,
                border: isHovering ? Border.all(color: Colors.deepOrange, width: 2) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: Icon(
                  nomeCategoria == 'Dal Coach 🐯' ? Icons.local_fire_department : Icons.folder,
                  color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        nomeCategoria,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: nomeCategoria == 'Dal Coach 🐯' ? Colors.greenAccent : Colors.deepOrange,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, size: 22, color: Colors.redAccent),
                      onPressed: () => _esportaCartellaInPDF(nomeCategoria, schedeDiQuestaCategoria),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, size: 22, color: Colors.purpleAccent),
                      onPressed: () => _mostraAnalisiCartella(context, nomeCategoria, schedeDiQuestaCategoria),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                      onPressed: () => _rinominaCategoria(nomeCategoria),
                    ),
                    if (schedeDiQuestaCategoria.isEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        tooltip: 'Elimina cartella vuota',
                        onPressed: () => _eliminaCartellaVuota(nomeCategoria),
                      ),
                  ],
                ),
                children: schedeDiQuestaCategoria.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text('Cartella vuota', style: TextStyle(color: Colors.grey)),
                        ),
                      ]
                    : schedeDiQuestaCategoria.map((scheda) => _buildSchedaCard(context, scheda)).toList(),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostraAnalisiCartella(BuildContext context, String nomeCategoria, List<Scheda> schedeDiQuestaCategoria) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),
    );
    String? recensione = await AiService.valutaCartella(nomeCategoria, schedeDiQuestaCategoria);
    if (!context.mounted) return;
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 28),
                SizedBox(width: 8),
                Text('Analisi del Coach AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SingleChildScrollView(
                child: Text(recensione ?? 'Errore.', style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Ho capito, grazie Coach!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedaCard(BuildContext context, Scheda scheda) {
    final indiceReale = mieSchede.indexOf(scheda);
    final cardScheda = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.list_alt)),
        title: Text(scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${scheda.esercizi.length} esercizi • ${scheda.livello} • W${scheda.settimanaCorrente}\n'
          '${scheda.continuativa ? 'Continuativa' : 'Non continuativa'} • (Tieni premuto per spostare)',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_next, size: 20, color: Colors.greenAccent),
              tooltip: 'Settimana successiva',
              onPressed: () => _apriSettimanaSuccessiva(scheda),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: Colors.orangeAccent),
              tooltip: 'Rinomina scheda',
              onPressed: () => _rinominaScheda(scheda),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20, color: Colors.lightBlueAccent),
              tooltip: 'Duplica questa scheda',
              onPressed: () => _duplicaScheda(scheda),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () async {
          final completato = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DettaglioSchedaScreen(scheda: scheda, storico: storico)),
          );
          if (completato == true) {
            final copiaScheda = Scheda.fromJson(scheda.toJson());
            final nuovoAllenamento = Allenamento(data: DateTime.now(), scheda: copiaScheda);
            storico.add(nuovoAllenamento);
            _inviaAllenamentoAlCloud(nuovoAllenamento);
            for (var es in scheda.esercizi) {
              for (var s in es.serieAttive) {
                s.isCompletata = false;
              }
            }
          }
          _updateState(() {});
          _salvaDati();
        },
      ),
    );

    return LongPressDraggable<Scheda>(
      data: scheda,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: SizedBox(width: MediaQuery.of(context).size.width, child: Opacity(opacity: 0.8, child: cardScheda)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cardScheda),
      child: Dismissible(
        key: UniqueKey(),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete, color: Colors.white, size: 30),
        ),
        confirmDismiss: (direction) async {
          return _confermaEliminazioneCloud('la scheda "${scheda.nome}"');
        },
        onDismissed: (direction) {
          String nomeDaEliminare = mieSchede[indiceReale].nome;
          _updateState(() {
            mieSchede.removeAt(indiceReale);
          });
          _salvaDati();
          _eliminaSchedaDalCloud(nomeDaEliminare);
        },
        child: cardScheda,
      ),
    );
  }
}
*/
