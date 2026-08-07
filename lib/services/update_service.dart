import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Manages Shorebird over-the-air (OTA) updates for the Solak app.
///
/// Shorebird patches are only reachable when the installed binary was built
/// with `shorebird release android` (or `shorebird release ios-alpha`).
/// A binary built with plain `flutter build` has no engine and reports
/// `ShorebirdUpdater.isAvailable == false` — in that case this service
/// degrades silently so the rest of the app works normally.
class UpdateService {
  UpdateService() : _updater = ShorebirdUpdater();

  final ShorebirdUpdater _updater;

  int? _currentPatchNumber;
  int? get currentPatchNumber => _currentPatchNumber;

  /// Whether the Shorebird engine is present in this build.
  bool get isAvailable => _updater.isAvailable;

  Future<void> initialize() async {
    if (!_updater.isAvailable) return;

    try {
      final patch = await _updater.readCurrentPatch();
      _currentPatchNumber = patch?.number;
    } on ReadPatchException {
      // first install — no patch to read
    }
  }

  /// Checks for an available update and downloads it in the background.
  ///
  /// Safe to call on every launch. Does not block; the patch takes effect
  /// on the next cold start after download.
  Future<void> checkAndDownloadUpdate() async {
    if (!_updater.isAvailable) return;

    try {
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await _updater.update();
        final next = await _updater.readNextPatch();
        if (next != null) {
          _currentPatchNumber = next.number;
          debugPrint('[UpdateService] Patch #${next.number} ready — restart to apply');
        }
      }
    } on UpdateException catch (e) {
      debugPrint('[UpdateService] Update skipped: $e');
    }
  }
}
