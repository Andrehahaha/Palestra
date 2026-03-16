class EsercizioSuggerito {
  final String nome;
  final String categoria;

  EsercizioSuggerito(this.nome, this.categoria);
}

final List<EsercizioSuggerito> catalogoEsercizi = [
  // PETTO
  EsercizioSuggerito("Panca Piana Bilanciere", "Petto"),
  EsercizioSuggerito("Panca Inclinata Manubri", "Petto"),
  EsercizioSuggerito("Chest Press", "Petto"),
  EsercizioSuggerito("Croci ai cavi", "Petto"),
  EsercizioSuggerito("Dips (Petto)", "Petto"),
  // SCHIENA
  EsercizioSuggerito("Trazioni alla sbarra", "Schiena"),
  EsercizioSuggerito("Lat Machine Inversa", "Schiena"),
  EsercizioSuggerito("Rematore Bilanciere", "Schiena"),
  EsercizioSuggerito("Pulley basso", "Schiena"),
  EsercizioSuggerito("Pull-over ai cavi", "Schiena"),
  // GAMBE
  EsercizioSuggerito("Squat Bilanciere", "Gambe"),
  EsercizioSuggerito("Leg Press 45°", "Gambe"),
  EsercizioSuggerito("Leg Extension", "Gambe"),
  EsercizioSuggerito("Leg Curl (Sdraiato)", "Gambe"),
  EsercizioSuggerito("Stacco Rumeno", "Gambe"),
  EsercizioSuggerito("Calf Raise", "Gambe"),
  // SPALLE
  EsercizioSuggerito("Military Press", "Spalle"),
  EsercizioSuggerito("Alzate Laterali Manubri", "Spalle"),
  EsercizioSuggerito("Shoulder Press", "Spalle"),
  EsercizioSuggerito("Face Pull", "Spalle"),
  // BRACCIA
  EsercizioSuggerito("Curl Bilanciere EZ", "Bicipiti"),
  EsercizioSuggerito("Curl Hammer", "Bicipiti"),
  EsercizioSuggerito("Pushdown Tricipiti Cavi", "Tricipiti"),
  EsercizioSuggerito("French Press Bilanciere", "Tricipiti"),
];