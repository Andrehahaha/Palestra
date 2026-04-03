class WorkloadCalculator {
  static double calculateFromMaxAndPercentage({
    required double oneRepMax,
    required double percentage,
  }) {
    if (oneRepMax <= 0 || percentage <= 0) return 0;
    final raw = oneRepMax * (percentage / 100);

    // Arrotondamento pratico al mezzo chilo.
    return (raw * 2).roundToDouble() / 2;
  }
}
