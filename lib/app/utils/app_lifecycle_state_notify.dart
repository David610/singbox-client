// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

typedef _StateCallback = FutureOr<void> Function();

class AppLifecycleStateNofity extends WidgetsBindingObserver {
  AppLifecycleStateNofity._();

  static final AppLifecycleStateNofity _instance = AppLifecycleStateNofity._();

  static final Map<Object, _StateCallback> _resumedCallbacks = {};
  static final Map<Object, _StateCallback> _pausedCallbacks = {};

  static bool _paused = false;

  static void init() {
    WidgetsBinding.instance.addObserver(_instance);
  }

  static void uninit() {
    WidgetsBinding.instance.removeObserver(_instance);
    _resumedCallbacks.clear();
    _pausedCallbacks.clear();
  }

  static bool isPaused() => _paused;

  static void onStateResumed(Object? key, _StateCallback? callback) {
    final k = key ?? callback;
    if (callback == null || k == null) {
      if (k != null) {
        _resumedCallbacks.remove(k);
      }
      return;
    }
    _resumedCallbacks[k] = callback;
  }

  static void onStatePaused(Object? key, _StateCallback? callback) {
    final k = key ?? callback;
    if (callback == null || k == null) {
      if (k != null) {
        _pausedCallbacks.remove(k);
      }
      return;
    }
    _pausedCallbacks[k] = callback;
  }

  static Future<void> updateState() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.resumed) {
      await stateResumed('resumed');
    } else if (state == AppLifecycleState.paused) {
      await statePaused('paused');
    } else if (state != null) {
      await stateInactive(state.name);
    }
  }

  static Future<void> stateLaunch(bool launchAtStartup) async {
    _paused = false;
  }

  static Future<void> stateResumed(String reason) async {
    _paused = false;
    for (final cb in List<_StateCallback>.from(_resumedCallbacks.values)) {
      await cb();
    }
  }

  static Future<void> statePaused(String reason) async {
    _paused = true;
    for (final cb in List<_StateCallback>.from(_pausedCallbacks.values)) {
      await cb();
    }
  }

  static Future<void> stateInactive(String reason) async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(updateState());
  }
}
