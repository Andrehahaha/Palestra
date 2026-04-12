void main() {
  final r = RegExp(r'(?:\bweek\b|\bsettimana\b|\bw\s*\d+)', caseSensitive: false);
  print(r.hasMatch('week 1 - seduta a week 1'));
}
