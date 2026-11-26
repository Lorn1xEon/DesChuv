import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

// Аудіо завантажується ДО гри та зберігається у тимчасовому кеші пристрою.
class DeezerService {
  Future<String> cachedPreview(Track track) async {
    final cache = Directory('${(await getTemporaryDirectory()).path}/deschuv_audio');
    if (!await cache.exists()) await cache.create(recursive: true);
    final file = File('${cache.path}/${track.id}.mp3');
    if (await file.exists() && await file.length() > 20000) return file.path;

    final metadata = await http.get(
      Uri.https('api.deezer.com', '/track/${track.id}'),
    ).timeout(const Duration(seconds: 15));
    if (metadata.statusCode != 200) throw Exception('Deezer: HTTP ${metadata.statusCode}');
    final json = jsonDecode(metadata.body);
    if (json is! Map || json['preview'] is! String || (json['preview'] as String).isEmpty) {
      throw Exception('Прев’ю недоступне');
    }
    final audio = await http.get(Uri.parse(json['preview'] as String))
        .timeout(const Duration(seconds: 20));
    if (audio.statusCode != 200 || audio.bodyBytes.length < 20000) {
      throw Exception('Не вдалося завантажити аудіо');
    }
    await file.writeAsBytes(audio.bodyBytes, flush: true);
    return file.path;
  }
}
