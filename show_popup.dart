import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'marker_info.dart';
import 'package:image/image.dart' as img;
import 'color_picker.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'survey_page_state.dart';

List<String> _units = ['㎡', 'm', '箇所', '枚', '本', '㎥', '式', 'その他'];
List<double> fontSizeList = [
  32.0,
  30.0,
  28.0,
  26.0,
  24.0,
  22.0,
  20.0,
  18.0,
  16.0,
  14.0,
  12.0,
  10.0,
  8.0,
  6.0,
  4.0,
  2.0
];

class ShowPopup extends StatefulWidget {
  // Add the _deteriorationDetails property here
  final List<Map<String, dynamic>> deteriorationDetails;
  final void Function(
    String?,
    String?,
    String?,
    String?,
    String?,
    double?,
    Color,
    Color,
    Color,
    double,
  ) onSave;
  final Function onCancel;
  final List<String> locations;
  final List<String> parts;
  final List<String> finishings;
  final List<String> deteriorations;
  final MarkerInfo markerInfo;
  final String imageId;
  final Function(File?)? onImageSelected;
  final Map<String, dynamic>? initialValues;

  ShowPopup({
    required this.onSave,
    required this.onCancel,
    required this.locations,
    required this.parts,
    required this.finishings,
    required this.deteriorations,
    required this.markerInfo,
    required this.imageId,
    required this.deteriorationDetails,
    this.onImageSelected,
    this.initialValues,
  });

  @override
  _ShowPopupState createState() => _ShowPopupState();
}

class _ShowPopupState extends State<ShowPopup> {
  String? selectedLocation;
  String? selectedPart;
  String? selectedFinishing;
  String? selectedDeterioration;
  String? selectedUnit;
  String? imageId;
  String imageUrl = "";
  File? _tempImageFile;
  File? _displayImageFile;
  String? downloadUrl;
  String? markerId;
  TextEditingController? customLocationController;
  TextEditingController? customPartController;
  TextEditingController? customFinishingController;
  TextEditingController? customDeteriorationController;
  TextEditingController? customUnitController;
  TextEditingController? quantityController;
  Color selectedTextColor = Colors.black;
  Color selectedBackgroundColor = Color(0xffff5722);
  Color selectedBorderColor = Color(0xffff5722);
  double selectedFontSize = 20.0;
  bool _isInputComplete() {
    return selectedLocation != null &&
        selectedPart != null &&
        selectedFinishing != null &&
        selectedDeterioration != null &&
        selectedUnit != null &&
        quantityController!.text.isNotEmpty &&
        ((selectedLocation == 'その他' &&
                customLocationController!.text.isNotEmpty) ||
            (selectedLocation != 'その他')) &&
        ((selectedPart == 'その他' && customPartController!.text.isNotEmpty) ||
            (selectedPart != 'その他')) &&
        ((selectedFinishing == 'その他' &&
                customFinishingController!.text.isNotEmpty) ||
            (selectedFinishing != 'その他')) &&
        ((selectedDeterioration == 'その他' &&
                customDeteriorationController!.text.isNotEmpty) ||
            (selectedDeterioration != 'その他')) &&
        ((selectedUnit == 'その他' && customUnitController!.text.isNotEmpty) ||
            (selectedUnit != 'その他'));
  }

  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    selectedLocation =
        widget.initialValues?['location'] ?? widget.markerInfo.location;
    selectedPart = widget.initialValues?['part'] ?? widget.markerInfo.part;
    selectedFinishing =
        widget.initialValues?['finishing'] ?? widget.markerInfo.finishing;
    selectedDeterioration = widget.initialValues?['deterioration'] ??
        widget.markerInfo.deterioration;
    selectedUnit = widget.initialValues?['unit'] ?? widget.markerInfo.unit;
    customLocationController =
        TextEditingController(text: widget.initialValues?['customLocation']);
    customPartController =
        TextEditingController(text: widget.initialValues?['customPart']);
    customFinishingController =
        TextEditingController(text: widget.initialValues?['customFinishing']);
    customDeteriorationController = TextEditingController(
        text: widget.initialValues?['customDeterioration']);
    customUnitController =
        TextEditingController(text: widget.initialValues?['customUnit']);
    quantityController = TextEditingController(
        text: widget.initialValues?['quantity']?.toString());
    selectedTextColor =
        widget.initialValues?['text_color'] as Color? ?? Colors.black;
    selectedBackgroundColor =
        widget.initialValues?['background_color'] as Color? ??
            Color(0xffff5722);
    selectedBorderColor = widget.initialValues?['background_color'] as Color? ??
        Color(0xffff5722);
    selectedFontSize = widget.initialValues?['font_size'] as double? ?? 20.0;
    markerId = widget.initialValues?['id'];
    imageUrl = widget.initialValues?['image_url'] ?? '';
    if (imageUrl.isNotEmpty) {
      _setImageFromUrl(imageUrl);
    }
  }

  @override
  void dispose() {
    customLocationController!.dispose();
    customPartController!.dispose();
    customFinishingController!.dispose();
    customDeteriorationController!.dispose();
    customUnitController!.dispose();
    quantityController!.dispose();
    super.dispose();
  }

  Future<File> _saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final String path =
        '${directory.path}/${DateTime.now().toIso8601String()}.jpg';
    return await imageFile.copy(path);
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final ImagePicker _picker = ImagePicker();
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxHeight: 621,
        maxWidth: 828,
        imageQuality: 85,
      );
      if (image != null) {
        final String fileExtension = extension(image.path).toLowerCase();
        if (fileExtension != ".jpg" && fileExtension != ".jpeg") {
          _handleImageError(context);
        }
        File imageFile = File(image.path);
        File resizedImageFile = await _resizeImage(imageFile);
        File localImage = await _saveImageLocally(resizedImageFile);
        setState(() {
          _tempImageFile = localImage;
          // コールバックを呼び出し
          widget.onImageSelected?.call(_tempImageFile);
        });
      }
    } catch (e) {
      _handleImageError(context);
    }
  }

  void _handleImageError(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('エラー'),
          content: Text('画像を読み込めませんでした。選択した画像が破損しているか、サポートされていない形式の可能性があります。'),
          actions: <Widget>[
            TextButton(
              child: Text('閉じる'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<File> _resizeImage(File imageFile) async {
    img.Image originalImage = img.decodeImage(imageFile.readAsBytesSync())!;
    double maxWidth = 828;
    double maxHeight = 621;
    double width = originalImage.width.toDouble();
    double height = originalImage.height.toDouble();
    double aspectRatio = width / height;

    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspectRatio;
    }
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }

    img.Image resizedImage = img.copyResize(originalImage,
        width: width.toInt(), height: height.toInt());

    File resizedImageFile = File(imageFile.path + '_resized.jpg');
    resizedImageFile.writeAsBytesSync(img.encodeJpg(resizedImage, quality: 85));

    return resizedImageFile;
  }

  Widget _customFieldIfOther(
      TextEditingController? controller, String? selectedItem) {
    if (selectedItem == 'その他') {
      return TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'その他を入力してください',
        ),
      );
    }
    return SizedBox.shrink();
  }

  Future<void> _setImageFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    final documentDirectory = await getApplicationDocumentsDirectory();
    final file = File(
        '${documentDirectory.path}/${DateTime.now().toIso8601String()}.jpg');
    await file.writeAsBytes(response.bodyBytes);
    setState(() {
      _displayImageFile = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('詳細入力'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              hint: Text('場所を選択してください'),
              value: selectedLocation,
              onChanged: (String? newValue) {
                setState(() {
                  selectedLocation = newValue;
                });
              },
              items: widget.locations
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            _customFieldIfOther(customLocationController, selectedLocation),
            DropdownButton<String>(
              hint: Text('部位を選択してください'),
              value: selectedPart,
              onChanged: (String? newValue) {
                setState(() {
                  selectedPart = newValue;
                });
              },
              items: widget.parts.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            _customFieldIfOther(customPartController, selectedPart),
            DropdownButton<String>(
              hint: Text('仕上げを選択してください'),
              value: selectedFinishing,
              onChanged: (String? newValue) {
                setState(() {
                  selectedFinishing = newValue;
                });
              },
              items: widget.finishings
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            _customFieldIfOther(customFinishingController, selectedFinishing),
            DropdownButton<String>(
              hint: Text('劣化状況を選択してください'),
              value: selectedDeterioration,
              onChanged: (String? newValue) {
                setState(() {
                  selectedDeterioration = newValue;
                });
              },
              items: widget.deteriorations
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '数量を入力してください',
              ),
            ),
            DropdownButton<String>(
              hint: Text('単位を選択してください'),
              value: selectedUnit,
              onChanged: (String? newValue) {
                setState(() {
                  selectedUnit = newValue;
                });
              },
              items: _units.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            _customFieldIfOther(customUnitController, selectedUnit),
            if (_displayImageFile == null && _tempImageFile == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () async {
                      await _pickImage(context, ImageSource.camera);
                    },
                    icon: Icon(Icons.camera_alt),
                  ),
                  IconButton(
                    onPressed: () async {
                      await _pickImage(context, ImageSource.gallery);
                    },
                    icon: Icon(Icons.photo_library),
                  ),
                ],
              ),
            if (_displayImageFile != null || _tempImageFile != null)
              Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            content: _tempImageFile != null
                                ? Image.file(_tempImageFile!)
                                : Image.network(imageUrl),
                            actions: <Widget>[
                              TextButton(
                                child: Text('閉じる'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: Text(_tempImageFile != null
                        ? basename(_tempImageFile!.path)
                        : basename(_displayImageFile!.path)),
                  ),
                  IconButton(
                    onPressed: () async {
                      if (widget.initialValues?['image_url'] != null) {
                        Reference oldImageRef = _storage
                            .refFromURL(widget.initialValues?['image_url']);
                        await oldImageRef.delete();
                        QuerySnapshot snapshot = await FirebaseFirestore
                            .instance
                            .collection('deteriorationDetails')
                            .where('id', isEqualTo: widget.initialValues?['id'])
                            .get();
                        if (snapshot.docs.isNotEmpty) {
                          DocumentReference docRef =
                              snapshot.docs.first.reference;
                          await docRef
                              .update({"image_url": FieldValue.delete()});
                        }
                        widget.initialValues?['image_url'] = null;
                      }
                      setState(() {
                        widget.onImageSelected?.call(null);
                        imageUrl = "";
                        _displayImageFile = null;
                        _tempImageFile = null;
                        // _deleteMarker(markerId);
                      });
                    },
                    icon: Icon(Icons.delete),
                  ),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("文字サイズ"),
                DropdownButton<double>(
                  value: selectedFontSize,
                  onChanged: (double? newValue) {
                    setState(() {
                      selectedFontSize = newValue!;
                    });
                  },
                  items: fontSizeList.map<DropdownMenuItem<double>>(
                    (double value) {
                      return DropdownMenuItem<double>(
                        value: value,
                        child: Text(value.toString()),
                      );
                    },
                  ).toList(),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('文字色を選択してください'),
                          content: SingleChildScrollView(
                            child: CustomColorPicker(
                              color: selectedTextColor,
                              onColorChanged: (Color color) {
                                setState(() {
                                  selectedTextColor = color;
                                });
                              },
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Text(
                    "文字色",
                    style: TextStyle(color: selectedTextColor),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('背景色を選択してください'),
                          content: SingleChildScrollView(
                            child: CustomColorPicker(
                              color: selectedBackgroundColor,
                              onColorChanged: (Color color) {
                                setState(() {
                                  selectedBackgroundColor = color;
                                });
                              },
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Text(
                    "背景色",
                    style: TextStyle(color: selectedBackgroundColor),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('線色を選択してください'),
                          content: SingleChildScrollView(
                            child: CustomColorPicker(
                              color: selectedBorderColor,
                              onColorChanged: (Color color) {
                                setState(() {
                                  selectedBorderColor = color;
                                });
                              },
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Text(
                    "線色",
                    style: TextStyle(color: selectedBorderColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('閉じる'),
        ),
        TextButton(
          onPressed: _isInputComplete()
              ? () {
                  double? parsedQuantity =
                      double.tryParse(quantityController!.text);
                  widget.onSave(
                    selectedLocation == 'その他'
                        ? customLocationController!.text
                        : selectedLocation,
                    selectedPart == 'その他'
                        ? customPartController!.text
                        : selectedPart,
                    selectedFinishing == 'その他'
                        ? customFinishingController!.text
                        : selectedFinishing,
                    selectedDeterioration == 'その他'
                        ? customDeteriorationController!.text
                        : selectedDeterioration,
                    selectedUnit == 'その他'
                        ? customUnitController!.text
                        : selectedUnit,
                    parsedQuantity,
                    selectedTextColor,
                    selectedBackgroundColor,
                    selectedBorderColor,
                    selectedFontSize,
                  );
                  Navigator.of(context).pop();
                }
              : null,
// 入力が完了していない場合、ボタンを非アクティブにする
          child: Text('保存'),
        ),
      ],
    );
  }
}
