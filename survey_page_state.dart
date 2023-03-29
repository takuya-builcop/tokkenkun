import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'show_popup.dart';
import 'survey_page.dart';
import 'fetch_dropdown_items.dart';
import 'marker_info.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'memo_overlay.dart';
import 'marker_config.dart';

class SurveyPageState extends State<SurveyPage> {
  late Image _image;
  bool _imageLoaded = false;
  List<Map<String, dynamic>> _markers = [];
  String? selectedUnit;

  List<String> locations = [];
  List<String> parts = [];
  List<String> finishings = [];
  List<String> deteriorations = [];
  List<Map<String, dynamic>> _deteriorationDetails = [];
  MarkerInfo? _markerInfo;
  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseStorage _storage = FirebaseStorage.instance;
  String downloadUrl = '';
  File? _tempImageFile;
  File? imageFile;
  int markerIndex = 0;
  MarkerConfig _markerConfig = MarkerConfig();

  void _onPopupCancel() {
    setState(() {
      _markerInfo = null;
    });
    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _image = Image.network(widget.imagePath, fit: BoxFit.contain, frameBuilder:
        (BuildContext context, Widget child, int? frame,
            bool wasSynchronouslyLoaded) {
      if (frame == null) {
        return CircularProgressIndicator();
      } else {
        if (!_imageLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _imageLoaded = true;
            });
          });
        }
        return child;
      }
    });
    _fetchDataFromFirestore();
    _fetchDeteriorationDetails();
  }

  Future<String> _uploadImage(File imageFile) async {
    String imagePath = 'deterioration/${DateTime.now().toIso8601String()}.jpg';
    Reference reference = FirebaseStorage.instance.ref().child(imagePath);
    UploadTask uploadTask = reference.putFile(imageFile);
    await uploadTask.whenComplete(() => null);
    downloadUrl = await reference.getDownloadURL();
    return downloadUrl;
  }

  void _fetchDataFromFirestore() async {
    locations = await fetchDropdownItems('Location');
    parts = await fetchDropdownItems('Part');
    finishings = await fetchDropdownItems('Finishing');
    deteriorations = await fetchDropdownItems('Deterioration');
  }

  void _deleteMarker(Map<String, dynamic> marker) async {
    int markerIndex = marker['index'];
    _markers.removeWhere((m) => m['index'] == markerIndex);
    for (int i = markerIndex; i <= _markers.length; i++) {
      _markers[i - 1]['index'] = i;
    }
    setState(() {});
    // 3. Delete the marker from Firestore
    QuerySnapshot snapshot = await _firestore
        .collection('deteriorationDetails')
        .where('index', isEqualTo: markerIndex)
        .where('drawingid', isEqualTo: widget.imageId)
        .get();
    if (snapshot.docs.isNotEmpty) {
      snapshot.docs.first.reference.delete();
    }

    // 4. Update the indexes in Firestore
    WriteBatch batch = _firestore.batch();
    for (int i = markerIndex + 1; i <= _markers.length + 1; i++) {
      QuerySnapshot snapshot = await _firestore
          .collection('deteriorationDetails')
          .where('index', isEqualTo: i)
          .where('drawingid', isEqualTo: widget.imageId)
          .get();
      if (snapshot.docs.isNotEmpty) {
        DocumentReference docRef = snapshot.docs.first.reference;
        batch.update(docRef, {'index': i - 1});
      }
    }
    await batch.commit();
  }

  void _addMarker(Offset position,
      {bool isUpdate = false, int markerIndex = -1}) async {
    setState(() {
      if (isUpdate) {
        _markerInfo = MarkerInfo(position: position, index: markerIndex);
      } else {
        _markerInfo =
            MarkerInfo(position: position, index: _markers.length + 1);
      }
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return FutureBuilder(
          future: Future.wait([
            fetchDropdownItems('Location'),
            fetchDropdownItems('Part'),
            fetchDropdownItems('Finishing'),
            fetchDropdownItems('Deterioration'),
          ]),
          builder:
              (BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return ShowPopup(
                onSave: (
                  location,
                  part,
                  finishing,
                  deterioration,
                  unit,
                  quantity,
                  selectedTextColor,
                  selectedBackgroundColor,
                  selectedBorderColor,
                  selectedFontSize,
                ) async {
                  if (_markerInfo != null) {
                    if (_tempImageFile != null) {
                      String imageUrl = await _uploadImage(_tempImageFile!);
                      // 1. Upload the image
                      String filePath =
                          'images/${DateTime.now()}_${_markerInfo!.index}.jpg';
                      TaskSnapshot snapshot =
                          await _storage.ref(filePath).putFile(_tempImageFile!);
                      // 2. Get the download URL
                      downloadUrl = await snapshot.ref.getDownloadURL();
                    }
                    setState(() {
                      selectedUnit = unit;
                      // Save or update the marker data in Firestore
                      if (isUpdate) {
                        // Update marker data in Firestore
                        _firestore
                            .collection('deteriorationDetails')
                            .doc(markerIndex
                                .toString()) // Assuming you have the marker's document ID stored as markerIndex
                            .update({
                          'position': {
                            'dx': _markerInfo!.position.dx,
                            'dy': _markerInfo!.position.dy
                          },
                          'id': _markerInfo!.index,
                          'index': markerIndex, // Use existing marker index
                          'surveyid': widget.surveyId,
                          'drawingid': widget.imageId,
                          'location': location,
                          'part': part,
                          'finishing': finishing,
                          'deterioration': deterioration,
                          'unit': unit,
                          'quantity': quantity,
                          'image_url': downloadUrl,
                          'text_color': selectedTextColor.value,
                          'background_color': selectedBackgroundColor.value,
                          'border_color': selectedBorderColor.value,
                          'font_size': selectedFontSize,
                        });
                        // Update marker data in _markers list
                        int markerListIndex = _markers.indexWhere(
                            (marker) => marker['id'] == markerIndex);
                        if (markerListIndex != -1) {
                          _markers[markerListIndex] = {
                            'position': _markerInfo!.position,
                            'id': _markerInfo!.index,
                            'index': markerIndex, // Use existing marker index
                            'text_color': selectedTextColor,
                            'background_color': selectedBackgroundColor,
                            'border_color': selectedBorderColor,
                            'font_size': selectedFontSize,
                          };
                        }
                      } else {
                        // Save new marker data to Firestore
                        _firestore.collection('deteriorationDetails').add({
                          'position': {
                            'dx': _markerInfo!.position.dx,
                            'dy': _markerInfo!.position.dy
                          },
                          'id': _markerInfo!.index,
                          'index': _markers.length + 1,
                          'surveyid': widget.surveyId,
                          'drawingid': widget.imageId,
                          'location': location,
                          'part': part,
                          'finishing': finishing,
                          'deterioration': deterioration,
                          'unit': unit,
                          'quantity': quantity,
                          'image_url': downloadUrl,
                          'text_color': selectedTextColor.value,
                          'background_color': selectedBackgroundColor.value,
                          'border_color': selectedBorderColor.value,
                          'font_size': selectedFontSize,
                        });
                        // Add new marker data to _markers list
                        _markers.add({
                          'position': _markerInfo!.position,
                          'id': _markerInfo!.index,
                          'index': _markers.length + 1,
                          'text_color': selectedTextColor,
                          'background_color': selectedBackgroundColor,
                          'border_color': selectedBorderColor,
                          'font_size': selectedFontSize,
                        });
                      }
                      _markerInfo = null;
                    });
                  }
                },
                onCancel: _onPopupCancel,
                locations: snapshot.data![0],
                parts: snapshot.data![1],
                finishings: snapshot.data![2],
                deteriorations: snapshot.data![3],
                markerInfo: _markerInfo!,
                imageId: widget.imageId,
                deteriorationDetails: _deteriorationDetails,
                onImageSelected: (File? imageFile) {
                  setState(() {
                    this.imageFile = imageFile!;
                    _tempImageFile = imageFile; // 変更箇所
                  });
                },
              );
            } else {
              return Center(child: CircularProgressIndicator());
            }
          },
        );
      },
    );
  }

  Future<void> _fetchDeteriorationDetails() async {
    QuerySnapshot querySnapshot = await _firestore
        .collection('deteriorationDetails')
        .where('surveyid', isEqualTo: widget.surveyId)
        .where('drawingid', isEqualTo: widget.imageId)
        .get();

    if (querySnapshot.docs.isEmpty) {
      setState(() {
        _deteriorationDetails = [];
        _markers = [];
      });
      return;
    }

    List<QueryDocumentSnapshot> documents = querySnapshot.docs;
    _deteriorationDetails = documents
        .map<Map<String, dynamic>>((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    _markers = _deteriorationDetails
        .map((detail) => {
              'position':
                  Offset(detail['position']['dx'], detail['position']['dy']),
              'id': detail['id'],
              'index': detail['index'],
              'text_color': Color(detail['text_color']),
              'background_color': Color(detail['background_color']),
              'border_color': Color(detail['border_color']),
              'font_size': detail['font_size'] != null
                  ? double.parse(detail['font_size'].toString())
                  : _markerConfig.fontSize,
            })
        .toList();

    setState(() {});
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Survey Page'),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: () {
              // 登録内容の確認処理をここに追加します
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5, // 最小拡大率を設定します。適切な値に調整してください。
        maxScale: 2.0, // 最大拡大率を設定します。適切な値に調整してください。
        constrained: false,
        child: FutureBuilder(
          future: precacheImage(_image.image, context),
          builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return GestureDetector(
                onTapUp: (TapUpDetails details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset position =
                      box.globalToLocal(details.globalPosition);
                  _addMarker(position, isUpdate: false);
                },
                child: Stack(
                  children: [
                    Center(child: _image),
                    ..._markers.map((marker) {
                      double containerSize = _markerConfig.fontSize + 5;
                      double borderRadius = containerSize / 2;
                      return Positioned(
                          left: marker['position'].dx - containerSize / 2,
                          top: marker['position'].dy - containerSize / 2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: marker['background_color'],
                              border: Border.all(
                                color: marker['border_color'],
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(borderRadius),
                            ),
                            height: containerSize,
                            width: containerSize,
                            child: Center(
                              child: Container(
                                width: containerSize,
                                height: containerSize,
                                child: GestureDetector(
                                  // Change InkWell to GestureDetector
                                  onLongPress: () {
                                    // Add onLongPress
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text('Confirm Delete'),
                                          content: Text(
                                              'Are you sure you want to delete this marker?'),
                                          actions: [
                                            TextButton(
                                              child: Text('Cancel'),
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            TextButton(
                                              child: Text('OK'),
                                              onPressed: () {
                                                _deleteMarker(
                                                    marker); // Replace the existing setState block with this line
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  onTap: () {
                                    // ShowPopup を表示する
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        // Get deterioration details for this marker
                                        Map<String, dynamic> markerDetails =
                                            _deteriorationDetails.firstWhere(
                                          (element) =>
                                              element['id'] == marker['id'],
                                          orElse: () => {},
                                        );

                                        // Add appropriate values to initialValues
                                        Map<String, dynamic> initialValues = {
                                          'location': markerDetails['location'],
                                          'part': markerDetails['part'],
                                          'finishing':
                                              markerDetails['finishing'],
                                          'deterioration':
                                              markerDetails['deterioration'],
                                          'unit': markerDetails['unit'],
                                          'quantity': markerDetails['quantity'],
                                          'selectedTextColor': Color(
                                              markerDetails['text_color']),
                                          'selectedBackgroundColor': Color(
                                              markerDetails[
                                                  'background_color']),
                                          'selectedBorderColor': Color(
                                              markerDetails['border_color']),
                                          'selectedFontSize':
                                              markerDetails['font_size'] != null
                                                  ? double.parse(
                                                      markerDetails['font_size']
                                                          .toString())
                                                  : _markerConfig.fontSize,
                                        };
                                        return ShowPopup(
                                          initialValues: initialValues,
                                          onSave: (
                                            location,
                                            part,
                                            finishing,
                                            deterioration,
                                            unit,
                                            quantity,
                                            selectedTextColor,
                                            selectedBackgroundColor,
                                            selectedBorderColor,
                                            selectedFontSize,
                                          ) {
                                            _addMarker(
                                              marker['position'],
                                              isUpdate: true, // isUpdateを追加
                                              markerIndex: marker['id'],
                                            );
                                          },
                                          onCancel: () {
                                            Navigator.of(context).pop();
                                          },
                                          locations: locations,
                                          parts: parts,
                                          finishings: finishings,
                                          deteriorations: deteriorations,
                                          markerInfo: MarkerInfo(
                                            position: marker['position'],
                                            index: marker['id'],
                                          ),
                                          imageId: widget.imageId,
                                          deteriorationDetails:
                                              _deteriorationDetails,
                                        );
                                      },
                                    );
                                  },
                                  child: Center(
                                    child: Text(
                                      '${marker['index']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: marker['text_color'],
                                        fontSize: marker['font_size'],
                                        decoration: TextDecoration.none,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ));
                    }).toList(),
                  ],
                ),
              );
            } else {
              return Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.note),
        onPressed: () {
          OverlayEntry? overlayEntry;
          overlayEntry = OverlayEntry(
            builder: (BuildContext context) {
              return MemoOverlay(
                onClose: () {
                  overlayEntry?.remove();
                },
                surveyId: widget.surveyId, // surveyIdを追加
                drawingId: widget.drawingId,
              );
            },
          );
          Overlay.of(context)!.insert(overlayEntry);
        },
      ),
    );
  }
}
