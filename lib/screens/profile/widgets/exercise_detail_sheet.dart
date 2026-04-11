import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ExerciseDetailSheet extends StatelessWidget {
  const ExerciseDetailSheet({
    super.key,
    required this.nome,
    required this.categoria,
    required this.note,
    required this.url1,
    required this.url2,
  });

  final String nome;
  final String categoria;
  final String note;
  final String url1;
  final String url2;

  bool get _haImmagine1 => url1.trim().isNotEmpty;
  bool get _haImmagine2 => url2.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      nome,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Categoria: $categoria',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              if (_haImmagine1 || _haImmagine2)
                _buildImmagineAnimata(url1, url2)
              else
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Icon(
                      Icons.fitness_center,
                      color: Colors.grey,
                      size: 50,
                    ),
                  ),
                ),
              if (_haImmagine1 && _haImmagine2) ...[
                const SizedBox(height: 10),
                const Text(
                  'Scorri lateralmente per vedere entrambe le immagini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Note tecniche',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(note),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImmagineAnimata(String primaUrl, String secondaUrl) {
    final urls = [
      primaUrl,
      secondaUrl,
    ].where((u) => u.trim().isNotEmpty).toList(growable: false);

    if (urls.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Icon(Icons.fitness_center, color: Colors.grey, size: 50),
        ),
      );
    }

    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: urls.first,
          height: 220,
          fit: BoxFit.contain,
          placeholder: (c, u) => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (c, u, e) => const SizedBox(
            height: 220,
            child: Center(
              child: Icon(Icons.fitness_center, color: Colors.grey, size: 50),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: urls.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.contain,
                placeholder: (c, u) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (c, u, e) => const Center(
                  child: Icon(
                    Icons.fitness_center,
                    color: Colors.grey,
                    size: 50,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
