import 'dart:math';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

class YouthPlayer {
  String name;
  int age;
  int potential;
  int currentStats;
  String position;
  String nationality;
  bool isPromoted;
  Map<String, dynamic> hiddenAttributes;

  YouthPlayer({
    required this.name,
    required this.age,
    required this.potential,
    required this.currentStats,
    required this.position,
    required this.nationality,
    this.isPromoted = false,
    Map<String, dynamic>? hiddenAttributes,
  }) : hiddenAttributes = hiddenAttributes ?? {
          'personality': ['Stable', 'Driven', 'Charismatic', 'Temperamental']
              [Random().nextInt(4)],
          'leadership': Random().nextInt(100),
        };
}