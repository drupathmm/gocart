import 'package:flutter_test/flutter_test.dart';

import 'package:gocart/main.dart';

void main() {
  testWidgets('GoCart app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const GoCartApp());

    expect(find.text('GoCart'), findsOneWidget);
  });
}
