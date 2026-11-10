import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/diary.dart';

/// Adding a picture to a diary — spec §6.2.
///
/// - Only from the phone's photo library (the system picker; no permission to read the whole library).
/// - Whatever the original size: height = 1/3 of the screen height, width by the original ratio;
///   if that is wider than the screen, width = screen width instead. The stored file *is* the
///   shrunk one; zooming in later shows that same file.
/// - Turned upright by its orientation tag first, then saved as JPEG without EXIF (no location).
class ImageService {
  ImageService(this.store, {ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final Store store;
  final ImagePicker _picker;

  static const quality = 85;

  /// Picks one picture and stores it. [screen] is the screen size in physical pixels.
  /// Returns null when the user backs out of the picker.
  Future<ImageRef?> pick(ui.Size screen) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (picked == null) return null;
    return storeShrunk(await picked.readAsBytes(), screen);
  }

  /// The pixel size to store a [width]×[height] (upright) picture at on a [screen]-sized display.
  static ({int width, int height}) targetSize(int width, int height, ui.Size screen) {
    var h = screen.height / 3;
    var w = width * h / height;
    if (w > screen.width) {
      w = screen.width;
      h = height * w / width;
    }
    // Never enlarge a picture that is already smaller.
    if (h > height) return (width: width, height: height);
    return (width: w.round().clamp(1, width), height: h.round().clamp(1, height));
  }

  Future<ImageRef> storeShrunk(Uint8List original, ui.Size screen) async {
    // Pass 1: upright it and drop EXIF without resizing. The plugin resizes *before* rotating and
    // only knows the raw (unrotated) size, so the exact target can only be computed afterwards.
    final upright = await FlutterImageCompress.compressWithList(
      original,
      minWidth: 1 << 15,
      minHeight: 1 << 15,
      quality: 95,
      autoCorrectionAngle: true,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    final size = await _decodeSize(upright);
    final target = targetSize(size.width, size.height, screen);
    // Pass 2: resize. The plugin divides both sides by max(1, min(width/minWidth, height/minHeight)),
    // so giving both target sides (same ratio as the picture) lands on the target.
    final shrunk = await FlutterImageCompress.compressWithList(
      upright,
      minWidth: target.width,
      minHeight: target.height,
      quality: quality,
      autoCorrectionAngle: false,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    final finalSize = await _decodeSize(shrunk);
    final id = Store.newId();
    final file = store.imageFile(id);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(shrunk, flush: true);
    return ImageRef(id, finalSize.width, finalSize.height);
  }

  static Future<({int width, int height})> _decodeSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
}
