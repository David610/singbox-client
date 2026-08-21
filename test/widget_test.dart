// A meaningful i18n scaffolding smoke test.
//
// This used to be `flutter create`'s default counter-app template test,
// unrelated to this VPN client (no counter UI exists here) and never
// updated for this fork -- it always failed, testing nothing real about
// the app. `MyApp` itself needs full native-plugin bootstrap (storage,
// tray/window management, etc.) that isn't mocked anywhere in this test
// suite, so this instead exercises the same `TranslationProvider`/`t`
// scaffolding `MyApp` depends on for every screen, which is real,
// self-contained, and testable without that bootstrap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karing/i18n/strings.g.dart';

void main() {
  testWidgets('TranslationProvider supplies real app strings to descendants', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: Builder(
          builder: (context) =>
              MaterialApp(home: Text(context.t.SettingsScreen.htmlBoard)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Online Panel'), findsOneWidget);
  });
}
