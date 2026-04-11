part of 'workouts_screen.dart';

extension _WorkoutsScreenView on _WorkoutsScreenState {
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
