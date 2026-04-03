import 'serie.dart';
import '../services/workload_calculator.dart';

class Esercizio {
  final String nome;
  final int avvicinamento;
  final int workingSet;
  final String ripetizioni;
  final String recupero;
  final String? note;
  final List<String> tecniche; 
  String modalitaIntensita;
  String? rirTarget;
  double? percentualeMassimale;
  double? massimaleKg;
  double? caricoTargetKg;
  List<Serie> serieAttive;

  Esercizio({
    required this.nome,
    required this.avvicinamento,
    required this.workingSet,
    required this.ripetizioni,
    required this.recupero,
    this.note,
    this.tecniche = const ['Classico'], 
    this.modalitaIntensita = 'rir',
    this.rirTarget,
    this.percentualeMassimale,
    this.massimaleKg,
    this.caricoTargetKg,
    List<Serie>? serieAttive,
  }) : serieAttive = serieAttive ?? [];

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'avvicinamento': avvicinamento,
      'workingSet': workingSet,
      'ripetizioni': ripetizioni,
      'recupero': recupero,
      'note': note,
      'tecniche': tecniche,
      'modalitaIntensita': modalitaIntensita,
      'rirTarget': rirTarget,
      'percentualeMassimale': percentualeMassimale,
      'massimaleKg': massimaleKg,
      'caricoTargetKg': caricoTargetKg,
      'serieAttive': serieAttive.map((s) => s.toJson()).toList(),
    };
  }

  factory Esercizio.fromJson(Map<String, dynamic> json) {
    int avv = json['avvicinamento'] ?? 0;
    int work = json['workingSet'] ?? 3;
    
    // LOGICA PUNTO 3: Creazione automatica delle righe
    List<Serie> serieGenerate = [];
    
    // Se nel JSON non ci sono serie salvate, le creiamo noi basandoci sui numeri
    if (json['serieAttive'] == null || (json['serieAttive'] as List).isEmpty) {
      for (int i = 0; i < avv; i++) {
        serieGenerate.add(Serie(tipo: 'Avvicinamento'));
      }
      for (int i = 0; i < work; i++) {
        serieGenerate.add(Serie(tipo: 'Working Set'));
      }
    }

    final modalita = json['modalitaIntensita'] ?? 'rir';
    final percentuale = _toDoubleOrNull(json['percentualeMassimale']);
    final massimale = _toDoubleOrNull(json['massimaleKg']);
    final caricoJson = _toDoubleOrNull(json['caricoTargetKg']);
    final caricoCalcolato = (modalita == 'percentuale' &&
            caricoJson == null &&
            percentuale != null &&
            massimale != null)
        ? WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: massimale,
            percentage: percentuale,
          )
        : caricoJson;

    final serieFinali = json['serieAttive'] != null && (json['serieAttive'] as List).isNotEmpty
        ? (json['serieAttive'] as List).map((e) => Serie.fromJson(e)).toList()
        : serieGenerate;

    if (modalita == 'percentuale' && percentuale != null) {
      final percentText = percentuale.toStringAsFixed(percentuale % 1 == 0 ? 0 : 1);
      for (final s in serieFinali.where((s) => s.tipo != 'Avvicinamento')) {
        if (s.percentualeTarget.trim().isEmpty) {
          s.percentualeTarget = percentText;
        }
      }
    }

    return Esercizio(
      nome: json['nome'] ?? 'Esercizio',
      avvicinamento: avv,
      workingSet: work,
      ripetizioni: json['ripetizioni'] ?? '',
      recupero: json['recupero'] ?? '',
      note: json['note'],
      tecniche: json['tecniche'] != null ? List<String>.from(json['tecniche']) : ['Classico'],
      modalitaIntensita: modalita,
      rirTarget: json['rirTarget'],
      percentualeMassimale: percentuale,
      massimaleKg: massimale,
      caricoTargetKg: caricoCalcolato,
      serieAttive: serieFinali,
    );
  }

  static double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}