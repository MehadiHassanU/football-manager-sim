import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/screens/main_menu/main_menu_screen.dart';
import 'package:flutter/material.dart';

void main() {
  group('MainMenuScreen', () {
    test('widget can be built', () {
      final screen = MainMenuScreen();
      expect(screen, isNotNull);
    });

    test('widget has key', () {
      final screen = MainMenuScreen();
      expect(screen.key, isNull);
    });
  });
}