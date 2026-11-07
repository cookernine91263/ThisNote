import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/features/editor/note_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled fonts and OFL licenses are present', () async {
    for (final asset in const [
      'assets/fonts/SmileySans-Oblique.otf',
      'assets/fonts/SourceHanMonoSC-Regular.otf',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(512 * 1024), reason: asset);
    }

    for (final license in const [
      'assets/fonts/OFL-SmileySans.txt',
      'assets/fonts/OFL-SourceHanMono.txt',
    ]) {
      final data = await rootBundle.loadString(license);
      expect(data.toUpperCase(), contains('SIL OPEN FONT LICENSE'));
    }

    final values = noteFonts.map((e) => e.value).toList();
    expect(values, contains('SmileySans'));
    expect(values, contains('SourceHanMono'));
  });
}
