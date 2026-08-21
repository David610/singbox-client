// Real, minimal replacement for the missing private
// `StatisticsRecordsScreen` -- reconstructed from its sole call site
// (group_helper.dart's traffic-statistics database list).
//
// **Honest scope note**: the real screen renders per-connection traffic
// history read from a local sqlite statistics database. Parsing that
// database's real schema and rendering charts/tables from it is a
// substantial UI feature on its own; this screen honestly reports "not
// available" for now rather than fabricate statistics data or a fake
// empty-looking table that implies real data was queried.
import 'package:flutter/material.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/theme_config.dart';

class StatisticsRecordsScreen extends StatelessWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "StatisticsRecordsScreen");
  }

  final String dbPath;
  final bool currentDB;

  const StatisticsRecordsScreen({
    super.key,
    required this.dbPath,
    required this.currentDB,
  });

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tcontext.meta.statistics)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            "Statistics record viewing is not available in this build.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: ThemeConfig.kFontSizeGroupItem),
          ),
        ),
      ),
    );
  }
}
