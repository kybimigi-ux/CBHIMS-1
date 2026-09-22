import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service that persists workspace settings locally using
/// shared_preferences. Settings survive app restarts.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;
  bool _initialized = false;

  // Keys
  static const _kAppName = 'settings_app_name';
  static const _kLowStockAlerts = 'settings_low_stock_alerts';
  static const _kInboundNotices = 'settings_inbound_notices';
  static const _kEmailSummaries = 'settings_email_summaries';
  static const _kNotificationBanner = 'settings_notification_banner';

  /// Must be called once at app startup (or lazily on first access).
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  // ---------------------------------------------------------------------------
  // Getters (synchronous after init)
  // ---------------------------------------------------------------------------

  String get appName {
    final val = _prefs?.getString(_kAppName);
    if (val == null || val == 'Celis Brothers Hardware - CBHIMS') {
      return 'STOKADO';
    }
    return val;
  }

  bool get lowStockAlerts => _prefs?.getBool(_kLowStockAlerts) ?? true;

  bool get inboundNotices => _prefs?.getBool(_kInboundNotices) ?? true;

  bool get emailSummaries => _prefs?.getBool(_kEmailSummaries) ?? false;

  bool get notificationBannerEnabled => _prefs?.getBool(_kNotificationBanner) ?? true;

  // ---------------------------------------------------------------------------
  // Setters (async — write to disk)
  // ---------------------------------------------------------------------------

  Future<void> setAppName(String value) async {
    await _ensureInit();
    await _prefs?.setString(_kAppName, value);
  }

  Future<void> setLowStockAlerts(bool value) async {
    await _ensureInit();
    await _prefs?.setBool(_kLowStockAlerts, value);
  }

  Future<void> setInboundNotices(bool value) async {
    await _ensureInit();
    await _prefs?.setBool(_kInboundNotices, value);
  }

  Future<void> setEmailSummaries(bool value) async {
    await _ensureInit();
    await _prefs?.setBool(_kEmailSummaries, value);
  }

  Future<void> setNotificationBannerEnabled(bool value) async {
    await _ensureInit();
    await _prefs?.setBool(_kNotificationBanner, value);
  }
}
