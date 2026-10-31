import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// 从 Windows 剪贴板读一张图，转成 PNG 字节。
///
/// 只处理最常见的两种来源：截图工具（CF_DIB）与部分应用提供的
/// CF_DIBV5。剪贴板里同时有文字时由调用方优先按文字粘贴。
class ClipboardImage {
  ClipboardImage._();

  static const int _cfDib = 8;
  static const int _cfUnicodeText = 13;
  static const int _cfDibV5 = 17;

  /// 剪贴板里只有图片、没有文字时才返回 true（同步，适合放进快捷键判断）。
  static bool get imageOnly {
    if (!Platform.isWindows) return false;
    try {
      final hasImage = _available(_cfDib) || _available(_cfDibV5);
      return hasImage && !_available(_cfUnicodeText);
    } catch (_) {
      return false;
    }
  }

  /// 读取剪贴板图片并编码为 PNG；没有图片或格式不支持时返回 null。
  static Future<Uint8List?> readPng() async {
    if (!Platform.isWindows) return null;
    Uint8List? dib;
    try {
      // 其他程序刚写入剪贴板时可能短暂占用，重试几次。
      for (var attempt = 0; attempt < 5; attempt++) {
        if (_openClipboard(0) != 0) {
          try {
            dib = _readDib();
          } finally {
            _closeClipboard();
          }
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (_) {
      return null;
    }
    if (dib == null || dib.length < 40) return null;
    return dibToPng(dib);
  }

  static Uint8List? _readDib() {
    var handle = _getClipboardData(_cfDib);
    if (handle == 0) handle = _getClipboardData(_cfDibV5);
    if (handle == 0) return null;
    final pointer = _globalLock(handle);
    if (pointer == 0) return null;
    try {
      final size = _globalSize(handle);
      if (size <= 40) return null;
      final bytes = Pointer<Uint8>.fromAddress(pointer);
      final data = Uint8List(size);
      data.setAll(0, bytes.asTypedList(size));
      return data;
    } finally {
      _globalUnlock(handle);
    }
  }

  static bool _available(int format) =>
      _isClipboardFormatAvailable(format) != 0;

  static int _openClipboard(int hwnd) => _openClipboardFn(hwnd);
  static int _closeClipboard() => _closeClipboardFn();
  static int _getClipboardData(int format) => _getClipboardDataFn(format);
  static int _globalLock(int handle) => _globalLockFn(handle);
  static int _globalUnlock(int handle) => _globalUnlockFn(handle);
  static int _globalSize(int handle) => _globalSizeFn(handle);
  static int _isClipboardFormatAvailable(int format) =>
      _isClipboardFormatAvailableFn(format);
}

// ---------------------------------------------------------------------------
// Win32 FFI
// ---------------------------------------------------------------------------

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _OpenClipboardC = Int32 Function(IntPtr hWnd);
typedef _OpenClipboardD = int Function(int hWnd);

typedef _CloseClipboardC = Int32 Function();
typedef _CloseClipboardD = int Function();

typedef _GetClipboardDataC = IntPtr Function(Uint32 format);
typedef _GetClipboardDataD = int Function(int format);

typedef _IsFormatC = Int32 Function(Uint32 format);
typedef _IsFormatD = int Function(int format);

typedef _GlobalLockC = IntPtr Function(IntPtr handle);
typedef _GlobalLockD = int Function(int handle);

typedef _GlobalUnlockC = Int32 Function(IntPtr handle);
typedef _GlobalUnlockD = int Function(int handle);

typedef _GlobalSizeC = IntPtr Function(IntPtr handle);
typedef _GlobalSizeD = int Function(int handle);

final _OpenClipboardD _openClipboardFn =
    _user32.lookupFunction<_OpenClipboardC, _OpenClipboardD>('OpenClipboard');
final _CloseClipboardD _closeClipboardFn =
    _user32.lookupFunction<_CloseClipboardC, _CloseClipboardD>(
  'CloseClipboard',
);
final _GetClipboardDataD _getClipboardDataFn =
    _user32.lookupFunction<_GetClipboardDataC, _GetClipboardDataD>(
  'GetClipboardData',
);
final _IsFormatD _isClipboardFormatAvailableFn =
    _user32.lookupFunction<_IsFormatC, _IsFormatD>(
  'IsClipboardFormatAvailable',
);
final _GlobalLockD _globalLockFn =
    _kernel32.lookupFunction<_GlobalLockC, _GlobalLockD>('GlobalLock');
final _GlobalUnlockD _globalUnlockFn =
    _kernel32.lookupFunction<_GlobalUnlockC, _GlobalUnlockD>('GlobalUnlock');
final _GlobalSizeD _globalSizeFn =
    _kernel32.lookupFunction<_GlobalSizeC, _GlobalSizeD>('GlobalSize');

// ---------------------------------------------------------------------------
// DIB → PNG
// ---------------------------------------------------------------------------

/// 把 Windows 剪贴板里的 DIB（BITMAPINFOHEADER + 像素）转成 PNG。
Uint8List? dibToPng(Uint8List dib) {
  if (dib.length < 40) return null;
  final data = ByteData.sublistView(dib);
  final headerSize = data.getUint32(0, Endian.little);
  final width = data.getInt32(4, Endian.little);
  final rawHeight = data.getInt32(8, Endian.little);
  final bitCount = data.getUint16(14, Endian.little);
  final compression = data.getUint32(16, Endian.little);
  if (headerSize < 40 || width <= 0 || rawHeight == 0) return null;
  if (bitCount != 24 && bitCount != 32) return null;
  // BI_RGB 或 BI_BITFIELDS
  if (compression != 0 && compression != 3) return null;

  var pixelOffset = headerSize;
  if (compression == 3 && headerSize == 40) pixelOffset += 12;

  final height = rawHeight.abs();
  final topDown = rawHeight < 0;
  final bytesPerPixel = bitCount ~/ 8;
  final stride = ((width * bitCount + 31) ~/ 32) * 4;
  if (pixelOffset + stride * height > dib.length) return null;

  final rgb = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    final sourceRow = topDown ? y : height - 1 - y;
    var src = pixelOffset + sourceRow * stride;
    var dst = y * width * 3;
    for (var x = 0; x < width; x++) {
      rgb[dst] = dib[src + 2];
      rgb[dst + 1] = dib[src + 1];
      rgb[dst + 2] = dib[src];
      src += bytesPerPixel;
      dst += 3;
    }
  }
  return encodePng(width, height, rgb);
}

/// 最小 PNG 编码器：8 位 RGB、无滤波。
Uint8List encodePng(int width, int height, Uint8List rgb) {
  final raw = Uint8List(height * (width * 3 + 1));
  var offset = 0;
  for (var y = 0; y < height; y++) {
    raw[offset++] = 0; // filter: none
    raw.setRange(offset, offset + width * 3, rgb, y * width * 3);
    offset += width * 3;
  }
  final compressed = ZLibCodec(level: 6).encode(raw);

  final ihdr = Uint8List(13);
  final header = ByteData.sublistView(ihdr);
  header.setUint32(0, width, Endian.big);
  header.setUint32(4, height, Endian.big);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // color type: truecolor
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr))
    ..add(_chunk('IDAT', compressed))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final crcInput = Uint8List(typeBytes.length + data.length)
    ..setAll(0, typeBytes)
    ..setAll(typeBytes.length, data);
  final out = BytesBuilder(copy: false)
    ..add(_uint32(data.length))
    ..add(typeBytes)
    ..add(data)
    ..add(_uint32(_crc32(crcInput)));
  return out.takeBytes();
}

Uint8List _uint32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
  return bytes;
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
