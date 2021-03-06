import 'package:json_annotation/json_annotation.dart';
import 'package:raco/src/models/db_helpers/custom_grade_helper.dart';

part 'custom_grades.g.dart';

@JsonSerializable(explicitToJson: true)
class CustomGrades {
  int count;
  List<CustomGrade> results;


  CustomGrades(this.count, this.results);

  factory CustomGrades.fromJson(Map<String, dynamic> json) =>
      _$CustomGradesFromJson(json);

  Map<String, dynamic> toJson() => _$CustomGradesToJson(this);
}

@JsonSerializable()
class CustomGrade {
  String id;
  String subjectId;
  String name;
  String comments;
  String data;
  double grade;
  double percentage;

  CustomGrade(this.id, this.subjectId,this.name, this.comments, this.data,this.grade,this.percentage);

  CustomGrade.fromCustomGradeHelper(CustomGradeHelper customGradeHelper) {
    this.id = customGradeHelper.id;
    this.subjectId = customGradeHelper.subjectId;
    this.name = customGradeHelper.name;
    this.comments = customGradeHelper.comments;
    this.data = customGradeHelper.data;
    this.grade = customGradeHelper.grade;
    this.percentage = customGradeHelper.percentage;
  }

  factory CustomGrade.fromJson(Map<String, dynamic> json) =>
      _$CustomGradeFromJson(json);

  Map<String, dynamic> toJson() => _$CustomGradeToJson(this);
}

