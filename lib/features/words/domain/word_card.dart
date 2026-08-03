class WordCardContent {
  const WordCardContent({
    required this.word,
    required this.phonetic,
    required this.translation,
    required this.example,
    this.exampleTranslation = '',
    required this.frequency,
    required this.reviewLabel,
    required this.position,
    required this.total,
  });

  final String word;
  final String phonetic;
  final String translation;
  final String example;
  final String exampleTranslation;
  final int frequency;
  final String reviewLabel;
  final int position;
  final int total;
}
