import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/app/palette/palette_importer.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  test('imports json palette with name and hex colors', () {
    final Uint8List data = _bytes('''
{
  "name": "Game Palette",
  "colors": ["#5E315B", "#8C3F5D", "#66FFE3", "#FFFFEA"]
}
''');

    final PaletteImportResult result = PaletteFileImporter.importData(
      data,
      extension: 'json',
      fileName: 'palette.json',
    );

    expect(result.name, 'Game Palette');
    expect(result.colors, <Color>[
      const Color(0xFF5E315B),
      const Color(0xFF8C3F5D),
      const Color(0xFF66FFE3),
      const Color(0xFFFFFFEA),
    ]);
  });

  test('falls back to file name when json name is missing', () {
    final Uint8List data = _bytes('''
{
  "colors": ["#112233"]
}
''');

    final PaletteImportResult result = PaletteFileImporter.importData(
      data,
      extension: 'json',
      fileName: 'palette.json',
    );

    expect(result.name, 'palette.json');
    expect(result.colors, <Color>[const Color(0xFF112233)]);
  });

  test('throws when json palette has no valid colors', () {
    final Uint8List data = _bytes('''
{
  "name": "Broken",
  "colors": ["hello", 42]
}
''');

    expect(
      () => PaletteFileImporter.importData(
        data,
        extension: 'json',
        fileName: 'broken.json',
      ),
      throwsA(isA<PaletteImportException>()),
    );
  });
}
