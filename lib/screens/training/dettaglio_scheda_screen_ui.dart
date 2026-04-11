part of 'dettaglio_scheda_screen.dart';

extension _DettaglioSchedaScreenUi on _DettaglioSchedaScreenState {
  Widget _buildSoloStretchingSection() {
    final stretching = _eserciziSoloStretching();
    final tagScheda = _tagGruppiScheda();
    final sottotitolo = tagScheda.isEmpty
        ? 'Esercizi dal database master Tiger'
        : 'Filtrati per gruppi muscolari scheda: ${tagScheda.join(', ')}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.self_improvement, color: Colors.lightBlueAccent),
        title: const Text(
          'Sezione informativa • Solo stretching',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(sottotitolo),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (stretching.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Nessun esercizio di stretching disponibile al momento.', style: TextStyle(color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stretching.length,
                itemBuilder: (context, i) {
                  final es = stretching[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.fitness_center, size: 18, color: Colors.lightBlueAccent),
                    title: Text(es['nome'] ?? 'Stretching'),
                    trailing: const Icon(Icons.info_outline, color: Colors.grey, size: 18),
                    onTap: () => _mostraDettagliEsercizio(es),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSchedaHeaderCompatto() {
    final totalExercises = widget.scheda.esercizi.length;
    final totalSeries = widget.scheda.esercizi.fold<int>(
      0,
      (total, e) => total + e.serieAttive.where((s) => s.tipo != 'Avvicinamento').length,
    );
    final completedSeries = widget.scheda.esercizi.fold<int>(
      0,
      (total, e) => total + e.serieAttive.where((s) => s.tipo != 'Avvicinamento' && s.isCompletata).length,
    );
    final completionRatio = totalSeries == 0 ? 0.0 : completedSeries / totalSeries;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_left, color: Colors.lightBlueAccent, size: 20),
                tooltip: 'Settimana precedente',
                onPressed: _vaiSettimanaPrecedente,
              ),
              Expanded(
                child: Text(
                  'Settimana ${widget.scheda.settimanaCorrente}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_right, color: Colors.greenAccent, size: 20),
                tooltip: 'Settimana successiva',
                onPressed: _vaiSettimanaSuccessiva,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$totalExercises esercizi • $completedSeries/$totalSeries serie completate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Gestisci settimane',
                onPressed: _apriGestioneSettimane,
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 16),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Solo incompleti',
                onPressed: () {
                  _updateState(() {
                    _showOnlyIncomplete = !_showOnlyIncomplete;
                  });
                },
                icon: Icon(
                  _showOnlyIncomplete ? Icons.filter_alt : Icons.filter_alt_outlined,
                  color: _showOnlyIncomplete ? Colors.amber : Colors.white54,
                  size: 16,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Modalita compatta',
                onPressed: () {
                  _updateState(() {
                    _compactMode = !_compactMode;
                  });
                },
                icon: Icon(
                  _compactMode ? Icons.view_agenda : Icons.view_stream,
                  color: _compactMode ? Colors.lightBlueAccent : Colors.white54,
                  size: 16,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Calcola dischi',
                onPressed: _apriCalcolatoreDischi,
                icon: const Icon(Icons.calculate, size: 16, color: Colors.white70),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Aggiungi esercizio',
                onPressed: () async {
                  final nuovo = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreaEsercizioScreen()));
                  if (nuovo != null) {
                    _updateState(() {
                      widget.scheda.esercizi.add(nuovo);
                    });
                    _scheduleBozzaSave();
                  }
                },
                icon: const Icon(Icons.add, size: 16, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: completionRatio,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDettaglioSchedaScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scheda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildSchedaHeaderCompatto(),
          _buildSoloStretchingSection(),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.only(bottom: 100),
              onReorder: (int oldIndex, int newIndex) {
                if (_showOnlyIncomplete) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Disattiva il filtro "solo incompleti" per riordinare la scheda.'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                _updateState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final esercizio = widget.scheda.esercizi.removeAt(oldIndex);
                  widget.scheda.esercizi.insert(newIndex, esercizio);
                });
                _scheduleBozzaSave();
              },
              children: [
                for (int i = 0; i < widget.scheda.esercizi.length; i++)
                  if (!_showOnlyIncomplete ||
                      widget.scheda.esercizi[i].serieAttive.any((s) => !s.isCompletata && s.tipo != 'Avvicinamento'))
                    _buildEsercizioItem(widget.scheda.esercizi[i], i),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.flag, color: Colors.white),
        label: const Text('Termina Allenamento', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: () async {
          final noteAllenamentoController = TextEditingController();

          final conferma = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [Icon(Icons.emoji_events, color: Colors.amber, size: 28), SizedBox(width: 10), Text('Ottimo Lavoro!')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Salverai lo storico per te e per il tuo Coach.', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteAllenamentoController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Note a fine sessione (Opzionale)',
                      hintText: 'Es: Ottime sensazioni, stanco sul finale...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.black12,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Si, Salva'),
                ),
              ],
            ),
          );

          if (conferma == true) {
            _salvaAllenamentoIbrido(noteAllenamentoController.text.trim());
          }
        },
      ),
    );
  }

  Widget _buildEsercizioItem(Esercizio esercizio, int index) {
    final tuttoFatto = esercizio.serieAttive.isNotEmpty && esercizio.serieAttive.every((Serie s) => s.isCompletata);
    final isCollapsed = _isExerciseCollapsed(esercizio, index);

    final isSuperSet = esercizio.tecniche.any((t) => t.toLowerCase().contains('super'));
    final prevIsSuperSet = index > 0 && widget.scheda.esercizi[index - 1].tecniche.any((t) => t.toLowerCase().contains('super'));
    final nextIsSuperSet = index < widget.scheda.esercizi.length - 1 && widget.scheda.esercizi[index + 1].tecniche.any((t) => t.toLowerCase().contains('super'));

    final nomeTargetIta = _traduciNome(esercizio.nome).toLowerCase().trim();
    final matchDb = _databaseEsercizi.cast<Map<String, dynamic>?>().firstWhere(
      (e) {
        if (e == null) return false;
        final dbNome = e['nome'].toString().toLowerCase().trim();
        final dbNomeTradotto = _traduciNome(e['nome'].toString()).toLowerCase().trim();
        final targetOriginale = esercizio.nome.toLowerCase().trim();

        return dbNomeTradotto == nomeTargetIta ||
            dbNome == nomeTargetIta ||
            dbNomeTradotto == targetOriginale ||
            dbNome == targetOriginale;
      },
      orElse: () => null,
    );

    return Column(
      key: ValueKey('col_${esercizio.nome}_$index'),
      children: [
        if (isSuperSet && prevIsSuperSet)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 32),
            color: Colors.white.withValues(alpha: 0.05),
          ),
        Dismissible(
          key: ValueKey('dismiss_${esercizio.nome}_$index'),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (direction) {
            _updateState(() {
              widget.scheda.esercizi.removeAt(index);
            });
          },
          onUpdate: (details) {
            if (details.reached) {
              _scheduleBozzaSave();
            }
          },
          child: Card(
            margin: EdgeInsets.only(left: 16, right: 16, top: (isSuperSet && prevIsSuperSet) ? 0 : 8, bottom: (isSuperSet && nextIsSuperSet) ? 0 : 8),
            color: isSuperSet ? const Color(0xFF24202A) : const Color(0xFF1E1E1E),
            elevation: isSuperSet ? 0 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular((isSuperSet && prevIsSuperSet) ? 0 : 16),
                bottom: Radius.circular((isSuperSet && nextIsSuperSet) ? 0 : 16),
              ),
              side: BorderSide.none,
            ),
            child: Padding(
              padding: EdgeInsets.all(_compactMode ? 9.0 : 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.drag_indicator, color: Colors.grey, size: _compactMode ? 18 : 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(esercizio.nome, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _compactMode ? 14 : 16, color: tuttoFatto ? Colors.green : Colors.white))),
                      if (matchDb != null)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill, color: Colors.deepOrange, size: 24),
                          tooltip: 'Dettagli tecnica',
                          onPressed: () => _mostraDettagliEsercizio(matchDb),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.lightBlueAccent, size: 20),
                        onPressed: () async {
                          final mod = await Navigator.push(context, MaterialPageRoute(builder: (c) => CreaEsercizioScreen(esercizioDaModificare: esercizio)));
                          if (mod != null) {
                            _updateState(() => widget.scheda.esercizi[index] = mod);
                            _scheduleBozzaSave();
                          }
                        },
                      ),
                      if (matchDb != null)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                          onSelected: (value) {
                            if (value == 'alt') {
                              _mostraAlternative(esercizio.nome, matchDb['categoria']);
                            }
                            if (value == 'det') {
                              _mostraDettagliEsercizio(matchDb);
                            }
                            if (value == 'sto') {
                              _mostraStoricoEsercizio(esercizio.nome);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'alt', child: Text('Alternative')),
                            PopupMenuItem(value: 'det', child: Text('Dettagli tecnica')),
                            PopupMenuItem(value: 'sto', child: Text('Cronologia esercizio')),
                          ],
                        ),
                      IconButton(
                        icon: Icon(
                          isCollapsed ? Icons.expand_more : Icons.expand_less,
                          color: Colors.white70,
                          size: 20,
                        ),
                        tooltip: isCollapsed ? 'Espandi' : 'Comprimi',
                        onPressed: () => _toggleExerciseCollapsed(esercizio, index),
                      ),
                    ],
                  ),
                  if (!isCollapsed) ...[
                    if (esercizio.tecniche.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: esercizio.tecniche.map((t) {
                          if (t.toLowerCase() == 'classico') return const SizedBox.shrink();

                          final isMono = t.toLowerCase().contains('mono') || t.toLowerCase().contains('unilaterale');
                          final coloreTag = isMono ? Colors.cyanAccent : Colors.deepOrange;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: coloreTag.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: coloreTag.withValues(alpha: 0.5)),
                            ),
                            child: Text(t.toUpperCase(), style: TextStyle(color: coloreTag, fontSize: 9, fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      ),
                    Text('Obiettivo: ${esercizio.ripetizioni} | Rec: ${esercizio.recupero}s', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (esercizio.modalitaIntensita == 'rir')
                      Text(
                        'Intensita: RIR ${esercizio.rirTarget ?? '-'}',
                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Intensita: ${esercizio.percentualeMassimale?.toStringAsFixed(1) ?? '-'}% '
                            'di ${esercizio.massimaleKg?.toStringAsFixed(1) ?? '-'}kg '
                            '(target ${esercizio.caricoTargetKg?.toStringAsFixed(1) ?? '-'}kg)',
                            style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                          ),
                          if (esercizio.massimaleKg == null)
                            TextButton.icon(
                              onPressed: () => _impostaPrPersonale(esercizio),
                              icon: const Icon(Icons.fitness_center, size: 16),
                              label: const Text('Imposta il tuo PR per calcolare i carichi'),
                            ),
                        ],
                      ),
                    if (esercizio.note != null && esercizio.note!.trim().isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          border: const Border(left: BorderSide(color: Colors.amber, width: 3)),
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                        ),
                        child: Text('📝 ${esercizio.note}', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontStyle: FontStyle.italic)),
                      ),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: const [
                          SizedBox(width: 30, child: Text('#', style: TextStyle(color: Colors.white38, fontSize: 11))),
                          Expanded(flex: 3, child: Text('Kg', style: TextStyle(color: Colors.white38, fontSize: 11))),
                          Expanded(flex: 3, child: Text('Reps', style: TextStyle(color: Colors.white38, fontSize: 11))),
                          Expanded(flex: 2, child: Text('RPE / %', style: TextStyle(color: Colors.white38, fontSize: 11))),
                          SizedBox(width: 42),
                        ],
                      ),
                    ),
                    ...esercizio.serieAttive.asMap().entries.map((entry) {
                      final sIdx = entry.key;
                      final serie = entry.value;
                      final prev = _getDatiPrecedenti(esercizio.nome, sIdx);
                      final expectedKg = _expectedKgForSerie(esercizio, serie);
                      final expectedPerc = _parsePercentInput(serie.percentualeTarget) ?? esercizio.percentualeMassimale;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: serie.isCompletata ? Colors.green.withValues(alpha: 0.1) : Colors.black12, borderRadius: BorderRadius.circular(6)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 30, child: Text('${sIdx + 1}º', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    key: ValueKey('peso_${esercizio.nome}_$sIdx'),
                                    initialValue: serie.peso,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: expectedKg != null ? '${expectedKg.toStringAsFixed(1)}kg' : (prev != null ? '${prev['peso']}kg' : 'Kg'),
                                      border: InputBorder.none,
                                      isDense: true,
                                      hintStyle: TextStyle(color: Colors.grey.shade500),
                                    ),
                                    onChanged: (v) {
                                      serie.peso = v;
                                      _scheduleBozzaSave();
                                    },
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    key: ValueKey('reps_${esercizio.nome}_$sIdx'),
                                    initialValue: serie.ripetizioniFatte,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: prev != null ? '${prev['reps']}r' : 'Reps',
                                      border: InputBorder.none,
                                      isDense: true,
                                      hintStyle: TextStyle(color: Colors.grey.shade500),
                                    ),
                                    onChanged: (v) {
                                      serie.ripetizioniFatte = v;
                                      _scheduleBozzaSave();
                                    },
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    key: ValueKey('int_${esercizio.nome}_$sIdx'),
                                    initialValue: esercizio.modalitaIntensita == 'percentuale' ? serie.percentualeTarget : serie.rpe,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: esercizio.modalitaIntensita == 'percentuale' && serie.tipo != 'Avvicinamento'
                                          ? '% ${serie.percentualeTarget.isNotEmpty ? serie.percentualeTarget : (esercizio.percentualeMassimale?.toStringAsFixed(1) ?? '-')}'
                                          : (prev != null && prev['rpe'] != null ? 'RPE ${prev['rpe']}' : 'RPE'),
                                      border: InputBorder.none,
                                      isDense: true,
                                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                    ),
                                    style: const TextStyle(color: Colors.amber, fontSize: 14),
                                    onChanged: (v) {
                                      if (esercizio.modalitaIntensita == 'percentuale') {
                                        final rm = esercizio.massimaleKg;
                                        final oldPerc = _parsePercentInput(serie.percentualeTarget) ?? esercizio.percentualeMassimale;
                                        final oldExpected = (rm != null && rm > 0 && oldPerc != null && oldPerc > 0 && serie.tipo != 'Avvicinamento')
                                            ? WorkloadCalculator.calculateFromMaxAndPercentage(oneRepMax: rm, percentage: oldPerc)
                                            : null;

                                        final parsed = _parsePercentInput(v);
                                        serie.percentualeTarget = parsed != null
                                            ? parsed.toStringAsFixed(parsed % 1 == 0 ? 0 : 1)
                                            : v.replaceAll('%', '').trim();

                                        if (rm != null && rm > 0 && parsed != null && parsed > 0 && serie.tipo != 'Avvicinamento') {
                                          final newExpected = WorkloadCalculator.calculateFromMaxAndPercentage(
                                            oneRepMax: rm,
                                            percentage: parsed,
                                          );
                                          final currentPeso = _toDoubleOrNull(serie.peso);
                                          final shouldAutoUpdatePeso =
                                              serie.peso.trim().isEmpty || (oldExpected != null && currentPeso != null && _isAlmostEqual(currentPeso, oldExpected));

                                          if (shouldAutoUpdatePeso) {
                                            serie.peso = newExpected.toStringAsFixed(1);
                                          }
                                        }
                                      } else {
                                        serie.rpe = v;
                                      }
                                      _scheduleBozzaSave();
                                      _updateState(() {});
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(serie.isCompletata ? Icons.check_box : Icons.check_box_outline_blank, color: serie.isCompletata ? Colors.green : Colors.grey, size: 22),
                                  onPressed: () async {
                                    _updateState(() {
                                      serie.isCompletata = !serie.isCompletata;
                                    });
                                    _scheduleBozzaSave();
                                    if (await Vibration.hasVibrator() == true) {
                                      Vibration.vibrate(duration: 50, amplitude: 100);
                                    }
                                    if (serie.isCompletata) {
                                      _avviaTimerRecupero(_estraiSecondi(esercizio.recupero));
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (expectedKg != null && serie.tipo != 'Avvicinamento')
                              Padding(
                                padding: const EdgeInsets.only(left: 32, top: 2, bottom: 2),
                                child: Text(
                                  'Expected: ${expectedKg.toStringAsFixed(1)} kg @ ${expectedPerc?.toStringAsFixed(expectedPerc % 1 == 0 ? 0 : 1) ?? '-'}%',
                                  style: TextStyle(color: Colors.lightBlueAccent.withValues(alpha: 0.9), fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        'Card compatta: tocca per espandere serie e dettagli',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
