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

  static const _orange = Color(0xFFFF6B1A);
  static const _red = Color(0xFFCC1A1A);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // ── Profile Card ──────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: _orange.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_red, _orange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeUtente.isEmpty ? 'Atleta' : nomeUtente,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$sessioniRegistrate sessioni • $serieCompletate serie',
                      style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Section Label ──────────────────────────────────────
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'SEZIONI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF555555),
              letterSpacing: 2,
            ),
          ),
        ),

        // ── Navigation Tiles ───────────────────────────────────
        _ProfileSectionTile(
          icona: Icons.analytics_outlined,
          titolo: 'Grafici e andamento',
          descrizione: 'Calendario, curva della forza e distribuzione muscolare.',
          accentColor: _orange,
          onTap: onApriGrafici,
        ),
        const SizedBox(height: 10),
        _ProfileSectionTile(
          icona: Icons.menu_book_outlined,
          titolo: 'Libreria esercizi',
          descrizione: 'Cerca esercizi, visualizza dettagli e gestisci quelli custom.',
          accentColor: const Color(0xFF4A90D9),
          onTap: onApriLibreria,
        ),
        const SizedBox(height: 10),
        _ProfileSectionTile(
          icona: Icons.badge_outlined,
          titolo: 'Dati personali',
          descrizione: 'Misure, obiettivi e preferenze di calcolo carichi.',
          accentColor: const Color(0xFF4CAF50),
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
    required this.accentColor,
    required this.onTap,
  });

  final IconData icona;
  final String titolo;
  final String descrizione;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icona, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titolo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descrizione,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}
