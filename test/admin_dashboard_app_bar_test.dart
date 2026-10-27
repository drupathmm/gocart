import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/screens/admin_dashboard_screen.dart';

void main() {
  testWidgets('admin app bar fits narrow and desktop browser widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [320.0, 375.0, 599.0, 600.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AdminDashboardAppBar(
              unreadNotificationCount: 2,
              isRefreshing: false,
              onAccountNotifications: () {},
              onAdminNotifications: () {},
              onRefresh: () {},
              onLogout: () {},
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'AppBar should fit at $width logical pixels wide.',
      );
      expect(find.text('GoCart'), findsOneWidget);
      expect(
        find.byTooltip(width < 600 ? 'Admin actions' : 'Logout'),
        findsOneWidget,
      );
    }
  });

  testWidgets('narrow app bar menu keeps all account actions available', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AdminDashboardAppBar(
            unreadNotificationCount: 3,
            isRefreshing: false,
            onAccountNotifications: () => actions.add('account'),
            onAdminNotifications: () => actions.add('admin'),
            onRefresh: () => actions.add('refresh'),
            onLogout: () => actions.add('logout'),
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final item in [
      ('Account and order updates', 'account'),
      ('Admin notifications (3 unread)', 'admin'),
      ('Refresh', 'refresh'),
      ('Logout', 'logout'),
    ]) {
      await tester.tap(find.byTooltip('Admin actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.$1));
      await tester.pumpAndSettle();
      expect(actions.last, item.$2);
    }
    expect(actions, ['account', 'admin', 'refresh', 'logout']);
  });
}
