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
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class SurveyPageState extends State<SurveyPage> {
  late Image _image;
  bool _imageLoaded = false;
  List<Map<String, dynamic>> _markers = [];
  String? selectedUnit;
  late String id;
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
  String? closestMarkerId;
  bool _isMovingMarker = false;
  String? _movingMarkerId;
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  User? _currentUser;
  String? pageName;
  bool? currentInternetEnvironment = false;
  List<Map<String, String>> data = [];

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
    _getDrowing();
    _fetchCurrentUser();
    _fetchDeteriorationDetails();
    _getUserInternet();
    widget.surveyType == '特殊建築物定期調査' ? _loadJson() : _fetchDataFromFirestore();
    print(locations);
  }

  Future<void> _fetchCurrentUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  Future<void> _loadJson() async {
    try {
      String jsonString = await rootBundle.loadString('assets/surveyitem.json');
      final jsonResponse = json.decode(jsonString) as List<dynamic>;

      data = jsonResponse
          .map((item) => {
                "Part": item['Part'] as String,
                "Condition": item['Condition'] as String,
                "Location": item['Location'] as String,
              })
          .toList();

      locations = data.map((item) => item['Location']!).toSet().toList();
    } catch (e) {
      print('Error: $e');
    }
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
    String markerId = marker['id'];
    int markerIndex = marker['index'];
    _markers.removeWhere((m) => m['id'] == markerId);
    for (int i = markerIndex; i <= _markers.length; i++) {
      _markers[i - 1]['index'] = i;
    }
    setState(() {});
    QuerySnapshot snapshot = await _firestore
        .collection('deteriorationDetails')
        .where('id', isEqualTo: markerId)
        .get();
    if (snapshot.docs.isNotEmpty) {
      DocumentSnapshot document = await snapshot.docs.first.reference.get();
      if (document.exists) {
        Map<String, dynamic> data = document.data() as Map<String, dynamic>;
        if (data.containsKey('image_url')) {
          Reference oldImageRef = _storage.refFromURL(marker['image_url']);
          await oldImageRef.delete();
        }
      }
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
    setState(() {});
  }

  void _addMarker(Offset position) async {
    setState(() {
      _markerInfo = MarkerInfo(position: position, index: _markers.length + 1);
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
                      var uuid = Uuid();
                      String generatedUuid = uuid.v4();
                      selectedUnit = unit;
                      // Save the marker data to Firestore
                      _firestore.collection('deteriorationDetails').add({
                        'position': {
                          'dx': _markerInfo!.position.dx,
                          'dy': _markerInfo!.position.dy
                        },
                        'id': generatedUuid,
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
                        'createdBy': _currentUser!.uid
                      });
                      _markers.add({
                        'position': _markerInfo!.position,
                        'id': generatedUuid,
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
                        'text_color': selectedTextColor,
                        'background_color': selectedBackgroundColor,
                        'border_color': selectedBorderColor,
                        'font_size': selectedFontSize,
                        'createdBy': _currentUser!.uid
                      });
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
                    if (imageFile != null) {
                      this.imageFile = imageFile;
                      _tempImageFile = imageFile;
                    } else {
                      _tempImageFile = null;
                    }
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
              'location': detail['location'],
              'part': detail['part'],
              'finishing': detail['finishing'],
              'deterioration': detail['deterioration'],
              'unit': detail['unit'],
              'quantity': detail['quantity'],
              'image_url': detail['image_url'],
              'id': detail['id'],
              'index': detail['index'],
              'text_color': Color(detail['text_color']),
              'background_color': Color(detail['background_color']),
              'surveyid': detail['surveyid'],
              'drawingid': detail['drawingid'],
              'border_color': Color(detail['border_color']),
              'font_size': detail['font_size'] != null
                  ? double.parse(detail['font_size'].toString())
                  : _markerConfig.fontSize,
              'createdBy': detail['createdBy'],
              'modifiedBy': detail['createdBy']
            })
        .toList();

    setState(() {});
  }

  void _editMarker(Map<String, dynamic> marker) async {
    _markerInfo =
        MarkerInfo(position: marker['position'], index: marker['index']);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ShowPopup(
          initialValues: marker,
          onSave: (location,
              part,
              finishing,
              deterioration,
              unit,
              quantity,
              selectedTextColor,
              selectedBackgroundColor,
              selectedBorderColor,
              selectedFontSize) async {
            try {
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
              // 4. Update Firestore document
              QuerySnapshot snapshot = await FirebaseFirestore.instance
                  .collection('deteriorationDetails')
                  .where('id', isEqualTo: marker['id'])
                  .get();
              if (snapshot.docs.isNotEmpty) {
                Map<String, dynamic>? imageUrlMap =
                    _tempImageFile != null ? {'image_url': downloadUrl} : null;
                Map<String, dynamic> updateData = {
                  'location': location,
                  'part': part,
                  'finishing': finishing,
                  'deterioration': deterioration,
                  'unit': unit,
                  'quantity': quantity,
                  'text_color': selectedTextColor.value,
                  'background_color': selectedBackgroundColor.value,
                  'border_color': selectedBorderColor.value,
                  'font_size': selectedFontSize,
                  'modifiedBy': _currentUser!.uid,
                  if (imageUrlMap != null) ...imageUrlMap,
                };
                DocumentReference docRef = snapshot.docs.first.reference;
                await docRef.update(updateData);

                marker = _markers
                    .firstWhere((element) => element['id'] == marker['id']);
                print(marker);
                int index = marker['index'] - 1;
                Map<String, dynamic> newMarker = Map.from(marker);
                newMarker['location'] = location;
                newMarker['part'] = part;
                newMarker['finishing'] = finishing;
                newMarker['deterioration'] = deterioration;
                newMarker['unit'] = unit;
                newMarker['quantity'] = quantity;
                newMarker['text_color'] = selectedTextColor;
                newMarker['background_color'] = selectedBackgroundColor;
                newMarker['border_color'] = selectedBorderColor;
                newMarker['font_size'] = selectedFontSize;
                newMarker['modifiedBy'] = _currentUser!.uid;
                _tempImageFile != null
                    ? newMarker['image_url'] = downloadUrl
                    : null;
                _markers[index] = newMarker;

                setState(() {
                  _tempImageFile = null;
                });
              }
            } catch (e) {
              print(e.toString());
            }
          },
          onCancel: _onPopupCancel,
          locations: locations,
          parts: parts,
          finishings: finishings,
          deteriorations: deteriorations,
          imageId: widget.imageId,
          markerInfo: _markerInfo!,
          deteriorationDetails: _deteriorationDetails,
          onImageSelected: (File? imageFile) {
            setState(() {
              if (imageFile != null) {
                this.imageFile = imageFile;
                _tempImageFile = imageFile;
              } else {
                _tempImageFile = null;
              }
            });
          },
        );
      },
    );
  }

  void _moveMarker(String closestMarkerId, Offset newPosition) async {
    final moveMarker = _markers.firstWhere(
        (element) => element != null && element['id'] == closestMarkerId,
        orElse: () => {});
    if (moveMarker == {}) {
      return;
    }
    {
      try {
        // 4. Update Firestore document
        QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('deteriorationDetails')
            .where('id', isEqualTo: closestMarkerId)
            .get();
        if (snapshot.docs.isNotEmpty) {
          DocumentReference docRef = snapshot.docs.first.reference;
          await docRef.update({
            'position': {'dx': newPosition.dx, 'dy': newPosition.dy},
            'modifiedBy': _currentUser!.uid
          });
        }
      } catch (e) {
        print(e.toString());
      }
    }
    int num =
        _markers.indexWhere((element) => element['id'] == _movingMarkerId);
    moveMarker[num];
    Map<String, dynamic> newMarker = Map.from(moveMarker);
    newMarker['position'] = newPosition;
    newMarker['modifiedBy'] = _currentUser!.uid;
    setState(() {
      _markers[num] = newMarker;
    });
    _isMovingMarker = false;
  }

  Future<void> _Vibrator() async {
    bool? hasVibrator;
    try {
      hasVibrator = await Vibration.hasVibrator();
    } catch (e) {
      print('Error checking for vibrator: $e');
    }

    // 非同期処理が終わった後、BuildContextを使用する
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasVibrator != null && hasVibrator) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('マーカー移動スタート　移動先をタップしてください。')),
        );
        Vibration.vibrate(duration: 500);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('マーカー移動スタート　移動先をタップしてください。')),
        );
      }
    });
  }

  Future<void> _getDrowing() async {
    String documentId = widget.surveyId; // 対象のドキュメントのID
    String uuid = widget.imageId; // 検索対象のUUID

    var surveysCollectionRef = FirebaseFirestore.instance.collection('surveys');
    DocumentSnapshot documentSnapshot =
        await surveysCollectionRef.doc(documentId).get();
    List<dynamic> drawings = documentSnapshot.get('drawings');
    Map<String, dynamic>? targetDrawing;
    for (var drawing in drawings) {
      if (drawing['uuid'] == uuid) {
        targetDrawing = drawing;
        break;
      }
    }
    if (targetDrawing != null) {
      pageName = targetDrawing['name'];
    }
  }

  Future<void> _getUserInternet() async {
    CollectionReference users = _firestore.collection('users');
    DocumentSnapshot userSnapshot = await users.doc(_currentUser!.uid).get();
    currentInternetEnvironment =
        (userSnapshot.data() as Map<String, dynamic>)['InternetEnvironment'] ??
            false;
  }

  Future<void> _changeInternetMode() async {
    CollectionReference users = _firestore.collection('users');
    DocumentSnapshot userSnapshot = await users.doc(_currentUser!.uid).get();
    currentInternetEnvironment =
        (userSnapshot.data() as Map<String, dynamic>)['InternetEnvironment'];
    if (currentInternetEnvironment != null) {
      // 反転させた値を更新する
      await users
          .doc(_currentUser!.uid)
          .update({'InternetEnvironment': !currentInternetEnvironment!});
      setState(() {
        currentInternetEnvironment = !currentInternetEnvironment!;
      });
    } else {
      // InternetEnvironment の値が null の場合、デフォルト値（true または false）を設定
      await users.doc(_currentUser!.uid).update({'InternetEnvironment': true});
      setState(() {
        currentInternetEnvironment = true;
      });
    }
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pageName ?? "図面"),
        actions: [
          Text(
              'Mode: ${currentInternetEnvironment != null ? (currentInternetEnvironment! ? true : false) : false}'),
          SizedBox(height: 16),
          Switch(
            value: currentInternetEnvironment!,
            onChanged: (bool newValue) {
              _changeInternetMode();
              setState(() {
                currentInternetEnvironment = newValue;
              });
            },
            activeColor: Colors.green, // オン（インターネットモード）の時の色
            inactiveThumbColor: Colors.grey, // オフ（ローカルモード）の時の親指の色
            inactiveTrackColor:
                Colors.grey.withOpacity(0.5), // オフ（ローカルモード）の時のトラックの色
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
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset position =
                      box.globalToLocal(details.globalPosition);
                  if (!_isMovingMarker) {
                    _addMarker(position);
                  } else if (closestMarkerId != null) {
                    _moveMarker(closestMarkerId!, position);
                  }
                },
                onLongPressStart: (LongPressStartDetails details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset position =
                      box.globalToLocal(details.globalPosition);
                  double minDistance = double.infinity;
                  for (var marker in _markers) {
                    final distance = (marker['position'] - position).distance;
                    if (distance < minDistance) {
                      minDistance = distance;
                      closestMarkerId = marker['id'];
                    }
                  }
                  if (closestMarkerId != null) {
                    _isMovingMarker = true;
                    _movingMarkerId = closestMarkerId;

                    _Vibrator();

                    setState(() {});
                  } else {
                    _isMovingMarker = false;
                  }
                },
                onLongPressEnd: (LongPressEndDetails details) {
                  final Offset touchPosition = details.globalPosition;

                  if (_isMovingMarker) {
                    _moveMarker(_movingMarkerId!, touchPosition);
                    setState(() {});
                    _movingMarkerId = null;
                  }
                },
                onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset touchPosition =
                      box.globalToLocal(details.globalPosition);

                  if (_isMovingMarker) {
                    _moveMarker(_movingMarkerId!, touchPosition);
                    setState(() {});
                  }
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
                                  onDoubleTap: () {
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
                                  onTap: () async {
                                    _editMarker(marker);
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
                imageId: widget.imageId,
              );
            },
          );
          Overlay.of(context).insert(overlayEntry);
        },
      ),
    );
  }
}
