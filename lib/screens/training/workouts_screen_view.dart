part of 'workouts_screen.dart';

extension _WorkoutsScreenView on _WorkoutsScreenState {
  Widget _buildWorkoutsScreen(BuildContext context) {
    final schedeRaggruppate = _raggruppaSchedePerCategoria();
    final categorie = schedeRaggruppate.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le tue Schede'),
        actions: _buildAppBarActions(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildQuickAccessCards(context),
                Expanded(
                  child: _buildCategorieList(
                    context,
                    schedeRaggruppate,
                    categorie,
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _apriMenuCreazione,
        child: const Icon(Icons.add),
      ),
    );
  }

  List<_WorkoutAllenamentoData> _buildAllenamentiGerarchia(Scheda scheda) {
    final groupedSedute = _groupExercisesBySeduta(scheda);

    final allWeekNumbers = scheda.eserciziPerSettimana.keys.toList()..sort();
    final weekNumbers = allWeekNumbers.isNotEmpty
        ? allWeekNumbers
        : [scheda.settimanaCorrente > 0 ? scheda.settimanaCorrente : 1];
    final days = <_WorkoutDayData>[];

    for (final seduta in groupedSedute.entries) {
      final weeks = weekNumbers
          .map(
            (wn) => _WorkoutWeekData(
              label: 'Settimana $wn',
              exercises: seduta.value,
              weekNumber: wn,
            ),
          )
          .toList();

      days.add(_WorkoutDayData(title: seduta.key, weeks: weeks));
    }

    if (days.isEmpty) {
      days.add(
        _WorkoutDayData(
          title: scheda.nome,
          weeks: weekNumbers
              .map(
                (wn) => _WorkoutWeekData(
                  label: 'Settimana $wn',
                  exercises: const ['Corpo libero 3x12', 'Plank 3x45"'],
                  weekNumber: wn,
                ),
              )
              .toList(),
        ),
      );
    }

    return [
      _WorkoutAllenamentoData(
        title: scheda.nome,
        subtitle: '${days.length} sedute • ${scheda.livello}',
        days: days,
      ),
    ];
  }

  Map<String, List<String>> _groupExercisesBySeduta(Scheda scheda) {
    if (scheda.esercizi.isEmpty) {
      return const {
        'Seduta 1': ['Corpo libero 3x12', 'Plank 3x45"'],
      };
    }

    final grouped = <String, List<String>>{};

    for (final exercise in scheda.esercizi) {
      final label = _extractSedutaLabel(exercise.note) ?? scheda.nome;
      grouped
          .putIfAbsent(label, () => <String>[])
          .add(_formatExercise(exercise));
    }

    return grouped;
  }

  String? _extractSedutaLabel(String? note) {
    if (note == null) return null;
    final text = note.trim();
    if (text.isEmpty) return null;

    final longMatch = RegExp(
      r'\b(?:seduta|giorno|day)\s*([a-z0-9]+)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (longMatch != null) {
      final code = longMatch.group(1)?.trim();
      if (code != null && code.isNotEmpty) {
        return 'Seduta ${code.toUpperCase()}';
      }
    }

    final shortMatch = RegExp(r'^\s*([a-z])\b', caseSensitive: false).firstMatch(text);
    if (shortMatch != null) {
      final code = shortMatch.group(1)?.trim();
      if (code != null && code.isNotEmpty) {
        return 'Seduta ${code.toUpperCase()}';
      }
    }

    return null;
  }

  String _formatExercise(Esercizio exercise) {
    final reps = exercise.ripetizioni.trim().isEmpty
        ? '8-10'
        : exercise.ripetizioni;
    return '${exercise.nome} ${exercise.workingSet}x$reps';
  }
}

class _SchedaAllenamentiPage extends StatelessWidget {
  const _SchedaAllenamentiPage({
    required this.scheda,
    required this.allenamenti,
    required this.onOpenWorkout,
  });

  final Scheda scheda;
  final List<_WorkoutAllenamentoData> allenamenti;
  final Future<void> Function(int week) onOpenWorkout;

  @override
  Widget build(BuildContext context) {
    final sedute = _extractSedute(allenamenti);
    const orange = Color(0xFFFF6B1A);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(title: Text(scheda.nome)),
      body: sedute.isEmpty
          ? const Center(child: Text('Nessuna seduta disponibile.', style: TextStyle(color: Color(0xFF666666))))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: sedute.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final seduta = sedute[index];

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.fitness_center, color: orange, size: 20),
                    ),
                    title: Text(
                      seduta.day.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    subtitle: Text(
                      seduta.day.weeks.length == 1 ? '1 settimana' : '${seduta.day.weeks.length} settimane',
                      style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                    children: seduta.day.weeks.isEmpty
                        ? const [
                            Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Text('Nessuna settimana disponibile.', style: TextStyle(color: Color(0xFF666666))),
                            ),
                          ]
                        : seduta.day.weeks
                              .map(
                                (week) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.timelapse_outlined, color: Color(0xFF888888), size: 18),
                                  title: Text(week.label, style: const TextStyle(color: Colors.white)),
                                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF555555), size: 18),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _WorkoutExercisesPage(
                                          dayTitle: seduta.day.title,
                                          week: week,
                                          onOpenWorkout: onOpenWorkout,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                              .toList(),
                  ),
                );
              },
            ),
    );
  }
}

class _WorkoutExercisesPage extends StatelessWidget {
  const _WorkoutExercisesPage({
    required this.dayTitle,
    required this.week,
    required this.onOpenWorkout,
  });

  final String dayTitle;
  final _WorkoutWeekData week;
  final Future<void> Function(int week) onOpenWorkout;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B1A);
    const red = Color(0xFFCC1A1A);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(title: Text('$dayTitle – ${week.label}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              itemCount: week.exercises.length,
              itemBuilder: (context, index) {
                final exercise = week.exercises[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: orange.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: orange, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(exercise, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [red, orange],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: orange.withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => onOpenWorkout(week.weekNumber),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: const Text(
                    'APRI ALLENAMENTO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutAllenamentoData {
  const _WorkoutAllenamentoData({
    required this.title,
    required this.subtitle,
    required this.days,
  });

  final String title;
  final String subtitle;
  final List<_WorkoutDayData> days;
}

class _WorkoutDayData {
  const _WorkoutDayData({required this.title, required this.weeks});

  final String title;
  final List<_WorkoutWeekData> weeks;
}

class _WorkoutWeekData {
  const _WorkoutWeekData({
    required this.label,
    required this.exercises,
    required this.weekNumber,
  });

  final String label;
  final List<String> exercises;
  final int weekNumber;
}

class _SedutaViewData {
  const _SedutaViewData({required this.allenamentoTitle, required this.day});

  final String allenamentoTitle;
  final _WorkoutDayData day;
}

List<_SedutaViewData> _extractSedute(
  List<_WorkoutAllenamentoData> allenamenti,
) {
  final out = <_SedutaViewData>[];
  for (final allenamento in allenamenti) {
    for (final day in allenamento.days) {
      out.add(_SedutaViewData(allenamentoTitle: allenamento.title, day: day));
    }
  }
  return out;
}
