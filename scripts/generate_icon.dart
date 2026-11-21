import 'dart:io';
import 'dart:typed_data';

// Generate a valid 32x32 PNG file with indigo background and white sync icon
void main() {
  final file = File('D:/Projects/Sync47/apps/sync47_pc/assets/tray_icon.png');
  file.parent.createSync(recursive: true);

  // Minimal 32x32 PNG header and uncompressed IDAT
  // We can write a minimal valid PNG
  final pngBytes = _generate32x32Png();
  file.writeAsBytesSync(pngBytes);

  // Also write ico
  final icoFile = File('D:/Projects/Sync47/apps/sync47_pc/assets/app_icon.ico');
  icoFile.writeAsBytesSync(_generateIco(pngBytes));

  print('Icons generated successfully.');
}

List<int> _generateIco(List<int> pngBytes) {
  final header = Uint8List(6);
  final bdata = ByteData.sublistView(header);
  bdata.setUint16(0, 0, Endian.little); // Reserved
  bdata.setUint16(2, 1, Endian.little); // ICO type
  bdata.setUint16(4, 1, Endian.little); // 1 image

  final entry = Uint8List(16);
  final edata = ByteData.sublistView(entry);
  entry[0] = 32; // Width
  entry[1] = 32; // Height
  entry[2] = 0;  // Palette count
  entry[3] = 0;  // Reserved
  edata.setUint16(4, 1, Endian.little); // Color planes
  edata.setUint16(6, 32, Endian.little); // Bits per pixel
  edata.setUint32(8, pngBytes.length, Endian.little); // Image size
  edata.setUint32(12, 6 + 16, Endian.little); // Offset

  return [...header, ...entry, ...pngBytes];
}

List<int> _generate32x32Png() {
  // 32x32 RGBA raw image
  const width = 32;
  const height = 32;
  final rawData = <int>[];

  for (int y = 0; y < height; y++) {
    rawData.add(0); // filter type: None
    for (int x = 0; x < width; x++) {
      // Rounded icon in Indigo #4F46E5
      final dx = x - 15.5;
      final dy = y - 15.5;
      final distSq = dx * dx + dy * dy;
      if (distSq <= 14 * 14) {
        // Draw symbol
        if ((x >= 10 && x <= 22 && y >= 14 && y <= 18) ||
            (y >= 10 && y <= 22 && x >= 14 && x <= 18)) {
          // White symbol center
          rawData.addAll([255, 255, 255, 255]);
        } else {
          // Indigo #4F46E5
          rawData.addAll([0x4F, 0x46, 0xE5, 255]);
        }
      } else {
        // Transparent
        rawData.addAll([0, 0, 0, 0]);
      }
    }
  }

  // Deflate using zlib in Dart
  final deflated = zlib.encode(rawData);

  final out = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  ];

  void writeChunk(String type, List<int> data) {
    final length = Uint8List(4);
    ByteData.sublistView(length).setUint32(0, data.length, Endian.big);
    out.addAll(length);

    final typeBytes = type.codeUnits;
    out.addAll(typeBytes);
    out.addAll(data);

    // CRC32
    final crc = _crc32([...typeBytes, ...data]);
    final crcBytes = Uint8List(4);
    ByteData.sublistView(crcBytes).setUint32(0, crc, Endian.big);
    out.addAll(crcBytes);
  }

  // IHDR
  final ihdr = Uint8List(13);
  final ihdrData = ByteData.sublistView(ihdr);
  ihdrData.setUint32(0, width, Endian.big);
  ihdrData.setUint32(4, height, Endian.big);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: RGBA
  ihdr[10] = 0; // compression method
  ihdr[11] = 0; // filter method
  ihdr[12] = 0; // interlace method
  writeChunk('IHDR', ihdr);

  // IDAT
  writeChunk('IDAT', deflated);

  // IEND
  writeChunk('IEND', []);

  return out;
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (int j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}
