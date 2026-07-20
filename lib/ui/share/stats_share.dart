import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Injectable sink for the captured PNG. The real implementation
/// ([shareBytesAsPng]) writes a temp file and opens the OS share sheet; tests
/// pass a fake to assert behaviour without touching the platform.
typedef SharePng = Future<void> Function(Uint8List pngBytes, {String? text});

/// Rasterises the [RepaintBoundary] behind [key] to PNG bytes at [pixelRatio].
///
/// Device-verify only: [RenderRepaintBoundary.toImage] needs a real rasteriser,
/// so this is deliberately kept thin and out of the widget so the widget stays
/// headlessly testable.
Future<Uint8List> capturePng(GlobalKey key, {double pixelRatio = 3.0}) async {
  final context = key.currentContext;
  if (context == null) {
    throw StateError('Share card is not mounted.');
  }
  final boundary = context.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Could not encode the share image.');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// The real share sink: writes [pngBytes] to a temporary PNG and hands it to
/// the platform share sheet, optionally with accompanying [text].
Future<void> shareBytesAsPng(Uint8List pngBytes, {String? text}) async {
  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}/rise_stats_${DateTime.now().millisecondsSinceEpoch}.png';
  final file = await File(path).writeAsBytes(pngBytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text),
  );
}

/// Captures the card behind [key] and hands the PNG to [share] (the real share
/// sheet by default). Thin orchestration so the widget layer stays declarative
/// and this — the only non-headless-testable step — lives in one place.
Future<void> captureAndShare(
  GlobalKey key, {
  String? text,
  double pixelRatio = 3.0,
  SharePng share = shareBytesAsPng,
}) async {
  final bytes = await capturePng(key, pixelRatio: pixelRatio);
  await share(bytes, text: text);
}
