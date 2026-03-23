import 'package:flutter/foundation.dart';

const List<String> zoneDolore = [
  'Collo',
  'Spalle',
  'Schiena alta',
  'Lombare',
  'Anca',
  'Ginocchio',
  'Polso',
  'Caviglia',
];

const String zonaStretchingSharedKey = 'zona_stretching_condivisa';

final ValueNotifier<String> zonaStretchingNotifier = ValueNotifier<String>('Lombare');

void aggiornaZonaStretchingCondivisa(String zona) {
  if (!zoneDolore.contains(zona)) return;
  if (zonaStretchingNotifier.value != zona) {
    zonaStretchingNotifier.value = zona;
  }
}

const Map<String, Map<String, List<String>>> consigliDolore = {
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

List<String> stretchingPerZona(String zona) {
  return consigliDolore[zona]?['stretching'] ?? const [];
}

List<String> eserciziPerZona(String zona) {
  return consigliDolore[zona]?['esercizi'] ?? const [];
}
