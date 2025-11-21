import 'dart:typed_data';

import 'package:emotion_detection/extension/context_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imagelib;
import 'package:provider/provider.dart';

//import '../models/model.dart';

class EmotionDisplayScreen extends StatelessWidget {
  final imagelib.Image image;
  String emotion = '';

  EmotionDisplayScreen({Key? key, required this.image, this.emotion = ''})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    //final viewModel = Provider.of<ViewModel>(context, listen: false);
    emotion = "Emotion"; //viewModel.detectedEmotion;

    return Scaffold(
        appBar: AppBar(title: const Text('Captured Image')),
        body: Stack(children: [
          Image.memory(Uint8List.fromList(imagelib.encodePng(image!))),
          Positioned(
              top: 20,
              left: context.width / 2 - 20,
              child: Text(
                emotion,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              )),
        ]));
  }
}
