part of 'workouts_screen.dart';

extension _WorkoutsScreenUiCategories on _WorkoutsScreenState {
  Future<void> _apriSettimanaSuccessiva(Scheda scheda) async {
    final aggiornata = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettimanaSuccessivaScreen(scheda: scheda),
      ),
    );

    if (aggiornata is Scheda && mounted) {
      _updateState(() {});
      await _salvaDati();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Progressione applicata alla settimana ${aggiornata.settimanaCorrente}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Map<String, List<Scheda>> _raggruppaSchedePerCategoria() {
    final schedeRaggruppate = <String, List<Scheda>>{};
    for (final scheda in mieSchede) {
      schedeRaggruppate.putIfAbsent(scheda.categoria, () => []).add(scheda);
    }
    for (final cartella in cartelleVuote) {
      schedeRaggruppate.putIfAbsent(cartella, () => []);
    }
    return schedeRaggruppate;
  }

  Widget _buildCategorieList(
    BuildContext context,
    Map<String, List<Scheda>> schedeRaggruppate,
    List<String> categorie,
  ) {
    if (categorie.isEmpty) {
      return const Center(
        child: Text(
          'Nessuna scheda. Premi + o chiedi al tuo Coach!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: categorie.length,
      itemBuilder: (context, index) {
        final nomeCategoria = categorie[index];
        final schedeDiQuestaCategoria = schedeRaggruppate[nomeCategoria]!;
        final isCoachCategory = nomeCategoria == 'Dal Coach 🐯';
        final accent = isCoachCategory
            ? const Color(0xFF57E0B3)
            : const Color(0xFFFF9448);
        final panelGradient = isCoachCategory
            ? const [Color(0xFF112C25), Color(0xFF0E1F1B)]
            : const [Color(0xFF2D2017), Color(0xFF1A1410)];

        return DragTarget<Scheda>(
          onWillAcceptWithDetails: (details) =>
              details.data.categoria != nomeCategoria,
          onAcceptWithDetails: (details) {
            _updateState(() {
              details.data.categoria = nomeCategoria;
              cartelleVuote.remove(nomeCategoria);
            });
            _salvaDati();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Scheda spostata in "$nomeCategoria"! 📂'),
                backgroundColor: Colors.green,
              ),
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: panelGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: isHovering
                      ? accent.withValues(alpha: 0.95)
                      : accent.withValues(alpha: 0.4),
                  width: isHovering ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  collapsedIconColor: accent,
                  iconColor: accent,
                  tilePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: Icon(
                      isCoachCategory
                          ? Icons.local_fire_department
                          : Icons.folder,
                      color: accent,
                      size: 19,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          nomeCategoria,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: accent.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '${schedeDiQuestaCategoria.length}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.picture_as_pdf,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        splashRadius: 18,
                        onPressed: () => _esportaCartellaInPDF(
                          nomeCategoria,
                          schedeDiQuestaCategoria,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: Colors.amberAccent,
                        ),
                        splashRadius: 18,
                        onPressed: () => _mostraAnalisiCartella(
                          context,
                          nomeCategoria,
                          schedeDiQuestaCategoria,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.white60,
                        ),
                        splashRadius: 18,
                        onPressed: () => _rinominaCategoria(nomeCategoria),
                      ),
                      if (schedeDiQuestaCategoria.isEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          splashRadius: 18,
                          tooltip: 'Elimina cartella vuota',
                          onPressed: () => _eliminaCartellaVuota(nomeCategoria),
                        ),
                    ],
                  ),
                  children: schedeDiQuestaCategoria.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              'Cartella vuota',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ),
                        ]
                      : schedeDiQuestaCategoria
                          .map((scheda) => _buildSchedaCard(context, scheda))
                          .toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostraAnalisiCartella(
    BuildContext context,
    String nomeCategoria,
    List<Scheda> schedeDiQuestaCategoria,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: CircularProgressIndicator(color: Colors.purpleAccent),
      ),
    );
    final recensione = await AiService.valutaCartella(
      nomeCategoria,
      schedeDiQuestaCategoria,
    );
    if (!context.mounted) return;
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                Text(
                  'Analisi del Coach AI',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.purpleAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Text(
                  recensione ?? 'Errore.',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: Colors.white,
                  ),
                ),
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
              child: const Text(
                'Ho capito, grazie Coach!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedaCard(BuildContext context, Scheda scheda) {
    final indiceReale = mieSchede.indexOf(scheda);
    final isCoachScheda = scheda.categoria == 'Dal Coach 🐯';
    final accent = isCoachScheda
        ? const Color(0xFF57E0B3)
        : const Color(0xFFFF9448);

    final cardScheda = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: const Color(0xFF1F1F1F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onSchedaTap(context, scheda),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Icon(
                  isCoachScheda ? Icons.local_fire_department : Icons.list_alt,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            scheda.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            'W${scheda.settimanaCorrente}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scheda.esercizi.length} esercizi • ${scheda.livello}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      scheda.continuativa ? 'Continuativa' : 'Non continuativa',
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.9),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next,
                      size: 20,
                      color: Colors.greenAccent,
                    ),
                    tooltip: 'Settimana successiva',
                    onPressed: () => _apriSettimanaSuccessiva(scheda),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit,
                      size: 20,
                      color: Colors.orangeAccent,
                    ),
                    tooltip: 'Rinomina scheda',
                    onPressed: () => _rinominaScheda(scheda),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      size: 20,
                      color: Colors.lightBlueAccent,
                    ),
                    tooltip: 'Duplica questa scheda',
                    onPressed: () => _duplicaScheda(scheda),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<Scheda>(
      data: scheda,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Opacity(opacity: 0.8, child: cardScheda),
        ),
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
          final nomeDaEliminare = mieSchede[indiceReale].nome;
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

  Future<void> _onSchedaTap(BuildContext context, Scheda scheda) async {
    final completato = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DettaglioSchedaScreen(scheda: scheda, storico: storico),
      ),
    );
    if (completato == true) {
      final copiaScheda = Scheda.fromJson(scheda.toJson());
      final nuovoAllenamento = Allenamento(data: DateTime.now(), scheda: copiaScheda);
      storico.add(nuovoAllenamento);
      _inviaAllenamentoAlCloud(nuovoAllenamento);
      for (final es in scheda.esercizi) {
        for (final s in es.serieAttive) {
          s.isCompletata = false;
        }
      }
    }
    _updateState(() {});
    _salvaDati();
  }
}
