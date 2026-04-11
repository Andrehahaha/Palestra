import 'package:flutter/material.dart';

class ProfileHomeSection extends StatelessWidget {
  const ProfileHomeSection({
    super.key,
    required this.nomeUtente,
    required this.sessioniRegistrate,
    required this.serieCompletate,
    required this.onApriGrafici,
    required this.onApriLibreria,
    required this.onApriDati,
  });

  final String nomeUtente;
  final int sessioniRegistrate;
  final int serieCompletate;
  final VoidCallback onApriGrafici;
  final VoidCallback onApriLibreria;
  final VoidCallback onApriDati;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.deepOrange,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        nomeUtente.isEmpty
                            ? 'Il tuo profilo atleta'
                            : nomeUtente,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Sessioni registrate: $sessioniRegistrate • Serie completate: $serieCompletate',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ProfileSectionTile(
          icona: Icons.analytics_outlined,
          titolo: 'Grafici e andamento',
          descrizione:
              'Calendario allenamenti, curva della forza e distribuzione muscolare.',
          onTap: onApriGrafici,
        ),
        _ProfileSectionTile(
          icona: Icons.menu_book_outlined,
          titolo: 'Libreria esercizi',
          descrizione:
              'Cerca esercizi, visualizza dettagli e gestisci quelli personalizzati.',
          onTap: onApriLibreria,
        ),
        _ProfileSectionTile(
          icona: Icons.badge_outlined,
          titolo: 'Dati personali',
          descrizione:
              'Aggiorna misure, note obiettivi e preferenze di calcolo carichi.',
          onTap: onApriDati,
        ),
      ],
    );
  }
}

class _ProfileSectionTile extends StatelessWidget {
  const _ProfileSectionTile({
    required this.icona,
    required this.titolo,
    required this.descrizione,
    required this.onTap,
  });

  final IconData icona;
  final String titolo;
  final String descrizione;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icona, color: Colors.deepOrange, size: 28),
        title: Text(
          titolo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(descrizione),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
