import 'dart:async';
import 'dart:math';

import 'package:emotion_detection/native/model_runtime.dart';
import 'package:face_camera/face_camera.dart';
//import 'package:face_expression_package/src/AIHException.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imagelib;
import 'dart:io';

import '../utility/utility.dart';

/// The [EmotionDetectionController] holds all the logic of a face expression detection plugin, developed by AIHP
class EmotionDetectionController {
  static const method_channel_name = "face_emotion_detection";
  static const MethodChannel _methodChannel =
      MethodChannel(method_channel_name);
  static ModelRuntime modelLoader = ModelRuntime(method_channel_name);

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
    ),
  );

  Rect? faceRect;
  imagelib.Image? faceImage;
  List<int> history = [];
  int windowSize = 5;
  final Map<String, int> emotionMap = {
    "Anger": 0,
    "Disgust": 1,
    "Fear": 2,
    "Happiness": 3,
    "Neutral": 4,
    "Sadness": 5,
    "Surprise": 6
  };
  final List<String> emotions = [
    "Anger",
    "Disgust",
    "Fear",
    "Happiness",
    "Neutral",
    "Sadness",
    "Surprise"
  ];

  /// Process the image using apple vision and return the requested information or null value
  ///
  /// [image] as Uint8List is the image that needs to be processed
  /// this needs to be in an image format raw will not work.
  ///
  /// [imageSize] as Size is the size of the image that is being processed
  ///
  /// [orientation] The orientation of the image
  Future<Map?> processImage(InputImage image, faces) async {
    try {
      //final faces = await _faceDetector.processImage(image);
      if (faces.isNotEmpty) {
        //faceData = await emotionDetectionController.processImage(inputImage.bytes!, inputImage.metadata!.size);
        final nv21Image = convertNV21(
            image.bytes!,
            image.metadata!.size.width.toInt(),
            image.metadata!.size.height.toInt());
        final maxBoxIndex = findLargestBoundingBoxIndex(faces);
        print("maxFaceIndex: $maxBoxIndex");
        faceRect = faces[maxBoxIndex].boundingBox;

        faceImage = imagelib.copyCrop(
            nv21Image,
            faceRect!.left.toInt(),
            faceRect!.top.toInt(),
            faceRect!.width.toInt(),
            faceRect!.height.toInt());
        //faceImage = imagelib.flipHorizontal(faceImage!);
        //faceImage = imagelib.copyResize(faceImage!, width:48, height:48);

        final InputImageMetadata imageMeta = image.metadata!;
        double width = imageMeta.size.width, height = imageMeta.size.height;
        print("Rotated: ${imageMeta.rotation} width:$width height: $height");
        if (imageMeta.rotation == InputImageRotation.rotation270deg ||
            imageMeta.rotation == InputImageRotation.rotation90deg) {
          width = height;
          height = imageMeta.size.width;
        }
        Face face = faces[maxBoxIndex];

        List<List<int>> landmarks = [];
        bool shouldContinue = true;
        final leftEye = face.contours[FaceContourType.leftEye];
        final rightEye = face.contours[FaceContourType.rightEye];
        final upperLip = face.contours[FaceContourType.upperLipTop];
        final lowerLip = face.contours[FaceContourType.lowerLipBottom];
        if (leftEye != null &&
            rightEye != null &&
            (upperLip != null || lowerLip != null)) {
          final leftEyeBx = findMinMax(leftEye.points);
          if (leftEyeBx != null) {
            //print("adding left eye");
            landmarks.add(leftEyeBx);
          } else {
            shouldContinue = false;
          }
          if (shouldContinue) {
            final rightEyeBx = findMinMax(rightEye.points);
            if (rightEyeBx != null) {
              //print("adding right eye");
              landmarks.add(rightEyeBx);
            } else {
              shouldContinue = false;
            }
          }
          if (shouldContinue) {
            List<Point<int>> mouthPoints = [];
            if (upperLip != null && upperLip.points != null) {
              //upperLipBx =  findMinMax(upperLip.points);
              mouthPoints.addAll(upperLip.points);
            }
            if (lowerLip != null && lowerLip.points != null) {
              mouthPoints.addAll(lowerLip.points);
            }

            final mouthBx = findMinMax(mouthPoints);
            if (mouthBx != null) {
              landmarks.add(mouthBx);
            } else {
              shouldContinue = false;
            }
          }
        }
        print("landmark length: ${landmarks.length}");

        if (Platform.isIOS) {
          final dataMap = await _methodChannel.invokeMethod<dynamic>(
            'faceEmotion',
            {
              'image': image.bytes,
              'width': imageMeta.size.width,
              'height': imageMeta.size.height,
              'left': faceRect!.left.toInt(),
              'top': faceRect!.top.toInt(),
              'boxwidth': faceRect!.width.toInt(),
              'boxheight': faceRect!.height.toInt(),
              'landmarks': landmarks
            },
          );
          return dataMap;
        } else {
          final dataMap = await _methodChannel.invokeMethod<dynamic>(
            'faceEmotion',
            {
              'faceImageData': imagelib.encodePng(faceImage!),
              'width': width,
              'height': height,
              'left': faceRect!.left.toInt(),
              'top': faceRect!.top.toInt(),
              'boxwidth': faceRect!.width.toInt(),
              'boxheight': faceRect!.height.toInt(),
            },
          );
          return dataMap;
        }
        /*var emotionString = getEmotion(data);
        if (emotionString == 'Neutral') return '';*/
        // return data;
      }
    } catch (e) {
      debugPrint('$e');
    }

    return null;
  }

  String? getEmotion(List<double> probability) {
    if (probability == null || probability.length <= 0) return 'None';
    var max = 0.0;
    var idx = 0;
    for (int i = 1; i < probability.length; i++) {
      if (probability[i] > max) {
        max = probability[i];
        idx = i;
      }
    }
    return getEmotionFromIndex(idx);
  }

  String getEmotionString(Map? emotions) {
    if (emotions == null) return "";
    double max = 0;
    String emotionStr = "";
    for (var emotion in emotions.entries) {
      if (emotion.value > max) {
        emotionStr = emotion.key;
        max = emotion.value;
      }
    }
    print("emotion $emotionStr , map: $emotions ");
    if (history.length >= windowSize) {
      history.removeAt(0);
    } else if (history.length < windowSize) {
      return emotionStr;
    }
    final maxId = emotionMap[emotionStr];
    history.add(maxId!);
    final finalId = majorityVote(history, windowSize: windowSize);
    emotionStr = emotions[finalId];
    print("final emotion: $emotionStr");
    return emotionStr;
  }

  String? getEmotionFromIndex(int index) {
    if (index < 0 || index > emotions.length) return null;
    return emotions[index];
  }
}

int majorityVote(List<int> emotionIds, {int windowSize = 5}) {
  if (emotionIds.isEmpty) return -1; // Return -1 if the list is empty.

  // Use the last `windowSize` elements or all if fewer available.
  int startIndex = max(0, emotionIds.length - windowSize);
  List<int> window = emotionIds.sublist(startIndex);

  // Count occurrences for each emotion ID.
  Map<int, int> counts = {};
  for (int id in window) {
    counts[id] = (counts[id] ?? 0) + 1;
  }

  // Find the emotion with the highest count.
  int majorityEmotion =
      counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  return majorityEmotion;
}

/// This function computes the majority vote from the last few frame predictions.

/// Returns the final emotion based on majority vote over the last few frames.
/// [predictions] is a list where each element is a map of emotion names to their probabilities.
String majorityVote2(List<Map<String, double>> predictions) {
  if (predictions.isEmpty) {
    return '';
  }

  // Use a sliding window: last 5 frames or fewer if not enough frames.
  int windowSize = min(5, predictions.length);
  List<Map<String, double>> windowFrames =
      predictions.sublist(predictions.length - windowSize);

  // For each frame, compute the emotion with the maximum probability.
  List<String> votes = [];
  for (var frame in windowFrames) {
    // Determine the emotion with the highest probability in the frame.
    String bestEmotion = frame.entries
        .reduce(
          (a, b) => a.value >= b.value ? a : b,
        )
        .key;
    votes.add(bestEmotion);
  }

  // Tally the votes.
  Map<String, int> frequency = {};
  for (String vote in votes) {
    frequency[vote] = (frequency[vote] ?? 0) + 1;
  }

  // Select the emotion with the highest count.
  String finalEmotion = frequency.entries
      .reduce(
        (a, b) => a.value >= b.value ? a : b,
      )
      .key;

  return finalEmotion;
}

/// A class that converts the information from apple vision to dart
class EmotionDetectionFunctions {
  /// Convert rect data from apple vision to usable dart data
  static List<Rect> getFaceDataFromList(List<Object?> faces) {
    List<Rect> data = [];
    for (int i = 0; i < faces.length; i++) {
      Map map = faces[i] as Map;
      data.add(Rect.fromCenter(
          center: Offset(map['origin']['x'], map['origin']['y']),
          width: map['width'],
          height: map['height']));
    }

    return data;
  }
}

int findLargestBoundingBoxIndex(List<Face> faces) {
  int maxIndex = 0;
  Rect maxRect = const Offset(0, 0) & const Size(0, 0);
  for (var i = 0; i < faces.length; i++) {
    if (faces[i].boundingBox.width * faces[i].boundingBox.height >
        maxRect.width * maxRect.height) {
      maxRect = faces[i].boundingBox;
      maxIndex = i;
    }
  }
  return maxIndex;
}

List<int>? findMinMax(List<Point<int>>? points) {
  if (points == null) return null;
  if (points.isEmpty) return null; // Return null for an empty list
  //print(points);

  // Initialize min and max values with the first point
  int minX = points[0].x;
  int minY = points[0].y;
  int maxX = points[0].x;
  int maxY = points[0].y;

  // Iterate through the points
  for (var point in points) {
    minX = point.x < minX ? point.x : minX;
    minY = point.y < minY ? point.y : minY;
    maxX = point.x > maxX ? point.x : maxX;
    maxY = point.y > maxY ? point.y : maxY;
  }

  return [minX, minY, maxX, maxY];
//  return {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY};
}

extension FaceExtension on Face {
  Future<Uint8List> getFaceFromImage(File imageFile) async {
    final image = await imageFile.readAsBytes();
    final decodedImage = imagelib.decodeImage(image);

    final rectangle = this.boundingBox;

    final face = imagelib.copyCrop(
      decodedImage!,
      rectangle.topLeft.dx.toInt(),
      rectangle.topLeft.dy.toInt(),
      rectangle.width.toInt(),
      rectangle.height.toInt(),
    );

    return Uint8List.fromList(imagelib.encodePng(face));
  }
}
