library test_hop_tasks;

import 'dart:async';
import 'dart:io';
import 'package:unittest/unittest.dart';
import 'package:bot/bot.dart';
import 'package:bot/bot_git.dart';
import 'package:bot/bot_io.dart';
import 'package:bot/bot_test.dart';
import 'package:bot/hop.dart';
import 'package:bot/hop_tasks.dart';
import '../hop/_hop.dart';

part 'process_tests.dart';
part 'git_tests.dart';
part 'dart_analyzer_tests.dart';

void main() {
  group('hop_tasks', () {
    ProcessTests.run();
    GitTests.register();
    DartAnalyzerTests.register();
  });
}
