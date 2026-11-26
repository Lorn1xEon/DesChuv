class Track {
  const Track({required this.id, required this.title, required this.artist});

  final int id; // Deezer ID, не локальний номер у списку.
  final String title;
  final String artist;

  String get label => '$artist — $title';
}
