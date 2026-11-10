import 'package:allmodiary/ui/editor/toolbar.dart';
import 'package:flutter/painting.dart';
import 'package:allmodiary/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paper: off-white with black text in light, dark grey with white text in dark', () {
    expect(Paper.light.color, const Color(0xFFFAF6EC));
    expect(Paper.light.text, const Color(0xFF000000));
    expect(Paper.dark.text, const Color(0xFFFFFFFF));
    expect(Paper.dark.color.computeLuminance(), lessThan(0.05));
  });

  test("each theme's default text colour is one of the swatches, so picking it can mean 'default'", () {
    final colours = Swatches.text.map((s) => s.color).toSet();
    expect(colours, contains(Paper.light.text));
    expect(colours, contains(Paper.dark.text));
  });
}
