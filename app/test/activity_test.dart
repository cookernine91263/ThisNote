import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/activity.dart';

void main() {
  test('startSession 幂等，始终保留最初的基线', () {
    final log = ActivityLog();
    expect(log.startSession('2026-10-31', 'n1', 1200), 1200);
    log.touch('2026-10-31', 'n1', 1350);
    expect(log.startSession('2026-10-31', 'n1', 9999), 1200);
    expect(log.startSession('2026-10-31', 'n1', 10), 1200);
    expect(log.days['2026-10-31']!.notes['n1']!.startWords, 1200);
  });

  test('touch 只增不减：字数回落不会让 gain 变小', () {
    final log = ActivityLog();
    log.startSession('2026-10-31', 'n1', 1200);
    expect(log.touch('2026-10-31', 'n1', 1300), 100);
    expect(log.touch('2026-10-31', 'n1', 1350), 150);
    expect(log.touch('2026-10-31', 'n1', 1210), 150);
    expect(log.touch('2026-10-31', 'n1', 1200), 150);
    expect(log.touch('2026-10-31', 'n1', 1450), 250);
  });

  test('touch 遇到未知笔记时新建条目，gain 从 0 开始', () {
    final log = ActivityLog();
    expect(log.touch('2026-10-31', 'n2', 500), 0);
    expect(log.days['2026-10-31']!.notes['n2']!.startWords, 500);
    expect(log.touch('2026-10-31', 'n2', 520), 20);
  });

  test('wordsOn 汇总一天的多个笔记，未知日期返回 0', () {
    final log = ActivityLog();
    log.startSession('2026-10-31', 'n1', 1200);
    log.startSession('2026-10-31', 'n2', 30);
    log.touch('2026-10-31', 'n1', 1320);
    log.touch('2026-10-31', 'n2', 55);
    expect(log.wordsOn('2026-10-31'), 145);
    expect(log.wordsOn('2026-11-01'), 0);
    expect(log.activeDays(), {'2026-10-31'});
  });

  test('JSON 使用短键并能编码/解码往返', () {
    final log = ActivityLog();
    log.startSession('2026-10-31', 'n1', 1200);
    log.touch('2026-10-31', 'n1', 1320);
    expect(log.toJson(), {
      'days': {
        '2026-10-31': {
          'n1': {'s': 1200, 'g': 120},
        },
      },
    });

    final restored = ActivityLog.decode(log.encode());
    expect(restored.wordsOn('2026-10-31'), 120);
    expect(restored.days['2026-10-31']!.notes['n1']!.startWords, 1200);
    expect(ActivityLog.decode(ActivityLog().encode()).days, isEmpty);
  });

  test('decode 对 null、非 JSON、畸形结构都返回空日志且不抛异常', () {
    expect(ActivityLog.decode(null).days, isEmpty);
    expect(ActivityLog.decode('').days, isEmpty);
    expect(ActivityLog.decode('not json').days, isEmpty);
    expect(ActivityLog.decode('[]').days, isEmpty);
    expect(ActivityLog.decode('{"days":"oops"}').days, isEmpty);
    expect(ActivityLog.decode('{"days":{"2026-10-31":"x"}}').days.length, 1);
    expect(ActivityLog.decode('{"days":{"2026-10-31":"x"}}').wordsOn('2026-10-31'), 0);

    final dirty = ActivityLog.decode(
      '{"days":{"2026-10-31":{"n1":{"s":"abc","g":-5},'
      '"n2":{"s":null,"g":"12"},"n3":null,"n4":{"s":3.9,"g":7.8}}}}',
    );
    expect(dirty.wordsOn('2026-10-31'), 19);
    expect(dirty.days['2026-10-31']!.notes['n1']!.startWords, 0);
    expect(dirty.days['2026-10-31']!.notes['n1']!.gain, 0);
    expect(dirty.days['2026-10-31']!.notes['n4']!.startWords, 3);

    expect(NoteActivity.fromJson(null).startWords, 0);
    expect(DayActivity.fromJson(null).notes, isEmpty);
    expect(ActivityLog.fromJson(null).days, isEmpty);
  });

  test('startSession 对负数与异常值做钳制', () {
    final log = ActivityLog();
    expect(log.startSession('2026-10-31', 'n1', -50), 0);
    expect(log.touch('2026-10-31', 'n1', -80), 0);
    expect(log.wordsOn('2026-10-31'), 0);
  });

  test('pruneBefore 保留 cutoff 当天，丢弃更早的日期', () {
    final log = ActivityLog();
    for (final day in ['2026-10-29', '2026-10-30', '2026-10-31']) {
      log.startSession(day, 'n1', 0);
      log.touch(day, 'n1', 10);
    }
    log.pruneBefore('2026-10-30');
    expect(log.days.keys, unorderedEquals(['2026-10-30', '2026-10-31']));
    expect(log.wordsOn('2026-10-29'), 0);
    expect(log.wordsOn('2026-10-31'), 10);
  });
}
