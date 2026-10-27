import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/services/product_service.dart';

void main() {
  group('PostgREST search value quoting', () {
    test('keeps OR delimiters inside a quoted value', () {
      expect(
        ProductService.quotePostgrestValue('%chair,(name.eq.secret)%'),
        '"%chair,(name.eq.secret)%"',
      );
    });

    test('escapes quotes and backslashes', () {
      expect(ProductService.quotePostgrestValue('a\\b"c'), '"a\\\\b\\"c"');
    });
  });
}
