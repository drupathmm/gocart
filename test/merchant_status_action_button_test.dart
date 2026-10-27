import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/widgets/merchant_status_action_button.dart';

void main() {
  testWidgets('pending merchant has an explicit approval action', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantStatusActionButton(
            status: 'pending',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    expect(pressed, isTrue);
  });

  testWidgets('pending merchant has a separate rejection action', (
    tester,
  ) async {
    var rejected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantStatusActionButton(
            status: 'pending',
            onPressed: _noop,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.text('Reject'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
  });

  testWidgets('rejected merchant has no status mutation action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantStatusActionButton(
            status: 'rejected',
            onPressed: _noop,
            onReject: _noop,
          ),
        ),
      ),
    );

    final action = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(action.onPressed, isNull);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets(
    'suspension routes admins to review requests instead of direct restore',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MerchantStatusActionButton(
                  status: 'approved',
                  onPressed: _noop,
                ),
                MerchantStatusActionButton(
                  status: 'suspended',
                  onPressed: _noop,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Suspend'), findsOneWidget);
      expect(find.text('Review requests'), findsOneWidget);
    },
  );

  testWidgets('unknown merchant status disables status actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantStatusActionButton(status: 'unknown', onPressed: _noop),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Status unavailable'), findsOneWidget);
  });
}

void _noop() {}
