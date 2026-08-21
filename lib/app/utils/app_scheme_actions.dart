// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
// Action-name constants for the app's own `karing://` custom-scheme
// routing (deep links, LAN backup/sync, tvOS companion sync). Values are
// simple stable identifiers, not protocol-sensitive.
library;

class AppSchemeActions {
  AppSchemeActions._();

  static String scheme() => 'karing';

  static String connectAction() => 'connect';
  static String disconnectAction() => 'disconnect';
  static String reconnectAction() => 'reconnect';
  static String installConfigAction() => 'install-config';
  static String restoreBackup() => 'restore-backup';

  static String syncUploadAction() => 'sync-upload';
  static String syncDownloadAction() => 'sync-download';

  static String appleTVHost() => 'appletv';
  static String appleTVGetFileContentAction() => 'appletv-get-file-content';
  static String appleTVSyncUploadAction() => 'appletv-sync-upload';
  static String appleTVDeleteCoreConfigAction() => 'appletv-delete-core-config';
}
