part of 'dettaglio_scheda_screen.dart';

class RecuperoTimerWidget extends StatefulWidget {
  final int secondiTotali;

  const RecuperoTimerWidget({super.key, required this.secondiTotali});

  @override
  State<RecuperoTimerWidget> createState() => _RecuperoTimerWidgetState();
}

class _RecuperoTimerWidgetState extends State<RecuperoTimerWidget> {
  late int _rimanenti;
  Timer? _t;
  Timer? _alarmTimer;
  late DateTime _fineTimer;

  @override
  void initState() {
    super.initState();
    _rimanenti = widget.secondiTotali;

    _fineTimer = DateTime.now().add(Duration(seconds: widget.secondiTotali));
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _aggiornaDaTempoReale());
    _aggiornaDaTempoReale();
  }

  void _aggiornaDaTempoReale() {
    final secondiRestanti = _fineTimer.difference(DateTime.now()).inSeconds;
    final nuoviRimanenti = secondiRestanti > 0 ? secondiRestanti : 0;

    if (!mounted) return;
    if (_rimanenti != nuoviRimanenti) {
      setState(() => _rimanenti = nuoviRimanenti);
    }

    if (_rimanenti == 0) {
      _t?.cancel();
      if (_alarmTimer == null || !_alarmTimer!.isActive) {
        _avviaSvegliaInfinita();
      }
    }
  }

  void _avviaSvegliaInfinita() async {
    Future<void> playCue() async {
      SystemSound.play(SystemSoundType.alert);
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(duration: 1000, amplitude: 255);
      }
    }

    await playCue();

    _alarmTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      playCue();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _alarmTimer?.cancel();
    Vibration.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _rimanenti ~/ 60;
    final s = _rimanenti % 60;
    final isAllarme = _rimanenti == 0;

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(30),
      height: 280,
      child: Column(
        children: [
          Text(
            isAllarme ? 'SVEGLIA! TOCCA A TE!' : 'RECUPERO IN CORSO',
            style: TextStyle(letterSpacing: 2, color: isAllarme ? Colors.redAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: isAllarme ? Colors.redAccent : Colors.white),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isAllarme ? Colors.redAccent : Colors.deepOrange,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              isAllarme ? 'STOP E CHIUDI' : 'SALTA TIMER',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class PlateCalculatorWidget extends StatefulWidget {
  const PlateCalculatorWidget({super.key});

  @override
  State<PlateCalculatorWidget> createState() => _PlateCalculatorWidgetState();
}

class _PlateCalculatorWidgetState extends State<PlateCalculatorWidget> {
  final TextEditingController _p = TextEditingController();
  double bil = 20.0;
  List<double> dischi = [];

  void _calc() {
    final tot = double.tryParse(_p.text.replaceAll(',', '.')) ?? 0;
    dischi.clear();
    if (tot <= bil) {
      setState(() {});
      return;
    }
    var lato = (tot - bil) / 2;
    for (final d in [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]) {
      while (lato >= d) {
        dischi.add(d);
        lato -= d;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PLATE CALCULATOR 🏋️', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 8),
          const Text('Peso da caricare per ogni lato del bilanciere', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _p,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Peso Totale (kg)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.fitness_center)),
                  onChanged: (v) => _calc(),
                ),
              ),
              const SizedBox(width: 15),
              DropdownButton<double>(
                value: bil,
                items: [20.0, 15.0, 10.0].map((e) => DropdownMenuItem(value: e, child: Text('Bil. ${e}kg'))).toList(),
                onChanged: (v) {
                  setState(() {
                    bil = v!;
                    _calc();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 30),
          if (dischi.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: dischi
                  .map(
                    (d) => Column(
                      children: [
                        CircleAvatar(
                          radius: 25 + (d / 2),
                          backgroundColor: d >= 20
                              ? Colors.red.shade900
                              : (d == 15
                                    ? Colors.amber.shade800
                                    : (d == 10 ? Colors.green.shade800 : Colors.grey.shade800)),
                          child: Text(d.toString().replaceAll('.0', ''), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        const SizedBox(height: 4),
                        Text('${d}kg', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  )
                  .toList(),
            )
          else if (_p.text.isNotEmpty)
            const Text('Carica solo il bilanciere!', style: TextStyle(color: Colors.amber)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
