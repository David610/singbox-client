#
# Run `pod lib lint vpn_core.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'vpn_core'
  s.version          = '0.1.0'
  s.summary          = 'First-party in-repo replacement for the missing KaringX vpn_service package.'
  s.description      = <<-DESC
  Typed Dart <-> native bridge to a pinned public sing-box/libbox core, via
  NEPacketTunnelProvider on iOS. See docs/ARCHITECTURE.md.
  DESC
  s.homepage         = 'https://github.com/David610/singbox-client'
  s.license          = { :file => '../LICENSE.md' }
  s.author           = { 'singbox-client' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # The pinned sing-box/libbox core is NOT vendored as source in this
  # repository (it is Go, built by the upstream sing-box build system). A
  # developer produces Libbox.xcframework locally by running
  # packages/vpn_core/native/singbox-go/build_ios.sh (documented in
  # docs/BUILDING.md) and drops it at packages/vpn_core/ios/Frameworks/.
  #
  # Deliberately NOT vendored from this podspec: `flutter_install_all_ios_pods`
  # (ios/Podfile) links every Flutter plugin pod, this one included, into
  # the Runner *host app* target only -- there is no separate CocoaPods
  # integration for the PacketTunnel Network Extension target. Only the
  # extension calls into libbox (VpnCorePlugin.swift talks to
  # NETunnelProviderManager, a public framework, not libbox directly), so
  # Libbox.xcframework is linked straight into the PacketTunnel target in
  # ios/Runner.xcodeproj/project.pbxproj instead. Uncommenting
  # `s.vendored_frameworks` here would link libbox into Runner too, which
  # is neither needed nor wanted.
  # s.vendored_frameworks = 'Frameworks/Libbox.xcframework'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
