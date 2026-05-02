import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import 'camera_view.dart';
import 'gallery_view.dart';

enum DetectorViewMode { liveFeed, gallery }

class DetectorViewController extends ChangeNotifier {
  Future<String>? Function()? _takePicture;

  Future<String>? takePicture() => _takePicture?.call();

  void _attach({Future<String>? Function()? takePicture}) {
    _takePicture = takePicture;
  }

  void _detach() {
    _takePicture = null;
  }
}

class DetectorView extends StatefulWidget {
  DetectorView({
    super.key,
    required this.detectorViewController,
    required this.title,
    required this.onImage,
    required this.onSnapShot,
    this.customPaint,
    this.text,
    this.initialDetectionMode = DetectorViewMode.liveFeed,
    this.initialCameraLensDirection = CameraLensDirection.back,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
  });

  final String title;
  final CustomPaint? customPaint;
  final String? text;
  final DetectorViewMode initialDetectionMode;
  final Function(InputImage inputImage) onImage;
  final Function()? onCameraFeedReady;
  final Function(DetectorViewMode mode)? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;
  final Function() onSnapShot;

  final DetectorViewController detectorViewController;

  final CameraViewController cameraViewController = CameraViewController();

  @override
  State<DetectorView> createState() => _DetectorViewState();
}

class _DetectorViewState extends State<DetectorView> {
  late DetectorViewMode _mode;

  @override
  void initState() {
    _mode = widget.initialDetectionMode;
    widget.detectorViewController._attach(
      takePicture: widget.cameraViewController.takePicture,
    );
    super.initState();
  }

  @override
  void dispose() {
    widget.detectorViewController._detach();
    super.dispose();
  }

  void setTitle(String title) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _mode == DetectorViewMode.liveFeed
        ? CameraView(
            cameraViewController: widget.cameraViewController,
            customPaint: widget.customPaint,
            onImage: widget.onImage,
            onSnapShot: widget.onSnapShot,
            onCameraFeedReady: widget.onCameraFeedReady,
            onDetectorViewModeChanged: _onDetectorViewModeChanged,
            initialCameraLensDirection: widget.initialCameraLensDirection,
            onCameraLensDirectionChanged: widget.onCameraLensDirectionChanged,
            title: widget.text,
            showTitle: true,
          )
        : GalleryView(
            title: widget.title,
            text: widget.text,
            onImage: widget.onImage,
            onDetectorViewModeChanged: _onDetectorViewModeChanged);
  }

  void _onDetectorViewModeChanged() {
    if (_mode == DetectorViewMode.liveFeed) {
      _mode = DetectorViewMode.gallery;
    } else {
      _mode = DetectorViewMode.liveFeed;
    }
    if (widget.onDetectorViewModeChanged != null) {
      widget.onDetectorViewModeChanged!(_mode);
    }
    setState(() {});
  }
}
