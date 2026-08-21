/// First-party, in-repo replacement for the missing KaringX `vpn_service`
/// package.
///
/// See packages/vpn_core/README.md and docs/ARCHITECTURE.md for the design.
library;

export 'src/config/singbox_config_builder.dart';
export 'src/method_channel_vpn_core.dart' show MethodChannelVpnCore;
export 'src/models.dart';
export 'src/vpn_core.dart';
export 'src/vpn_core_platform_interface.dart';
