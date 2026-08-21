/// First-party, in-repo replacement for the missing KaringX `vpn_service`
/// package.
///
/// See packages/vpn_core/README.md and docs/ARCHITECTURE.md for the design.
library;

export 'src/config/singbox_config_builder.dart';
export 'src/diagnostics/diagnostics_collector.dart';
export 'src/diagnostics/diagnostics_exporter.dart';
export 'src/diagnostics/diagnostics_models.dart';
export 'src/diagnostics/network_probes.dart';
export 'src/diagnostics/redaction.dart';
export 'src/method_channel_vpn_core.dart' show MethodChannelVpnCore;
export 'src/models.dart';
export 'src/vpn_core.dart';
export 'src/vpn_core_platform_interface.dart';
