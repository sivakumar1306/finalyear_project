import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_pill.dart';
import 'package:path_provider/path_provider.dart';

/// Ring-controlled camera screen.
///
/// On open: tells the ring to enter its camera UI (BleProvider.enterRingCameraMode(),
/// which fires BlePlugin.kt's takePicture() — ACTION_INTO_CAMARA_UI + the native
/// ACTION_KEEP_SCREEN_ON keep-alive loop) and shows a live phone camera preview.
///
/// While open, it listens to BleProvider.cameraShutterEvents for:
///   - "capture": the ring's physical shutter gesture was used — take a photo.
///   - "exit":    the ring itself left camera mode — close this screen.
///
/// On close (any path — back button, ring-initiated exit, or dispose), it always
/// calls BleProvider.exitRingCameraMode() so the ring is told to leave its camera UI
/// and the native keep-alive loop is stopped.
class RingCameraScreen extends StatefulWidget {
  const RingCameraScreen({super.key});

  @override
  State<RingCameraScreen> createState() => _RingCameraScreenState();
}

class _RingCameraScreenState extends State<RingCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  StreamSubscription<String>? _shutterSub;
  bool _isCapturing = false;
  String? _lastPhotoPath;
  String? _error;
  bool _exited = false;
  Future<XFile>? _pendingCapture; // track in-flight capture so dispose() can wait

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _initCamera();
    context.read<BleProvider>().enterRingCameraMode();
    _shutterSub = context.read<BleProvider>().cameraShutterEvents.listen((
      action,
    ) {
      if (action == 'capture') {
        _capturePhoto();
      } else if (action == 'exit') {
        _closeScreen(tellRing: false);
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'No camera available on this device');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      setState(() => _error = 'Failed to start camera: $e');
    }
  }

  Future<void> _saveToGallery(String srcPath) async {
    try {
      final srcFile = File(srcPath);
      if (!await srcFile.exists()) return;

      Directory? targetDir;
      if (Platform.isAndroid) {
        final picturesDir = Directory('/storage/emulated/0/Pictures/SUNDR');
        if (!await picturesDir.exists()) {
          await picturesDir.create(recursive: true);
        }
        targetDir = picturesDir;
      } else if (Platform.isIOS) {
        targetDir = await getApplicationDocumentsDirectory();
      }

      if (targetDir != null) {
        final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '${targetDir.path}/$fileName';
        await srcFile.copy(destPath);
        if (Platform.isAndroid) {
          BleService().scanMediaFile(destPath);
        }
      }
    } catch (e) {
      debugPrint('Save to gallery error: $e');
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return; // already guards overlapping calls
    }
    setState(() => _isCapturing = true);
    try {
      final capture = controller.takePicture();
      _pendingCapture = capture; // track it so dispose() can wait
      final file = await capture;
      if (!mounted) return;
      setState(() => _lastPhotoPath = file.path);
      _saveToGallery(file.path);
      showGlassPill(context, 'Photo captured', type: GlassPillType.success);
    } catch (e) {
      if (!mounted) return;
      showGlassPill(context, 'Capture failed: $e', type: GlassPillType.error);
    } finally {
      _pendingCapture = null;
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _closeScreen({bool tellRing = true}) async {
    if (_exited) return;
    _exited = true;
    final ble = _bleProviderRef;
    if (_pendingCapture != null) {
      try {
        await _pendingCapture;
      } catch (e) {
        debugPrint('_closeScreen capture wait: $e');
      }
    }
    if (tellRing && ble != null) {
      try {
        await ble.exitRingCameraMode();
      } catch (e) {
        debugPrint('_closeScreen exitRingCameraMode: $e');
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initFuture = _initCamera();
      setState(() {});
    }
  }

  // Captured once (didChangeDependencies) via a stored reference so dispose()
  // can still call exitRingCameraMode() after this State has no valid context.
  BleProvider? _bleProviderRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bleProviderRef ??= context.read<BleProvider>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shutterSub?.cancel();
    // Don't dispose the controller while a capture is still pending —
    // schedule disposal after it resolves to avoid BufferQueue abandoned errors.
    final pending = _pendingCapture;
    final controller = _controller;
    if (pending != null && controller != null) {
      pending.whenComplete(() => controller.dispose());
    } else {
      controller?.dispose();
    }
    if (!_exited) {
      _exited = true;
      try {
        _bleProviderRef?.exitRingCameraMode();
      } catch (e) {
        debugPrint('dispose exitRingCameraMode: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snapshot) {
                if (_error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.inter(color: Colors.white70),
                      ),
                    ),
                  );
                }
                final controller = _controller;
                if (controller == null || !controller.value.isInitialized) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.gold),
                  );
                }
                return Center(child: CameraPreview(controller));
              },
            ),

            // Top bar
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => _closeScreen(),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Use your ring to take a photo',
                      style: AppTypography.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!context.select<BleProvider, bool>((b) => b.gestureEnabled))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 6.0,
                          left: 20.0,
                          right: 20.0,
                        ),
                        child: Text(
                          'Turn on Gesture Controls in settings to use your ring to take photos',
                          style: AppTypography.inter(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Last photo thumbnail
            if (_lastPhotoPath != null)
              Positioned(
                bottom: 24,
                left: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(_lastPhotoPath!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // Manual shutter (in case the phone user wants to trigger it too)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: _isCapturing ? 0.4 : 0.9),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
