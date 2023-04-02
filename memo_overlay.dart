import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MemoOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final String surveyId;
  final String drawingId;
  final String imageId;

  MemoOverlay(
      {required this.onClose,
      required this.surveyId,
      required this.drawingId,
      required this.imageId});

  @override
  _MemoOverlayState createState() => _MemoOverlayState();
}

class _MemoOverlayState extends State<MemoOverlay> {
  late final TextEditingController _textEditingController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textEditingController = TextEditingController();

    FirebaseFirestore.instance
        .collection('surveys')
        .doc(widget.surveyId)
        .get()
        .then((snapshot) {
      final data = snapshot.data();
      final drawings = data?['drawings'] as List<dynamic>? ?? [];

      final targetDrawing = drawings.firstWhere(
          (drawing) => drawing['uuid'] == widget.imageId,
          orElse: () => null);
      if (targetDrawing != null) {
        final memo = targetDrawing['memo'] as String?;
        if (memo != null) {
          _textEditingController.text = memo;
        }
      }
    });
  }

  Future<void> _saveMemo() async {
    final memoText = _textEditingController.text;

    await FirebaseFirestore.instance
        .collection('surveys')
        .doc(widget.surveyId)
        .get()
        .then((snapshot) async {
      final data = snapshot.data();
      final drawings = data?['drawings'] as List<dynamic>? ?? [];

      final targetDrawingIndex =
          drawings.indexWhere((drawing) => drawing['uuid'] == widget.imageId);
      if (targetDrawingIndex != -1) {
        drawings[targetDrawingIndex]['memo'] = memoText;

        await FirebaseFirestore.instance
            .collection('surveys')
            .doc(widget.surveyId)
            .update({'drawings': drawings})
            .then((_) => print('Memo saved'))
            .catchError((error) => print('Failed to save memo: $error'));
      }
    });

    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            _focusNode.requestFocus();
          },
          child: Container(
            color: Colors.black54,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: EdgeInsets.only(right: 20),
            color: Colors.white,
            width: MediaQuery.of(context).size.width * 0.4,
            height: MediaQuery.of(context).size.height * 0.8,
            padding: EdgeInsets.all(16),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'メモ',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () {
                          _saveMemo();
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      textAlignVertical: TextAlignVertical.top,
                      controller: _textEditingController,
                      maxLines: null,
                      expands: true,
                      focusNode: _focusNode,
                      style: TextStyle(
                        fontSize: 14, //文字の大きさ
                        height: 0.5, //文字の大きさの0.5倍(7)を行間
                      ),
                      decoration: InputDecoration(
                        hintText: 'メモを入力してください',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
