import 'package:deschuv/models/track.dart';
import 'package:deschuv/services/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Track label contains artist and title', () {
    const track = Track(id: 1, title: 'Title', artist: 'Artist');
    expect(track.label, 'Artist — Title');
  });

  test('Catalog contains enough unique tracks for ten rounds', () {
    expect(demoTracks.length, greaterThanOrEqualTo(10));
    expect(demoTracks.map((track) => track.id).toSet().length,
        demoTracks.length);
    for (final track in demoTracks) {
      expect(track.id, greaterThan(0));
      expect(track.title.trim(), isNotEmpty);
      expect(track.artist.trim(), isNotEmpty);
    }
  });
}
