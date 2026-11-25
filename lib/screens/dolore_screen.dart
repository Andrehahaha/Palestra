import 'package:flutter/material.dart';

import '../services/archivio_atleta.dart';
import '../services/dolore_data.dart';
import '../services/valutazione_dolore.dart';

class DoloreScreen extends StatefulWidget {
  const DoloreScreen({super.key});

  @override
  State<DoloreScreen> createState() => _DoloreScreenState();
}

class _DoloreScreenState extends State<DoloreScreen> {
  String _zonaSelezionata = 'Lombare';
  String _tipoDoloreSelezionato = 'Contrattura muscolare';
  bool _usaMiniTest = false;

  RisposteTestDolore _risposte = const RisposteTestDolore();
  EsitoTestDolore? _esitoTest;

  final ArchivioAtleta _archivio = ArchivioAtleta.instance;

  void _onZonaCondivisaChanged() {
    if (!mounted) return;
    if (_zonaSelezionata != zonaStretchingNotifier.value) {
      setState(() => _zonaSelezionata = zonaStretchingNotifier.value);
    }
  }

  @override
  void initState() {
    super.initState();
    _zonaSelezionata = zonaStretchingNotifier.value;
    zonaStretchingNotifier.addListener(_onZonaCondivisaChanged);
    _caricaZonaSelezionata();
  }

  @override
  void dispose() {
    zonaStretchingNotifier.removeListener(_onZonaCondivisaChanged);
    super.dispose();
  }

  Future<void> _caricaZonaSelezionata() async {
    await _archivio.carica();
    if (!mounted) return;
    final tipo = _archivio.tipoDolore;
    setState(() {
      _zonaSelezionata = _archivio.zonaStretching;
      if (tipo != null && profiliDolore.containsKey(tipo)) _tipoDoloreSelezionato = tipo;
    });
  }

  Future<void> _salvaZonaSelezionata(String zona) async {
    _archivio.tipoDolore = _tipoDoloreSelezionato;
    await _archivio.impostaZona(zona);
  }

  Future<void> _salvaTipoDoloreSelezionato(String tipo) => _archivio.impostaTipoDolore(tipo);

  Widget _buildSceltaTest(String titolo, String? valore, List<String> opzioni, void Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titolo, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opzioni.map((opzione) {
            final isSelected = valore == opzione;
            return ChoiceChip(
              label: Text(opzione),
              selected: isSelected,
              onSelected: (_) => onSelect(opzione),
              selectedColor: Colors.deepOrange,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade300,
                fontWeight: FontWeight.bold,
              ),
              backgroundColor: const Color(0xFF1E1E1E),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profilo = profiliDolore[_tipoDoloreSelezionato]!;
    final livello = profilo['livello'] as String;
    final mostraConsigliZona = _tipoDoloreSelezionato != 'Strappo (lacerazione)';
    final stretching = [
      ...(profilo['stretching'] as List<String>),
      if (mostraConsigliZona) ...stretchingPerZona(_zonaSelezionata),
    ];
    final esercizi = [
      ...(profilo['esercizi'] as List<String>),
      if (mostraConsigliZona) ...eserciziPerZona(_zonaSelezionata),
    ];

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
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              child: const Text(
                'Suggerimenti generali: se il dolore è forte, dura a lungo o peggiora, sospendi i carichi e senti un professionista sanitario.',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Dove senti dolore?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Zona condivisa con PR e Schede',
              style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zoneDolore.map((zona) {
                final isSelected = _zonaSelezionata == zona;
                return ChoiceChip(
                  label: Text(zona),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _zonaSelezionata = zona);
                    _salvaZonaSelezionata(zona);
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
            const SizedBox(height: 18),
            const Text(
              'Che tipo di dolore senti?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Selezione manuale'),
                  selected: !_usaMiniTest,
                  onSelected: (_) => setState(() => _usaMiniTest = false),
                  selectedColor: Colors.deepOrange,
                  backgroundColor: const Color(0xFF1E1E1E),
                  labelStyle: TextStyle(color: !_usaMiniTest ? Colors.white : Colors.grey.shade300, fontWeight: FontWeight.bold),
                ),
                ChoiceChip(
                  label: const Text('Mini test guidato'),
                  selected: _usaMiniTest,
                  onSelected: (_) => setState(() => _usaMiniTest = true),
                  selectedColor: Colors.deepOrange,
                  backgroundColor: const Color(0xFF1E1E1E),
                  labelStyle: TextStyle(color: _usaMiniTest ? Colors.white : Colors.grey.shade300, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_usaMiniTest)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profiliDolore.keys.map((tipo) {
                final isSelected = _tipoDoloreSelezionato == tipo;
                return ChoiceChip(
                  label: Text(tipo),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _tipoDoloreSelezionato = tipo);
                    _salvaTipoDoloreSelezionato(tipo);
                  },
                  selectedColor: Colors.deepOrange,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade300,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                );
              }).toList(),
            )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSceltaTest(
                        'Quando compare di più?',
                        _risposte.quando,
                        RisposteTestDolore.opzioniQuando,
                        (v) => setState(() => _risposte = _risposte.copyWith(quando: v)),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Dove lo senti principalmente?',
                        _risposte.dove,
                        RisposteTestDolore.opzioniDove,
                        (v) => setState(() => _risposte = _risposte.copyWith(dove: v)),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Intensità percepita',
                        _risposte.intensita,
                        RisposteTestDolore.opzioniIntensita,
                        (v) => setState(() => _risposte = _risposte.copyWith(intensita: v)),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Come si comporta?',
                        _risposte.andamento,
                        RisposteTestDolore.opzioniAndamento,
                        (v) => setState(() => _risposte = _risposte.copyWith(andamento: v)),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () {
                          final esito = ValutazioneDolore.suggerisci(_risposte);
                          setState(() {
                            _tipoDoloreSelezionato = esito.tipo;
                            _esitoTest = esito;
                          });
                          _salvaTipoDoloreSelezionato(esito.tipo);
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Suggerisci tipo dolore'),
                      ),
                      if (_esitoTest != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'Risultato test: ${_esitoTest!.tipo} • Confidenza ${_esitoTest!.confidenza}% (${_esitoTest!.etichetta})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profilo['categoria'] as String,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Livello attenzione: $livello',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: livello == 'Basso'
                          ? Colors.greenAccent
                          : livello == 'Medio'
                              ? Colors.orangeAccent
                              : livello == 'Alto'
                                  ? Colors.deepOrangeAccent
                                  : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(profilo['descrizione'] as String),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sezioneConsigli(
              titolo: 'Stretching consigliato',
              icon: Icons.self_improvement,
              color: Colors.lightBlueAccent,
              righe: stretching,
              initiallyExpanded: true,
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
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: color),
        title: Text(
          titolo,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: righe.map(
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
        ).toList(),
      ),
    );
  }
}
