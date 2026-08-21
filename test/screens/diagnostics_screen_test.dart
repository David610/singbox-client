// Widget test for DiagnosticsScreen. Deliberately does NOT import
// package:karing/main.dart (which cannot currently compile -- see
// docs/ARCHITECTURE.md §9); DiagnosticsScreen was built specifically to
// not depend on any of the still-missing lib/app/utils/ modules, and this
// test proves that independence by exercising it standalone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karing/screens/diagnostics_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vpn_core/vpn_core.dart';

class _FakeVpnCorePlatform extends VpnCorePlatform {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> start(VpnCoreConfig config) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restart(VpnCoreConfig config) async {}

  @override
  Future<VpnCoreStatus> status() async =>
      const VpnCoreStatus(state: VpnCoreState.connected, activeTag: 'Reality');

  @override
  Stream<VpnCoreStatus> statusStream() => const Stream.empty();

  @override
  Future<String> coreVersion() async => '1.13.19';

  @override
  Future<List<String>> getSanitizedLogs({int maxLines = 200}) async => [
    '[error] outbound uuid: 9c7e12d1-64c3-46f2-9e21-d707f05c88d9 pbk=anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w',
  ];
}

void main() {
  setUp(() {
    VpnCorePlatform.instance = _FakeVpnCorePlatform();
    PackageInfo.setMockInitialValues(
      appName: 'singbox-client',
      packageName: 'com.example.singboxclient',
      version: '1.2.24',
      buildNumber: '2704',
      buildSignature: '',
    );
  });

  testWidgets('renders VPN state and profile once loaded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(
          serverHostname: 'vpn.singboxvpn.test.invalid',
          selectedTransport: 'vless-reality',
          vlessUuidForCorrelation: '9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Values are rendered via SelectableText (so a user can copy a single
    // field), not Text -- find.text() only matches Text/EditableText, so
    // values are asserted via the SelectableText widget list directly.
    final allText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(allText, contains('connected'));
    expect(allText, contains('Reality'));
    expect(allText, contains('vpn.singboxvpn.test.invalid'));
  });

  testWidgets('never renders the raw VLESS UUID anywhere on screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(
          serverHostname: 'vpn.singboxvpn.test.invalid',
          vlessUuidForCorrelation: '9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .followedBy(tester.widgetList<SelectableText>(find.byType(SelectableText)).map((w) => w.data ?? ''))
        .join('\n');

    expect(allText.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
    // The redacted, correlatable form IS expected to appear.
    expect(allText.contains('88d9'), isTrue);
  });

  testWidgets('the last engine error shown on screen is redacted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(serverHostname: 'vpn.singboxvpn.test.invalid'),
      ),
    );
    await tester.pumpAndSettle();

    final allText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(allText.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
    expect(allText.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'), isFalse);
  });

  testWidgets('export dialog text never contains the raw UUID or REALITY key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(
          serverHostname: 'vpn.singboxvpn.test.invalid',
          vlessUuidForCorrelation: '9c7e12d1-64c3-46f2-9e21-d707f05c88d9',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pumpAndSettle();

    final dialogText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(dialogText.contains('9c7e12d1-64c3-46f2-9e21-d707f05c88d9'), isFalse);
    expect(dialogText.contains('anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w'), isFalse);
    expect(dialogText, contains('singbox-client diagnostics'));
  });
}
