part of 'workouts_screen.dart';

extension _WorkoutsScreenView on _WorkoutsScreenState {
  Widget _buildStretchingInfoSection() {
    final stretching = stretchingPerZona(_zonaStretchingSelezionata);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.self_improvement, color: Colors.lightBlueAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sezione informativa • Solo stretching',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Routine breve consigliata nei giorni di recupero o pre-allenamento leggero.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            const Text(
              'Zona condivisa con PR e Dolori',
              style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zoneDolore.map((zona) {
                final isSelected = _zonaStretchingSelezionata == zona;
                return ChoiceChip(
                  label: Text(zona),
                  selected: isSelected,
                  onSelected: (_) {
                    _updateState(() => _zonaStretchingSelezionata = zona);
                    _salvaZonaStretching(zona);
                  },
                  selectedColor: Colors.deepOrange,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade300,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            ...stretching.map(
              (riga) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(riga)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutsScreen(BuildContext context) {
    final schedeRaggruppate = _raggruppaSchedePerCategoria();
    List<String> categorie = schedeRaggruppate.keys.toList()..sort();

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
                _buildStretchingInfoSection(),
                Expanded(child: _buildCategorieList(context, schedeRaggruppate, categorie)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _apriMenuCreazione,
        child: const Icon(Icons.add),
      ),
    );
  }
}
