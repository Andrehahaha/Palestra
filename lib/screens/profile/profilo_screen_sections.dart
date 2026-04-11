part of 'profilo_screen.dart';

extension _ProfiloScreenSections on _ProfiloScreenState {
  Widget _buildGraficiTab() {
    List<FlSpot> puntiLineari = _generaPuntiGraficoLineare();
    List<PieChartSectionData> puntiTorta = _generaDatiTorta();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Calendario Allenamenti',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TableCalendar(
                firstDay: DateTime.utc(2023, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Mese'},
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerStyle: const HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                eventLoader: (day) {
                  return storico
                      .where(
                        (a) =>
                            a.data.year == day.year &&
                            a.data.month == day.month &&
                            a.data.day == day.day,
                      )
                      .toList();
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    if (events.isEmpty) return const SizedBox();

                    bool haAllenamento = false;
                    bool haPR = false;

                    for (var event in events) {
                      Allenamento a = event as Allenamento;
                      if (a.scheda.nome.contains('🏆 TEST PR')) {
                        haPR = true;
                      } else {
                        haAllenamento = true;
                      }
                    }

                    return Positioned(
                      bottom: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (haAllenamento)
                            Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                              ),
                            ),
                          if (haPR)
                            Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.purpleAccent,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Distribuzione Muscolare (Set)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 16),
          if (puntiTorta.isEmpty)
            const Text(
              'Nessun dato muscolare disponibile.',
              style: TextStyle(color: Colors.grey),
            )
          else
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: puntiTorta,
                ),
              ),
            ),
          const SizedBox(height: 40),
          const Text(
            'Curva della Forza',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 8),
          if (nomiEserciziGrafico.isEmpty)
            const Text(
              'Completa un allenamento per vedere i progressi.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Seleziona Esercizio',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(
                  Icons.fitness_center,
                  color: Colors.deepOrange,
                ),
                filled: true,
                fillColor: Colors.black12,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: esercizioSelezionato,
                  isDense: true,
                  isExpanded: true,
                  items: nomiEserciziGrafico
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      _updateState(() => esercizioSelezionato = v),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: puntiLineari.isEmpty
                  ? const Center(
                      child: Text(
                        'Nessun dato di peso.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.withValues(alpha: 0.2),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) => Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '#${value.toInt() + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 45,
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}kg',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.5),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: puntiLineari,
                            isCurved: true,
                            color: Colors.deepOrange,
                            barWidth: 4,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.deepOrange.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildLibreriaTab() {
    List<Map<String, dynamic>> tuttiEsercizi = [];
    for (var e in catalogoEsercizi) {
      tuttiEsercizi.add({
        'nome': e.nome,
        'categoria': e.categoria,
        'video': '',
        'video2': '',
        'note': '',
      });
    }
    for (var e in eserciziCustom) {
      tuttiEsercizi.add({
        'nome': e['nome'],
        'categoria': e['categoria'],
        'video': '',
        'video2': '',
        'note': '',
      });
    }
    tuttiEsercizi.addAll(eserciziDalWeb);

    String q = _searchQuery.toLowerCase().trim();
    var eserciziFiltrati = tuttiEsercizi
        .where((e) => e['nome'].toString().toLowerCase().contains(q))
        .toList();

    Map<String, Map<String, dynamic>> eserciziUnici = {};
    for (var e in eserciziFiltrati) {
      eserciziUnici[e['nome']] = e;
    }

    Map<String, Map<String, List<Map<String, dynamic>>>> libreriaOrganizzata =
        {};

    for (var es in eserciziUnici.values) {
      String catGrezza = es['categoria']?.toString() ?? 'Altro';
      var classificazione = _classificaEsercizio(catGrezza);
      String macro = classificazione['macro']!;
      String micro = classificazione['micro']!;

      libreriaOrganizzata.putIfAbsent(macro, () => {});
      libreriaOrganizzata[macro]!.putIfAbsent(micro, () => []);
      libreriaOrganizzata[macro]![micro]!.add(es);
    }

    List<String> macroOrdinate = libreriaOrganizzata.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            onChanged: (value) => _updateState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Cerca esercizio...',
              prefixIcon: const Icon(Icons.search, color: Colors.deepOrange),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.1),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: macroOrdinate.length,
            itemBuilder: (context, i) {
              String macro = macroOrdinate[i];
              var microMap = libreriaOrganizzata[macro]!;
              List<String> microOrdinate = microMap.keys.toList()..sort();

              int totMacro = microMap.values.fold(
                0,
                (total, list) => total + list.length,
              );

              return ExpansionTile(
                leading: Icon(
                  _prendiIconaMuscolo(macro),
                  color: Colors.deepOrange,
                  size: 28,
                ),
                title: Text(
                  '$macro ($totMacro)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                children: microOrdinate.map((micro) {
                  var eserciziMicro = microMap[micro]!
                    ..sort((a, b) => a['nome'].compareTo(b['nome']));

                  return Padding(
                    padding: const EdgeInsets.only(left: 20.0),
                    child: ExpansionTile(
                      iconColor: Colors.grey,
                      collapsedIconColor: Colors.grey,
                      title: Text(
                        '$micro (${eserciziMicro.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                      children: eserciziMicro.map((esercizio) {
                        bool isCustom = eserciziCustom.any(
                          (e) => e['nome'] == esercizio['nome'],
                        );
                        bool haVideo =
                            esercizio['video'] != null &&
                            esercizio['video'].toString().isNotEmpty;

                        return ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 32,
                            right: 16,
                          ),
                          title: Text(
                            esercizio['nome'],
                            style: const TextStyle(fontSize: 14),
                          ),
                          leading: haVideo
                              ? const Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.deepOrange,
                                  size: 20,
                                )
                              : const Icon(
                                  Icons.fitness_center,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                          trailing: isCustom
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _eliminaEsercizio(esercizio['nome']),
                                )
                              : null,
                          onTap: () => _mostraDettagliEsercizio(esercizio),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDatiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_ind, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text(
                'I Tuoi Dati Fisici',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nomeUtenteController,
            decoration: const InputDecoration(
              labelText: 'Il tuo Nome',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pesoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Peso Corporeo (kg)',
                    prefixIcon: Icon(Icons.monitor_weight),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _altezzaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Altezza (cm)',
                    prefixIcon: Icon(Icons.height),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _misureController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Misure (Petto, Braccia, Vita, Gambe...)',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.straighten),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteExtraController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Note Generali / Obiettivi',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: _salvaDatiProfilo,
            icon: const Icon(Icons.save),
            label: const Text(
              'Salva e Sincronizza Cloud',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile.adaptive(
              title: const Text('Ricalcola automaticamente i carichi'),
              subtitle: const Text(
                'Se disattivo, mantiene i carichi custom dove possibile.',
              ),
              value: _forceRecalculateWeights,
              onChanged: _salvaPreferenzaToggle,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
