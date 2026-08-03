import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures whatever [repaintKey] is attached to (wrap the screen's root
/// widget in a `RepaintBoundary` with this key) and opens the OS share sheet
/// with the resulting PNG. Used by every health detail screen's "Share"
/// menu item.
Future<void> shareScreenshot(GlobalKey repaintKey, {required String text}) async {
  try {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vital_screenshot.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    await Share.shareXFiles([XFile(file.path)], text: text);
  } catch (_) {}
}
