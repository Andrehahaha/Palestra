part of 'profilo_screen.dart';

extension _ProfiloScreenData on _ProfiloScreenState {
  IconData _prendiIconaMuscolo(String categoria) {
    final cat = categoria.toLowerCase();
    if (cat.contains('addominali')) return Icons.grid_view;
    if (cat.contains('gambe') ||
        cat.contains('polpacci') ||
        cat.contains('glutei')) {
      return Icons.directions_run;
    }
    if (cat.contains('petto')) return Icons.view_headline;
    if (cat.contains('dorsali') ||
        cat.contains('schiena') ||
        cat.contains('lombari') ||
        cat.contains('trapezi')) {
      return Icons.format_align_center;
    }
    if (cat.contains('bicipiti') ||
        cat.contains('tricipiti') ||
        cat.contains('avambracci') ||
        cat.contains('spalle')) {
      return Icons.fitness_center;
    }
    return Icons.list;
  }

  Map<String, String> _classificaEsercizio(String categoriaGrezza) {
    String cat = categoriaGrezza.toLowerCase();

    if (cat.contains('petto') ||
        cat.contains('pettorali') ||
        cat.contains('spinte')) {
      return {'macro': 'Petto', 'micro': 'Pettorali'};
    }
    if (cat.contains('schiena') ||
        cat.contains('dorsali') ||
        cat.contains('trapezi') ||
        cat.contains('lombari') ||
        cat.contains('upper back')) {
      String micro = 'Dorso (Generale)';
      if (cat.contains('lombari') || cat.contains('bassa')) micro = 'Lombari';
      if (cat.contains('trapezi')) micro = 'Trapezi';
      return {'macro': 'Schiena', 'micro': micro};
    }
    if (cat.contains('gambe') ||
        cat.contains('quadricipiti') ||
        cat.contains('femorali') ||
        cat.contains('glutei') ||
        cat.contains('polpacci') ||
        cat.contains('adduttori') ||
        cat.contains('calf')) {
      String micro = 'Gambe (Generale)';
      if (cat.contains('quadricipiti')) micro = 'Quadricipiti';
      if (cat.contains('femorali') || cat.contains('ischiocrurali')) {
        micro = 'Femorali';
      }
      if (cat.contains('glutei')) micro = 'Glutei';
      if (cat.contains('polpacci') || cat.contains('calf')) micro = 'Polpacci';
      if (cat.contains('adduttori') || cat.contains('abduttori')) {
        micro = 'Adduttori / Abduttori';
      }
      return {'macro': 'Gambe', 'micro': micro};
    }
    if (cat.contains('spalle') ||
        cat.contains('spalla') ||
        cat.contains('deltoidi')) {
      String micro = 'Spalle (Generale)';
      if (cat.contains('frontali')) micro = 'Deltoidi Anteriori';
      if (cat.contains('laterali')) micro = 'Deltoidi Laterali';
      if (cat.contains('posteriori')) micro = 'Deltoidi Posteriori';
      if (cat.contains('cuffia')) micro = 'Cuffia dei Rotatori';
      return {'macro': 'Spalle', 'micro': micro};
    }
    if (cat.contains('bicipiti') ||
        cat.contains('tricipiti') ||
        cat.contains('avambracci') ||
        cat.contains('braccia') ||
        cat.contains('polsi')) {
      String micro = 'Braccia (Generale)';
      if (cat.contains('bicipiti')) micro = 'Bicipiti';
      if (cat.contains('tricipiti')) micro = 'Tricipiti';
      if (cat.contains('avambracci') || cat.contains('polsi')) {
        micro = 'Avambracci';
      }
      return {'macro': 'Braccia', 'micro': micro};
    }
    if (cat.contains('addom') ||
        cat.contains('core') ||
        cat.contains('obliqui')) {
      String micro = 'Addome Centrale';
      if (cat.contains('obliqui')) micro = 'Obliqui';
      return {'macro': 'Addome e Core', 'micro': micro};
    }

    String micro = 'Vari ed Eventuali';
    if (cat.contains('stretching') ||
        cat.contains('flessibilità') ||
        cat.contains('massaggio') ||
        cat.contains('smr')) {
      micro = 'Stretching & Mobilità';
    }
    if (cat.contains('cardio') ||
        cat.contains('corsa') ||
        cat.contains('atletica')) {
      micro = 'Cardio';
    }
    if (cat.contains('olimpico') ||
        cat.contains('strongman') ||
        cat.contains('potenza') ||
        cat.contains('pliometria')) {
      micro = 'Pesistica / Potenza';
    }
    if (cat.contains('total body')) micro = 'Total Body';
    return {'macro': 'Funzionale & Altro', 'micro': micro};
  }

  String _traduciNome(String nomeOriginale) {
    return DizionarioEsercizi.daIngleseAItaliano[nomeOriginale] ??
        nomeOriginale;
  }

  String _normalizzaNome(String nome) {
    return nome.trim().toLowerCase();
  }

  Future<void> _caricaDati() async {
    final prefs = await SharedPreferences.getInstance();
    storico = [];
    nomiEserciziGrafico = [];
    eserciziCustom = [];
    eserciziDalWeb = [];

    final String? storicoSalvato = prefs.getString('storico_salvato');
    if (storicoSalvato != null) {
      final List<dynamic> jsonDecodificato = jsonDecode(storicoSalvato);
      storico = jsonDecodificato.map((e) => Allenamento.fromJson(e)).toList();

      Map<String, String> nomiUnivoci = {};
      for (var allenamento in storico) {
        for (var es in allenamento.scheda.esercizi) {
          bool ignoraPerGrafico =
              es.tecniche.contains('Back off') ||
              es.tecniche.contains('Drop Set') ||
              es.tecniche.contains('Stripping');
          if (ignoraPerGrafico) continue;

          if (es.serieAttive.any(
            (s) =>
                s.isCompletata &&
                s.peso.isNotEmpty &&
                s.tipo != 'Avvicinamento',
          )) {
            String nomeTradotto = _traduciNome(es.nome);
            String nomePulito = _normalizzaNome(nomeTradotto);
            nomiUnivoci[nomePulito] = nomeTradotto.trim();
          }
        }
      }

      List<String> listaNomi = nomiUnivoci.values.toList();
      listaNomi.sort();
      nomiEserciziGrafico = listaNomi;

      if (nomiEserciziGrafico.isNotEmpty) {
        esercizioSelezionato = nomiEserciziGrafico.first;
      }
    }

    final String? customSalvati = prefs.getString('esercizi_custom_db_v2');
    if (customSalvati != null) {
      eserciziCustom = List<Map<String, String>>.from(
        jsonDecode(customSalvati).map((item) => Map<String, String>.from(item)),
      );
    }

    final String? datiProfiloStr = prefs.getString('profilo_dati_utente');
    if (datiProfiloStr != null) {
      Map<String, dynamic> dati = jsonDecode(datiProfiloStr);
      _nomeUtenteController.text = dati['nome'] ?? '';
      _pesoController.text = dati['peso'] ?? '';
      _altezzaController.text = dati['altezza'] ?? '';
      _misureController.text = dati['misure'] ?? '';
      _noteExtraController.text = dati['note'] ?? '';
    } else {
      final String? notevecchie = prefs.getString('note_generali');
      if (notevecchie != null) _noteExtraController.text = notevecchie;
    }

    eserciziDalWeb = await ApiEsercizi.ottieniEserciziTradotti();

    if (mounted) {
      _updateState(() {
        _isLoading = false;
      });
    }

    _sincronizzaCloud();
  }

  Future<void> _sincronizzaCloud() async {
    if (userId.isEmpty) return;
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshotNuovoSchema;
      final coachId = await _caricaCoachIdAtleta(userId);

      if (coachId != null && coachId.isNotEmpty) {
        snapshotNuovoSchema = await FirebaseFirestore.instance
            .collection('coaches')
            .doc(coachId)
            .collection('athletes')
            .doc(userId)
            .collection('progress')
            .orderBy('sessionAt', descending: true)
            .get();
      }

      final docsNuovoSchema =
          snapshotNuovoSchema?.docs ??
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      if (docsNuovoSchema.isNotEmpty) {
        List<Allenamento> storicoCloud = docsNuovoSchema
            .map((doc) {
              try {
                return Allenamento.fromJson(doc.data());
              } catch (_) {
                return null;
              }
            })
            .whereType<Allenamento>()
            .toList();

        if (storicoCloud.length > storico.length) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'storico_salvato',
            jsonEncode(storicoCloud.map((e) => e.toJson()).toList()),
          );
          if (mounted) {
            _updateState(() {
              storico = storicoCloud;
              _aggiornaInterfacciaGrafici();
            });
          }
        }
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('storico_atleti')
          .where('atletaId', isEqualTo: userId)
          .orderBy('data', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        List<Allenamento> storicoCloud = snapshot.docs
            .map((doc) {
              try {
                return Allenamento.fromJson(doc.data());
              } catch (_) {
                return null;
              }
            })
            .whereType<Allenamento>()
            .toList();
        if (storicoCloud.length > storico.length) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'storico_salvato',
            jsonEncode(storicoCloud.map((e) => e.toJson()).toList()),
          );
          if (mounted) {
            _updateState(() {
              storico = storicoCloud;
              _aggiornaInterfacciaGrafici();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Sincronizzazione fallita: $e');
    }
  }

  Future<String?> _caricaCoachIdAtleta(String atletaId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(atletaId)
          .get();
      if (!doc.exists) return null;
      final coachId = doc.data()?['coachId']?.toString().trim() ?? '';
      return coachId.isEmpty ? null : coachId;
    } catch (e) {
      debugPrint('CoachId non disponibile: $e');
      return null;
    }
  }

  void _aggiornaInterfacciaGrafici() {
    Map<String, String> nomiUnivoci = {};
    for (var allenamento in storico) {
      for (var es in allenamento.scheda.esercizi) {
        bool ignoraPerGrafico =
            es.tecniche.contains('Back off') ||
            es.tecniche.contains('Drop Set') ||
            es.tecniche.contains('Stripping');
        if (ignoraPerGrafico) continue;

        if (es.serieAttive.any(
          (s) =>
              s.isCompletata && s.peso.isNotEmpty && s.tipo != 'Avvicinamento',
        )) {
          String nomeTradotto = _traduciNome(es.nome);
          nomiUnivoci[_normalizzaNome(nomeTradotto)] = nomeTradotto.trim();
        }
      }
    }
    List<String> listaNomi = nomiUnivoci.values.toList();
    listaNomi.sort();
    nomiEserciziGrafico = listaNomi;

    if (nomiEserciziGrafico.isEmpty) {
      esercizioSelezionato = null;
      return;
    }

    if (esercizioSelezionato == null ||
        !nomiEserciziGrafico.contains(esercizioSelezionato)) {
      esercizioSelezionato = nomiEserciziGrafico.first;
    }
  }

  Future<void> _aggiungiEsercizioManualmente() async {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo Esercizio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nuovoEsercizioController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome Esercizio',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _categoriaNuovoEsercizio,
                decoration: const InputDecoration(
                  labelText: 'Gruppo Muscolare',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                          'Petto',
                          'Schiena',
                          'Gambe',
                          'Spalle',
                          'Bicipiti',
                          'Tricipiti',
                          'Addominali',
                          'Altro',
                        ]
                        .map(
                          (cat) =>
                              DropdownMenuItem(value: cat, child: Text(cat)),
                        )
                        .toList(),
                onChanged: (val) =>
                    setDialogState(() => _categoriaNuovoEsercizio = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () async {
                String nome = _nuovoEsercizioController.text.trim();
                if (nome.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  _updateState(() {
                    eserciziCustom.add({
                      'nome': nome,
                      'categoria': _categoriaNuovoEsercizio,
                    });
                  });
                  await prefs.setString(
                    'esercizi_custom_db_v2',
                    jsonEncode(eserciziCustom),
                  );
                  _nuovoEsercizioController.clear();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvaDatiProfilo() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> datiPersonali = {
      'nome': _nomeUtenteController.text.trim(),
      'peso': _pesoController.text.trim(),
      'altezza': _altezzaController.text.trim(),
      'misure': _misureController.text.trim(),
      'note': _noteExtraController.text.trim(),
    };

    await prefs.setString('profilo_dati_utente', jsonEncode(datiPersonali));

    if (userId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'datiFisici': datiPersonali,
        'ultimaModifica': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dati salvati con successo! ✅'),
        backgroundColor: Colors.green,
      ),
    );
  }

  List<FlSpot> _generaPuntiGraficoLineare() {
    if (esercizioSelezionato == null) return [];
    List<FlSpot> punti = [];
    List<Allenamento> storicoOrdinato = List.from(storico)
      ..sort((a, b) => a.data.compareTo(b.data));
    int numeroSessione = 0;
    String selezPulito = _normalizzaNome(esercizioSelezionato!);

    for (var allenamento in storicoOrdinato) {
      for (var es in allenamento.scheda.esercizi) {
        String nomeStoricoTradotto = _normalizzaNome(_traduciNome(es.nome));

        if (nomeStoricoTradotto == selezPulito) {
          bool ignoraPerGrafico =
              es.tecniche.contains('Back off') ||
              es.tecniche.contains('Drop Set') ||
              es.tecniche.contains('Stripping');
          if (ignoraPerGrafico) continue;

          double maxPeso = 0;
          for (var s in es.serieAttive) {
            if (s.isCompletata &&
                s.peso.isNotEmpty &&
                s.tipo != 'Avvicinamento') {
              double? p = double.tryParse(s.peso.replaceAll(',', '.'));
              if (p != null && p > maxPeso) maxPeso = p;
            }
          }
          if (maxPeso > 0) {
            punti.add(FlSpot(numeroSessione.toDouble(), maxPeso));
            numeroSessione++;
          }
        }
      }
    }
    return punti;
  }

  List<PieChartSectionData> _generaDatiTorta() {
    Map<String, int> conteggio = {};
    int totaleSerie = 0;

    for (var allenamento in storico) {
      for (var es in allenamento.scheda.esercizi) {
        String cat = 'Altro';

        String nomeTradotto = _traduciNome(es.nome);
        var matchDb = eserciziDalWeb.where((e) => e['nome'] == nomeTradotto);

        if (matchDb.isNotEmpty) {
          var classificazione = _classificaEsercizio(
            matchDb.first['categoria'],
          );
          cat = classificazione['macro']!;
        } else {
          var matchCustom = eserciziCustom.where(
            (e) => e['nome'] == nomeTradotto,
          );
          if (matchCustom.isNotEmpty) {
            var classificazione = _classificaEsercizio(
              matchCustom.first['categoria'] ?? 'Altro',
            );
            cat = classificazione['macro']!;
          }
        }

        int serieFatte = es.serieAttive
            .where((s) => s.isCompletata && s.tipo != 'Avvicinamento')
            .length;
        if (serieFatte > 0) {
          conteggio[cat] = (conteggio[cat] ?? 0) + serieFatte;
          totaleSerie += serieFatte;
        }
      }
    }

    if (totaleSerie == 0) return [];

    List<Color> colori = [
      Colors.deepOrange,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.amber,
      Colors.teal,
      Colors.redAccent,
      Colors.indigo,
    ];
    int i = 0;

    return conteggio.entries.map((e) {
      final double percentuale = (e.value / totaleSerie) * 100;
      final color = colori[i % colori.length];
      i++;
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${percentuale.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        badgeWidget: Text(
          e.key,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        badgePositionPercentageOffset: 1.3,
      );
    }).toList();
  }

  void _mostraDettagliEsercizio(Map<String, dynamic> esercizio) {
    final String url1 = (esercizio['video'] ?? '').toString();
    final String url2 = (esercizio['video2'] ?? '').toString();
    final String nome = (esercizio['nome'] ?? 'Esercizio').toString();
    final String categoria = (esercizio['categoria'] ?? 'Altro').toString();
    final String note = (esercizio['note'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ExerciseDetailSheet(
        nome: nome,
        categoria: categoria,
        note: note,
        url1: url1,
        url2: url2,
      ),
    );
  }

  Future<void> _eliminaEsercizio(String nome) async {
    final prefs = await SharedPreferences.getInstance();
    _updateState(() {
      eserciziCustom.removeWhere((e) => e['nome'] == nome);
    });
    await prefs.setString('esercizi_custom_db_v2', jsonEncode(eserciziCustom));
  }
}
