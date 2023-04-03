import 'package:flutter/material.dart';
import 'survey_page_state.dart';

class SurveyPage extends StatefulWidget {
  final String imagePath;
  final String imageId;
  final String imageName;
  final String surveyId;
  final String drawingId;
  bool? currentInternetEnvironment = false;
  final String surveyType;

  SurveyPage({
    required this.imagePath,
    required this.imageId,
    required this.imageName,
    required this.surveyId,
    required this.drawingId,
    required this.surveyType,
  });

  @override
  SurveyPageState createState() => SurveyPageState();
}

@override
void initState() {}
