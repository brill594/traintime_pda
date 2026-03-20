// Copyright 2026 Hazuki Keatsu.
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:watermeter/model/pda_service/custom_class.dart';
import 'package:watermeter/repository/network_session.dart';

enum CustomClassState { fetching, fetched, error, none }

class CustomClassOccurrence {
  final CustomClass customClass;
  final CustomClassTimeRange timeRange;

  const CustomClassOccurrence({
    required this.customClass,
    required this.timeRange,
  });
}

class CustomClassController extends GetxController {
  static const String _customClassFileName = 'CustomClassesV2.json';
  static const String _customClassIdPrefix = 'cc';
  static const String _timeRangeIdPrefix = 'tr';

  int _idSequence = 0;

  String _nextId(String prefix) {
    final int now = DateTime.now().microsecondsSinceEpoch;
    _idSequence = (_idSequence + 1) & 0xFFFFF;
    return '$prefix-${now.toRadixString(36)}-${_idSequence.toRadixString(36)}';
  }

  String generateCustomClassId() => _nextId(_customClassIdPrefix);

  String generateTimeRangeId() => _nextId(_timeRangeIdPrefix);

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String? error;
  CustomClassState state = CustomClassState.none;
  late File customClassFile;
  List<CustomClass> customClasses = [];

  @override
  void onInit() {
    super.onInit();
    customClassFile = File('${supportPath.path}/$_customClassFileName');
    _load();
  }

  void _load() {
    state = CustomClassState.fetching;
    error = null;
    try {
      if (!customClassFile.existsSync()) {
        customClassFile.writeAsStringSync('[]');
      }
      final dynamic decoded = jsonDecode(customClassFile.readAsStringSync());
      customClasses = (decoded as List<dynamic>)
          .map((e) => CustomClass.fromJson(e as Map<String, dynamic>))
          .toList();
      state = CustomClassState.fetched;
    } catch (e) {
      state = CustomClassState.error;
      error = e.toString();
      customClasses = [];
    }
    update();
  }

  bool _save() {
    try {
      customClassFile.writeAsStringSync(
        jsonEncode(customClasses.map((e) => e.toJson()).toList()),
      );
      error = null;
      state = CustomClassState.fetched;
      return true;
    } catch (e) {
      state = CustomClassState.error;
      error = 'Failed to save custom classes: $e';
      return false;
    }
  }

  int _indexOfCustomClassById(String customClassId) => customClasses.indexWhere(
    (customClass) => customClass.id == customClassId,
  );

  /// 添加新的自定义课程
  Future<void> addCustomClass(CustomClass customClass) async {
    customClasses.add(customClass);
    if (!_save()) {
      customClasses.removeLast();
    }
    update();
  }

  /// 编辑已有的自定义课程
  Future<void> editCustomClassById(
    String customClassId,
    CustomClass customClass,
  ) async {
    final int index = _indexOfCustomClassById(customClassId);
    if (index < 0) return;
    final CustomClass oldValue = customClasses[index];
    customClasses[index] = customClass;
    if (!_save()) {
      customClasses[index] = oldValue;
    }
    update();
  }

  /// 删除已有的自定义课程
  Future<void> deleteCustomClassById(String customClassId) async {
    final int index = _indexOfCustomClassById(customClassId);
    if (index < 0) return;
    final CustomClass removed = customClasses.removeAt(index);
    if (!_save()) {
      customClasses.insert(index, removed);
    }
    update();
  }

  /// 从已有的自定义课程中一处某个时间段
  Future<void> deleteCustomClassTimeRange({
    required String customClassId,
    required String timeRangeId,
  }) async {
    final int customIndex = _indexOfCustomClassById(customClassId);
    if (customIndex < 0) return;

    final CustomClass customClass = customClasses[customIndex];
    final int timeRangeIndex = customClass.timeRanges.indexWhere(
      (timeRange) => timeRange.id == timeRangeId,
    );
    if (timeRangeIndex < 0) return;

    final List<CustomClassTimeRange> updatedRanges =
        List<CustomClassTimeRange>.from(customClass.timeRanges)
          ..removeAt(timeRangeIndex);

    if (updatedRanges.isEmpty) {
      final CustomClass removed = customClasses.removeAt(customIndex);
      if (!_save()) {
        customClasses.insert(customIndex, removed);
      }
      update();
      return;
    }

    final CustomClass updatedClass = CustomClass(
      id: customClass.id,
      name: customClass.name,
      teacher: customClass.teacher,
      classroom: customClass.classroom,
      timeRanges: updatedRanges,
    );
    customClasses[customIndex] = updatedClass;
    if (!_save()) {
      customClasses[customIndex] = customClass;
    }
    update();
  }

  /// 通过周索引、日索引和学期开始日期来找到有日程的那天
  List<CustomClassOccurrence> getOccurrenceOfDay({
    required int weekIndex,
    required int dayIndex,
    required DateTime semesterStartDay,
  }) {
    final List<CustomClassOccurrence> occurrences = [];

    for (final customClass in customClasses) {
      for (final timeRange in customClass.timeRanges) {
        final int diffDays = _dateOnly(
          timeRange.startTime,
        ).difference(_dateOnly(semesterStartDay)).inDays;
        if (diffDays < 0) continue;

        final int targetWeek = diffDays ~/ 7;
        final int targetDay = diffDays % 7 + 1;

        if (targetWeek == weekIndex && targetDay == dayIndex) {
          occurrences.add(
            CustomClassOccurrence(
              customClass: customClass,
              timeRange: timeRange,
            ),
          );
        }
      }
    }

    return occurrences;
  }
}
