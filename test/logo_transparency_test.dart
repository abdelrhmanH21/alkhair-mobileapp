import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';

/// Regression test for the "logo prints/previews as a solid black square"
/// bug: the receipt logo pipeline used to threshold `pixel.luminance`
/// directly to decide black-vs-white, without ever checking `pixel.a`. Both
/// of AlKhair's real uploaded receipt logos are genuinely transparent PNGs
/// whose transparent pixels' leftover RGB channels happen to be dark
/// (verified by fetching and decoding them directly — one is literally
/// (0,0,0), the other's transparent palette entry is a dark green
/// (71,112,76)) — luminance-only thresholding painted almost the entire
/// transparent background solid black in both the real ESC/POS print and
/// the on-screen preview, regardless of what color the logo visibly is.
/// The fix alpha-composites each pixel onto white before thresholding.
void main() {
  final service = BluetoothPrinterService();

  /// Builds a test PNG already at the pipeline's fixed working width
  /// (`_logoWidthDots` = 384) as four solid horizontal bands, so
  /// `_fetchAndResizeLogo`'s `copyResize(width: 384)` is a horizontal no-op
  /// and each band's pixels reach the threshold step unblended by
  /// interpolation — a data: URI, so the test never touches the network.
  String buildTestLogoDataUri() {
    const bandHeight = 20;
    final image = img.Image(width: 384, height: bandHeight * 4, numChannels: 4);
    for (var x = 0; x < image.width; x++) {
      // Band 0: fully transparent, dark leftover RGB — the exact shape of
      // the bug found in the real uploaded logos.
      for (var y = 0; y < bandHeight; y++) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
      // Band 1: opaque black — genuine logo ink.
      for (var y = bandHeight; y < bandHeight * 2; y++) {
        image.setPixelRgba(x, y, 0, 0, 0, 255);
      }
      // Band 2: opaque white.
      for (var y = bandHeight * 2; y < bandHeight * 3; y++) {
        image.setPixelRgba(x, y, 255, 255, 255, 255);
      }
      // Band 3: mostly transparent, dark leftover RGB — should fade toward
      // white, not print as a hard black dot.
      for (var y = bandHeight * 3; y < bandHeight * 4; y++) {
        image.setPixelRgba(x, y, 0, 0, 0, 40);
      }
    }
    final png = img.encodePng(image);
    return 'data:image/png;base64,${base64Encode(png)}';
  }

  test('a transparent band with dark leftover RGB renders white, not black', () async {
    final dataUri = buildTestLogoDataUri();
    final resultBytes = await service.renderLogoPreviewPng(dataUri);
    expect(resultBytes, isNotNull);

    final result = img.decodePng(resultBytes!)!;
    const bandHeight = 20;
    const x = 192; // middle column — every band is uniform horizontally

    // Band 0 (mid-band, y=10): fully transparent, dark RGB underneath —
    // must be WHITE.
    expect(result.getPixel(x, bandHeight ~/ 2).r, 255,
        reason: 'a transparent pixel must never be flattened to black '
            'regardless of its leftover RGB — this is the exact bug');

    // Band 1 (mid-band, y=30): fully opaque black — must stay BLACK.
    expect(result.getPixel(x, bandHeight + bandHeight ~/ 2).r, 0,
        reason: 'genuine opaque logo ink must still print as black');

    // Band 2 (mid-band, y=50): fully opaque white — must stay WHITE.
    expect(result.getPixel(x, bandHeight * 2 + bandHeight ~/ 2).r, 255);

    // Band 3 (mid-band, y=70): mostly transparent (alpha ~16%) — composites
    // close to white, must NOT be thresholded as a black dot.
    expect(result.getPixel(x, bandHeight * 3 + bandHeight ~/ 2).r, 255,
        reason: 'a mostly-transparent pixel must fade toward white, not '
            'print as a hard black dot');
  });
}
