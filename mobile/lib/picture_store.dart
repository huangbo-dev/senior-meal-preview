import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// A meal picture made earlier, kept so it can be shown again at once and
/// without a connection.
class SavedPicture {
  const SavedPicture(this.result, this.madeAt);

  final PhotoEditResult result;

  /// When the server made it (local time).
  final DateTime madeAt;
}

/// Edited pictures of the bundled meal reference photos, keyed by meal and
/// changes. Only stock reference photos are kept; photos the user takes are
/// never saved.
abstract interface class PictureStore {
  Future<SavedPicture?> read(String key);
  Future<void> write(String key, SavedPicture picture);
}

/// Keeps pictures for this run of the app only (also used by tests).
class MemoryPictureStore implements PictureStore {
  final Map<String, SavedPicture> _items = {};

  @override
  Future<SavedPicture?> read(String key) async => _items[key];

  @override
  Future<void> write(String key, SavedPicture picture) async =>
      _items[key] = picture;
}

/// Keeps pictures in the app's private support directory, so they survive a
/// restart. Failures to read or write are treated as "nothing saved".
class FilePictureStore implements PictureStore {
  final MemoryPictureStore _memory = MemoryPictureStore();

  Future<File> _file(String key) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/meal-pictures',
    );
    await dir.create(recursive: true);
    final safe = key.replaceAll(RegExp('[^a-z0-9_+.-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  @override
  Future<SavedPicture?> read(String key) async {
    final cached = await _memory.read(key);
    if (cached != null) return cached;
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final picture = SavedPicture(
        PhotoEditResult.fromJson(json['result'] as Map<String, dynamic>),
        DateTime.parse(json['made_at'] as String),
      );
      await _memory.write(key, picture);
      return picture;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, SavedPicture picture) async {
    await _memory.write(key, picture);
    try {
      await (await _file(key)).writeAsString(
        jsonEncode({
          'made_at': picture.madeAt.toIso8601String(),
          'result': picture.result.toJson(),
        }),
      );
    } catch (_) {
      // Saving is a convenience; the picture is still shown.
    }
  }
}
