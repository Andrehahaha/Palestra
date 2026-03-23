import 'package:flutter/material.dart';

class DoloreScreen extends StatefulWidget {
  const DoloreScreen({super.key});

  @override
  State<DoloreScreen> createState() => _DoloreScreenState();
}

class _DoloreScreenState extends State<DoloreScreen> {
  final List<String> _zone = const [
    'Collo',
    'Spalle',
    'Schiena alta',
    'Lombare',
    'Anca',
    'Ginocchio',
    'Polso',
    'Caviglia',
  ];

  final Map<String, Map<String, List<String>>> _consigli = const {
    'Collo': {
      'stretching': [
        'Stretch trapezio superiore: 2 x 30 secondi per lato',
        'Chin tuck (mento indietro): 2 x 10 ripetizioni lente',
        'Mobilita rotazioni cervicali controllate: 2 x 8 per lato',
      ],
      'esercizi': [
        'Retrazioni scapolari al muro: 3 x 12',
        'Face pull elastico leggero: 3 x 15',
        'Respirazione diaframmatica 90/90: 3 x 6 respiri',
      ],
    },
    'Spalle': {
      'stretching': [
        'Sleeper stretch delicato: 2 x 30 secondi per lato',
        'Pettorale su porta: 2 x 30 secondi per lato',
        'Lat stretch su appoggio: 2 x 30 secondi',
      ],
      'esercizi': [
        'Extra-rotazioni con elastico: 3 x 15',
        'Y-T-W prone a corpo libero: 2 x 8',
        'Scap push-up: 3 x 10',
      ],
    },
    'Schiena alta': {
      'stretching': [
        'Estensioni toraciche su foam roller: 2 x 8',
        'Child pose con focus dorsale: 2 x 40 secondi',
        'Thread the needle: 2 x 8 per lato',
      ],
      'esercizi': [
        'Rematore elastico presa neutra: 3 x 12',
        'Wall slides: 3 x 10',
        'Dead bug: 3 x 8 per lato',
      ],
    },
    'Lombare': {
      'stretching': [
        'Cat-cow controllato: 2 x 10',
        'Stretch flessori anca: 2 x 30 secondi per lato',
        'Glute stretch supino: 2 x 30 secondi per lato',
      ],
      'esercizi': [
        'Bird dog: 3 x 8 per lato',
        'Glute bridge: 3 x 12',
        'Plank corto: 3 x 20-30 secondi',
      ],
    },
    'Anca': {
      'stretching': [
        '90/90 anca: 2 x 6 per lato',
        'Affondo statico flessori: 2 x 30 secondi per lato',
        'Pigeon modificato: 2 x 30 secondi per lato',
      ],
      'esercizi': [
        'Clamshell con miniband: 3 x 15 per lato',
        'Lateral walk miniband: 3 x 12 passi',
        'Step-up basso controllato: 3 x 10 per lato',
      ],
    },
    'Ginocchio': {
      'stretching': [
        'Quad stretch in piedi: 2 x 30 secondi per lato',
        'Polpaccio al muro: 2 x 30 secondi per lato',
        'Hamstring stretch supino: 2 x 30 secondi per lato',
      ],
      'esercizi': [
        'Spanish squat isometrico: 4 x 30 secondi',
        'Terminal knee extension con elastico: 3 x 15',
        'Step-down basso lento: 3 x 8 per lato',
      ],
    },
    'Polso': {
      'stretching': [
        'Stretch flessori polso: 2 x 30 secondi per lato',
        'Stretch estensori polso: 2 x 30 secondi per lato',
        'Pronazione/supinazione leggera: 2 x 12',
      ],
      'esercizi': [
        'Wrist curl leggero: 3 x 15',
        'Reverse wrist curl leggero: 3 x 15',
        'Grip isometrico morbido: 3 x 20 secondi',
      ],
    },
    'Caviglia': {
      'stretching': [
        'Dorsiflessione al muro: 2 x 10 per lato',
        'Polpaccio gastrocnemio/soleo: 2 x 30 secondi per lato',
        'Mobilita caviglia in affondo: 2 x 10 per lato',
      ],
      'esercizi': [
        'Calf raise lento: 3 x 15',
        'Tibialis raise al muro: 3 x 15',
        'Equilibrio monopodalico: 3 x 30 secondi per lato',
      ],
    },
  };

  String _zonaSelezionata = 'Lombare';

  @override
  Widget build(BuildContext context) {
    final consigliZona = _consigli[_zonaSelezionata]!;
    final stretching = consigliZona['stretching']!;
    final esercizi = consigliZona['esercizi']!;

    return Scaffold(
      appBar: AppBar(title: const Text('Dolori & Recupero')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.45)),
              ),
              child: const Text(
                'Suggerimenti generali: se il dolore e forte, dura a lungo o peggiora, sospendi i carichi e senti un professionista sanitario.',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Dove senti dolore?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _zone.map((zona) {
                final isSelected = _zonaSelezionata == zona;
                return ChoiceChip(
                  label: Text(zona),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _zonaSelezionata = zona),
                  selectedColor: Colors.deepOrange,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade300,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            _sezioneConsigli(
              titolo: 'Stretching consigliato',
              icon: Icons.self_improvement,
              color: Colors.lightBlueAccent,
              righe: stretching,
            ),
            const SizedBox(height: 14),
            _sezioneConsigli(
              titolo: 'Esercizi consigliati',
              icon: Icons.fitness_center,
              color: Colors.greenAccent,
              righe: esercizi,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sezioneConsigli({
    required String titolo,
    required IconData icon,
    required Color color,
    required List<String> righe,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  titolo,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...righe.map(
              (riga) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
}
