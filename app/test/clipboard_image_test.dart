import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/services/clipboard_image.dart';

Uint8List _dib24(int width, int height, List<List<List<int>>> bgrTopDown) {
  final stride = ((width * 24 + 31) ~/ 32) * 4;
  final bytes = Uint8List(40 + stride * height);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, 40, Endian.little); // biSize
  header.setInt32(4, width, Endian.little);
  header.setInt32(8, height, Endian.little); // 正数 = 自下而上
  header.setUint16(12, 1, Endian.little); // planes
  header.setUint16(14, 24, Endian.little); // bit count
  header.setUint32(16, 0, Endian.little); // BI_RGB
  var offset = 40;
  for (var y = 0; y < height; y++) {
    // DIB 的第 0 行是图片底部
    final row = bgrTopDown[height - 1 - y];
    for (var x = 0; x < width; x++) {
      final pixel = row[x];
      bytes[offset + x * 3] = pixel[0];
      bytes[offset + x * 3 + 1] = pixel[1];
      bytes[offset + x * 3 + 2] = pixel[2];
    }
    offset += stride;
  }
  return bytes;
}

int _pngWidth(Uint8List png) =>
    ByteData.sublistView(png).getUint32(16, Endian.big);

int _pngHeight(Uint8List png) =>
    ByteData.sublistView(png).getUint32(20, Endian.big);

void main() {
  test('PNG 头、尺寸与块结构正确', () {
    final rgb = Uint8List.fromList([255, 0, 0, 0, 255, 0, 0, 0, 255]);
    final png = encodePng(3, 1, rgb);
    expect(
      png.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    );
    expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
    expect(_pngWidth(png), 3);
    expect(_pngHeight(png), 1);
    expect(String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)), 'IEND');
  });

  test('24 位 DIB 能转成正确尺寸的 PNG', () {
    final dib = _dib24(2, 2, [
      [
        [0, 0, 255],
        [0, 255, 0],
      ],
      [
        [255, 0, 0],
        [255, 255, 255],
      ],
    ]);
    final png = dibToPng(dib);
    expect(png, isNotNull);
    expect(_pngWidth(png!), 2);
    expect(_pngHeight(png), 2);
  });

  test('不支持的位深返回 null', () {
    final dib = _dib24(2, 1, [
      [
        [0, 0, 0],
        [0, 0, 0],
      ],
    ]);
    final header = ByteData.sublistView(dib);
    header.setUint16(14, 8, Endian.little);
    expect(dibToPng(dib), isNull);
  });

  test('截断的 DIB 不会越界', () {
    final dib = _dib24(4, 4, [
      for (var i = 0; i < 4; i++)
        [
          for (var j = 0; j < 4; j++) [0, 0, 0]
        ]
    ]);
    final cut = Uint8List.sublistView(dib, 0, 60);
    expect(dibToPng(cut), isNull);
  });
}
