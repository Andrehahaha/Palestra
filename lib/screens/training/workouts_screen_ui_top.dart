part of 'workouts_screen.dart';

extension _WorkoutsScreenUiTop on _WorkoutsScreenState {
  Future<void> _apriStorico(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoricoScreen(
          storico: storico,
          onUpdate: () => _salvaDati(),
        ),
      ),
    );
    _updateState(() {});
  }

  Future<void> _apriPrMode(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const PRModeScreen()),
    );
    await _caricaDati();
  }

  Widget _buildAllenamentiHomeSection(BuildContext context) {
    final totSchede = mieSchede.length;
    final totStorico = storico.length;
    final coachSchede = mieSchede.where((s) => s.categoria == 'Dal Coach 🐯').length;
    final totCategorie = _raggruppaSchedePerCategoria().length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5A240C), Color(0xFF9E3A10)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.deepOrange.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.black26,
                    child: Icon(Icons.fitness_center, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hub Allenamenti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHomeMetricChip('Schede', '$totSchede', Colors.orangeAccent),
                  _buildHomeMetricChip('Categorie', '$totCategorie', Colors.cyanAccent),
                  _buildHomeMetricChip('Coach', '$coachSchede', Colors.lightGreenAccent),
                  _buildHomeMetricChip('Storico', '$totStorico', Colors.amberAccent),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildAllenamentiHomeTile(
          icona: Icons.view_list,
          titolo: 'Le tue schede',
          descrizione: 'Apri categorie, progressioni e gestione completa.',
          gradient: const [Color(0xFF2B3A12), Color(0xFF44651F)],
          accent: Colors.lightGreenAccent,
          onTap: () {
            _updateState(() {
              _sezioneCorrente = _WorkoutsSezione.schede;
            });
          },
        ),
        _buildAllenamentiHomeTile(
          icona: Icons.history,
          titolo: 'Storico allenamenti',
          descrizione: 'Visualizza cronologia e risultati delle sessioni.',
          gradient: const [Color(0xFF0E3B46), Color(0xFF15647A)],
          accent: Colors.lightBlueAccent,
          onTap: () {
            _apriStorico(context);
          },
        ),
        _buildAllenamentiHomeTile(
          icona: Icons.bolt,
          titolo: 'Modalita PR',
          descrizione: 'Calcolo percentuali, tentativi massimali e timer.',
          gradient: const [Color(0xFF4A1E56), Color(0xFF7B2D92)],
          accent: Colors.purpleAccent,
          onTap: () {
            _apriPrMode(context);
          },
        ),
      ],
    );
  }

  Widget _buildAllenamentiHomeTile({
    required IconData icona,
    required String titolo,
    required String descrizione,
    required List<Color> gradient,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(icona, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titolo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descrizione,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeMetricChip(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildAllenamentiHeroPanel(BuildContext context) {
    final totSchede = mieSchede.length;
    final coachSchede = mieSchede.where((s) => s.categoria == 'Dal Coach 🐯').length;
    final totCategorie = _raggruppaSchedePerCategoria().length;
    final now = DateTime.now();
    final todayLabel = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A1B0B), Color(0xFF6D2F12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.whatshot, color: Colors.amberAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Workout Command Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  todayLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Gestione schede, sincronizzazione e storico in un colpo d\'occhio.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildHeroStat(
                label: 'Schede',
                value: '$totSchede',
                accent: Colors.orangeAccent,
                icon: Icons.folder_open_rounded,
              ),
              const SizedBox(width: 8),
              _buildHeroStat(
                label: 'Coach',
                value: '$coachSchede',
                accent: Colors.lightGreenAccent,
                icon: Icons.sports_martial_arts,
              ),
              const SizedBox(width: 8),
              _buildHeroStat(
                label: 'Categorie',
                value: '$totCategorie',
                accent: Colors.cyanAccent,
                icon: Icons.category_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF20A87A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (c) => const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  ),
                );
                await _sincronizzaColCoach(silenzioso: false);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              icon: const Icon(Icons.sync),
              label: const Text(
                'Sincronizza Dal Coach',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat({
    required String label,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.23),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorieSectionLabel(int categorieCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.deepOrangeAccent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Categorie Schede',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2017),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$categorieCount categorie',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.sync, color: Colors.greenAccent),
        onPressed: () async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            ),
          );
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
              builder: (context) => const Center(
                child: CircularProgressIndicator(color: Colors.deepOrange),
              ),
            );
            final schedeImportate = await AiService.analizzaFotoScheda(foto);
            if (!context.mounted || !mounted) return;
            Navigator.pop(context);
            if (schedeImportate != null && schedeImportate.isNotEmpty) {
              _updateState(() {
                mieSchede.addAll(schedeImportate);
              });
              _salvaDati();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${schedeImportate.length} schede importate! 🤖💪'),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Errore durante la scansione. Riprova! ❌'),
                ),
              );
            }
          }
        },
      ),
    ];
  }

  Widget _buildQuickAccessCards(BuildContext context) {
    final totStorico = storico.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildQuickShortcutCard(
              title: 'Modalità PR',
              subtitle: 'Calcolo percentuali',
              icon: Icons.fitness_center,
              gradient: const [Color(0xFF7A2A00), Color(0xFFBF360C)],
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const PRModeScreen()),
                );
                _caricaDati();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildQuickShortcutCard(
              title: 'Cronologia',
              subtitle: '$totStorico sessioni',
              icon: Icons.history_toggle_off,
              gradient: const [Color(0xFF0E4A54), Color(0xFF12707E)],
              onTap: () {
                _apriStorico(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickShortcutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
