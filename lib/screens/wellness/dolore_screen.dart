import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/dolore_data.dart';

class DoloreScreen extends StatefulWidget {
  const DoloreScreen({super.key});

  @override
  State<DoloreScreen> createState() => _DoloreScreenState();
}

class _DoloreScreenState extends State<DoloreScreen> {
  String _zonaSelezionata = 'Lombare';
  String _tipoDoloreSelezionato = 'Contrattura muscolare';
  bool _usaMiniTest = false;

  String? _quandoDolore;
  String? _doveDolore;
  String? _intensitaDolore;
  String? _andamentoDolore;
  String? _tipoSuggeritoTest;
  int? _confidenzaTest;

  static const String _tipoDoloreKey = 'tipo_dolore_selezionato';

  final Map<String, Map<String, dynamic>> _profiliDolore = const {
    'Bruciore da acido lattico': {
      'categoria': 'Dolori fisiologici (normali)',
      'livello': 'Basso',
      'descrizione': 'Sensazione acuta durante la serie, in genere si riduce in pochi minuti.',
      'stretching': [
        'Defaticamento attivo 3-5 minuti',
        'Respirazione controllata 2 x 6 respiri',
        'Stretch leggero 2 x 20-30 secondi',
      ],
      'esercizi': [
        'Riduci il carico e allunga il recupero tra le serie',
        'Passa a ROM controllato e ritmo piu lento',
        'Idratazione e pausa di 2-3 minuti prima del set successivo',
      ],
    },
    'DOMS (indolenzimento ritardato)': {
      'categoria': 'Dolori fisiologici (normali)',
      'livello': 'Basso',
      'descrizione': 'Rigidita e dolore sordo che compare 24-48 ore dopo l’allenamento.',
      'stretching': [
        'Mobilita dolce 2 x 8-10',
        'Stretch leggero senza dolore acuto 2 x 30 secondi',
        'Camminata blanda 8-12 minuti',
      ],
      'esercizi': [
        'Recupero attivo a bassa intensita',
        'Riduci volume e carico nella sessione successiva',
        'Evita eccentriche pesanti finche la rigidita cala',
      ],
    },
    'Dolore meccanico articolare': {
      'categoria': 'Infortuni articolari e tendinei',
      'livello': 'Medio',
      'descrizione': 'Fastidio/fitta interna all’articolazione (es. spalla, ginocchio, polso).',
      'stretching': [
        'Mobilita articolare lenta e controllata 2 x 8',
        'Evita forzature a fine ROM doloroso',
        'Decompressione/articolazione scarica 2-3 minuti',
      ],
      'esercizi': [
        'Riduci carichi 30-50% e lavora su tecnica',
        'Usa varianti stabili e senza dolore',
        'Stop immediato se il dolore aumenta durante il set',
      ],
    },
    'Tendinite': {
      'categoria': 'Infortuni articolari e tendinei',
      'livello': 'Medio',
      'descrizione': 'Infiammazione del tendine da ripetizione o sovraccarico.',
      'stretching': [
        'Stretch lieve e graduale senza dolore acuto',
        'Mobilita controllata 2 x 8-10',
        'Recupero con pause piu lunghe tra le serie',
      ],
      'esercizi': [
        'Isometrici leggeri sul distretto 3 x 20-30 secondi',
        'Eccentrici leggeri se tollerati 2 x 10',
        'Evita picchi di carico finche i sintomi non calano',
      ],
    },
    'Contrattura muscolare': {
      'categoria': 'Traumi muscolari acuti',
      'livello': 'Medio',
      'descrizione': 'Indurimento e tensione involontaria del muscolo, senza rottura di fibre.',
      'stretching': [
        'Respirazione lenta 2 x 6 respiri profondi',
        'Stretch progressivo 2-3 x 30 secondi',
        'Mobilita a ROM ridotto 2 x 8-10',
      ],
      'esercizi': [
        'Isometria leggera 3 x 20-30 secondi',
        'Movimento a carico minimo e ritmo lento 2-3 x 10',
        'Camminata/cyclette blanda 8-12 minuti',
      ],
    },
    'Elongazione (stiramento)': {
      'categoria': 'Traumi muscolari acuti',
      'livello': 'Alto',
      'descrizione': 'Eccessivo allungamento del muscolo con possibili micro-lacerazioni.',
      'stretching': [
        'Niente stretching aggressivo nelle prime 24-72h',
        'Solo mobilita molto dolce entro soglia non dolorosa',
        'Progressione graduale solo se i sintomi migliorano',
      ],
      'esercizi': [
        'Evita carichi esplosivi e allungamenti forzati',
        'Isometrie leggere solo se ben tollerate',
        'Valuta consulto professionale se il dolore persiste',
      ],
    },
    'Strappo (lacerazione)': {
      'categoria': 'Traumi muscolari acuti',
      'livello': 'Molto alto',
      'descrizione': 'Rottura parziale o totale delle fibre muscolari (grado 1-2-3).',
      'stretching': [
        'Sospendi stretching e carichi sul distretto coinvolto',
        'Proteggi l’area e limita i movimenti dolorosi',
        'Richiedi valutazione medica/fisioterapica',
      ],
      'esercizi': [
        'Nessun esercizio di carico finche non valutato',
        'Mantieni solo attivita non dolorose a distanza dal distretto',
        'Rientro graduale guidato da professionista',
      ],
    },
  };

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
    final prefs = await SharedPreferences.getInstance();
    final String? zonaSalvata = prefs.getString(zonaStretchingSharedKey);
    final String? tipoSalvato = prefs.getString(_tipoDoloreKey);
    if (!mounted) return;
    if (zonaSalvata != null && zoneDolore.contains(zonaSalvata)) {
      setState(() => _zonaSelezionata = zonaSalvata);
      aggiornaZonaStretchingCondivisa(zonaSalvata);
    }
    if (tipoSalvato != null && _profiliDolore.containsKey(tipoSalvato)) {
      setState(() => _tipoDoloreSelezionato = tipoSalvato);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final cloudZona = doc.data()?['app_state']?['zona_stretching'];
        final cloudTipo = doc.data()?['app_state']?['tipo_dolore'];
        if (cloudZona is String && zoneDolore.contains(cloudZona) && mounted) {
          setState(() => _zonaSelezionata = cloudZona);
          aggiornaZonaStretchingCondivisa(cloudZona);
          await prefs.setString(zonaStretchingSharedKey, cloudZona);
        }
        if (cloudTipo is String && _profiliDolore.containsKey(cloudTipo) && mounted) {
          setState(() => _tipoDoloreSelezionato = cloudTipo);
          await prefs.setString(_tipoDoloreKey, cloudTipo);
        }
      } catch (e) {
        debugPrint('Errore caricamento zona cloud Dolore: $e');
      }
    }
  }

  Future<void> _salvaZonaSelezionata(String zona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(zonaStretchingSharedKey, zona);
    aggiornaZonaStretchingCondivisa(zona);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'app_state': {
            'zona_stretching': zona,
            'tipo_dolore': _tipoDoloreSelezionato,
            'updated_at': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Errore salvataggio zona cloud Dolore: $e');
      }
    }
  }

  Future<void> _salvaTipoDoloreSelezionato(String tipo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tipoDoloreKey, tipo);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'app_state': {
            'tipo_dolore': tipo,
            'updated_at': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Errore salvataggio tipo dolore cloud: $e');
      }
    }
  }

  String _etichettaConfidenza(int valore) {
    if (valore >= 70) return 'Alta';
    if (valore >= 45) return 'Media';
    return 'Bassa';
  }

  Map<String, dynamic> _suggerisciTipoDaTest() {
    final score = <String, int>{
      'Bruciore da acido lattico': 0,
      'DOMS (indolenzimento ritardato)': 0,
      'Dolore meccanico articolare': 0,
      'Tendinite': 0,
      'Contrattura muscolare': 0,
      'Elongazione (stiramento)': 0,
      'Strappo (lacerazione)': 0,
    };

    int risposteDate = 0;

    if (_quandoDolore != null) {
      risposteDate++;
      if (_quandoDolore == '24-48h dopo') score['DOMS (indolenzimento ritardato)'] = score['DOMS (indolenzimento ritardato)']! + 3;
      if (_quandoDolore == 'Durante la serie') score['Bruciore da acido lattico'] = score['Bruciore da acido lattico']! + 2;
      if (_quandoDolore == 'Dopo gesto brusco') {
        score['Elongazione (stiramento)'] = score['Elongazione (stiramento)']! + 2;
        score['Strappo (lacerazione)'] = score['Strappo (lacerazione)']! + 2;
      }
    }

    if (_doveDolore != null) {
      risposteDate++;
      if (_doveDolore == 'Dentro l’articolazione') score['Dolore meccanico articolare'] = score['Dolore meccanico articolare']! + 3;
      if (_doveDolore == 'Tendine/punto specifico') score['Tendinite'] = score['Tendinite']! + 3;
      if (_doveDolore == 'Fitta muscolare netta') {
        score['Elongazione (stiramento)'] = score['Elongazione (stiramento)']! + 2;
        score['Strappo (lacerazione)'] = score['Strappo (lacerazione)']! + 2;
      }
      if (_doveDolore == 'Muscolo diffuso') score['Contrattura muscolare'] = score['Contrattura muscolare']! + 2;
    }

    if (_intensitaDolore != null) {
      risposteDate++;
      if (_intensitaDolore == 'Bassa') {
        score['Bruciore da acido lattico'] = score['Bruciore da acido lattico']! + 1;
        score['DOMS (indolenzimento ritardato)'] = score['DOMS (indolenzimento ritardato)']! + 1;
      }
      if (_intensitaDolore == 'Media') {
        score['Contrattura muscolare'] = score['Contrattura muscolare']! + 1;
        score['Tendinite'] = score['Tendinite']! + 1;
      }
      if (_intensitaDolore == 'Alta') {
        score['Strappo (lacerazione)'] = score['Strappo (lacerazione)']! + 3;
        score['Elongazione (stiramento)'] = score['Elongazione (stiramento)']! + 2;
      }
    }

    if (_andamentoDolore != null) {
      risposteDate++;
      if (_andamentoDolore == 'Migliora scaldandomi') score['Contrattura muscolare'] = score['Contrattura muscolare']! + 2;
      if (_andamentoDolore == 'Peggiora con carico ripetuto') score['Tendinite'] = score['Tendinite']! + 3;
      if (_andamentoDolore == 'Dolore con movimenti articolari') score['Dolore meccanico articolare'] = score['Dolore meccanico articolare']! + 3;
      if (_andamentoDolore == 'Blocca il movimento') score['Strappo (lacerazione)'] = score['Strappo (lacerazione)']! + 3;
    }

    String migliore = 'Contrattura muscolare';
    int maxPunti = -1;
    for (final entry in score.entries) {
      if (entry.value > maxPunti) {
        maxPunti = entry.value;
        migliore = entry.key;
      }
    }

    if (maxPunti <= 0) {
      return {'tipo': 'Contrattura muscolare', 'confidenza': 35};
    }

    final denominatore = (risposteDate * 3).clamp(1, 1000);
    int confidenza = ((maxPunti / denominatore) * 100).round();
    confidenza = confidenza.clamp(35, 95);

    return {'tipo': migliore, 'confidenza': confidenza};
  }

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
    final profilo = _profiliDolore[_tipoDoloreSelezionato]!;
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
              children: _profiliDolore.keys.map((tipo) {
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
                        _quandoDolore,
                        const ['Durante la serie', 'Subito dopo', '24-48h dopo', 'Dopo gesto brusco'],
                        (v) => setState(() => _quandoDolore = v),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Dove lo senti principalmente?',
                        _doveDolore,
                        const ['Muscolo diffuso', 'Tendine/punto specifico', 'Dentro l’articolazione', 'Fitta muscolare netta'],
                        (v) => setState(() => _doveDolore = v),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Intensità percepita',
                        _intensitaDolore,
                        const ['Bassa', 'Media', 'Alta'],
                        (v) => setState(() => _intensitaDolore = v),
                      ),
                      const SizedBox(height: 12),
                      _buildSceltaTest(
                        'Come si comporta?',
                        _andamentoDolore,
                        const ['Migliora scaldandomi', 'Peggiora con carico ripetuto', 'Dolore con movimenti articolari', 'Blocca il movimento'],
                        (v) => setState(() => _andamentoDolore = v),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () {
                          final risultato = _suggerisciTipoDaTest();
                          final suggerito = risultato['tipo'] as String;
                          final confidenza = risultato['confidenza'] as int;
                          setState(() {
                            _tipoDoloreSelezionato = suggerito;
                            _tipoSuggeritoTest = suggerito;
                            _confidenzaTest = confidenza;
                          });
                          _salvaTipoDoloreSelezionato(suggerito);
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Suggerisci tipo dolore'),
                      ),
                      if (_tipoSuggeritoTest != null && _confidenzaTest != null) ...[
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
                            'Risultato test: $_tipoSuggeritoTest • Confidenza ${_confidenzaTest!}% (${_etichettaConfidenza(_confidenzaTest!)})',
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
