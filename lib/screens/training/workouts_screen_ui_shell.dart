part of 'workouts_screen.dart';

extension _WorkoutsScreenUiShell on _WorkoutsScreenState {
  Widget _buildWorkoutsScreen(BuildContext context) {
    final schedeRaggruppate = _raggruppaSchedePerCategoria();
    final categorie = schedeRaggruppate.keys.toList()..sort();

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF13100D),
        titleSpacing: 14,
        leading: _sezioneCorrente == _WorkoutsSezione.home
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () {
                  _updateState(() {
                    _sezioneCorrente = _WorkoutsSezione.home;
                  });
                },
              ),
        title: Text(_titoloSezioneAllenamenti(), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: _buildWorkoutsAppBarActions(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildWorkoutsBody(context, schedeRaggruppate, categorie),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _sezioneCorrente == _WorkoutsSezione.schede ? _buildWorkoutsFab() : null,
    );
  }

  String _titoloSezioneAllenamenti() {
    switch (_sezioneCorrente) {
      case _WorkoutsSezione.home:
        return 'Allenamenti';
      case _WorkoutsSezione.schede:
        return 'Le Tue Schede';
    }
  }

  List<Widget> _buildWorkoutsAppBarActions(BuildContext context) {
    if (_sezioneCorrente == _WorkoutsSezione.home) {
      return const <Widget>[];
    }
    return _buildAppBarActions(context);
  }

  Widget _buildWorkoutsBody(
    BuildContext context,
    Map<String, List<Scheda>> schedeRaggruppate,
    List<String> categorie,
  ) {
    if (_sezioneCorrente == _WorkoutsSezione.home) {
      return _buildAllenamentiHomeSection(context);
    }

    return Stack(
      children: [
        _buildAllenamentiBackground(),
        Column(
          children: [
            _buildAllenamentiHeroPanel(context),
            _buildQuickAccessCards(context),
            _buildCategorieSectionLabel(categorie.length),
            Expanded(
              child: _buildCategorieList(
                context,
                schedeRaggruppate,
                categorie,
              ),
            ),
            const SizedBox(height: 74),
          ],
        ),
      ],
    );
  }

  Widget _buildAllenamentiBackground() {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF15100A), Color(0xFF22170D), Color(0xFF0F0F0F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -50,
              top: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              right: -70,
              top: 130,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              left: 90,
              bottom: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepOrangeAccent.withValues(alpha: 0.08),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutsFab() {
    return FloatingActionButton.extended(
      elevation: 8,
      backgroundColor: const Color(0xFFD86125),
      foregroundColor: Colors.white,
      onPressed: _apriMenuCreazione,
      icon: const Icon(Icons.add_circle_outline),
      label: const Text(
        'Nuova Scheda',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
