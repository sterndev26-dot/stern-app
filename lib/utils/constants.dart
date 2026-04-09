class AppConstants {
  // Shared preferences keys
  static const String sharedPrefName = 'stern.msapps.com.stern';
  static const String sharedPrefTechnicianPassword = '4321';
  static const String sharedPrefUserPassword = 'shared_pref_user_password';
  static const String sharedPrefPasswordGeneral = 'shared_pref_password_general';
  static const String sharedPrefUserHandleId = 'event_set_data';
  static const String sharedPrefSternProductPresets = 'product_presets';
  static const String sharedPrefCleanFilter = 'clean_filter';
  static const String sharedPrefSoapRefill = 'soap_refill';
  static const String sharedDontLoadData = 'shared_dont_load_data';
  static const String sharedShortcutToMainScreen = 'shared_shorcut_to_main_screen';
  static const String sharedUserType = 'user_type';

  // App colors
  static const int appBlueColorHex = 0xFF1A73E8;
  static const int appWhiteHex = 0xFFFFFFFF;
  static const int appBlackTextHex = 0xFF212121;
}

class BleGattAttributes {
  // Device identification UUIDs
  static const String sternDeviceUuid = '00002a04-0000-1000-8000-00805f9b34fb';

  // Product type service UUIDs
  static const String sternUnknownUuid = '00001000-0000-1000-8000-00805f9b34fb';
  static const String sternFaucetUuid = '00001001-0000-1000-8000-00805f9b34fb';
  static const String sternShowerUuid = '00001002-0000-1000-8000-00805f9b34fb';
  static const String sternWcUuid = '00001003-0000-1000-8000-00805f9b34fb';
  static const String sternUrinalUuid = '00001004-0000-1000-8000-00805f9b34fb';
  static const String sternWaveUuid = '00001005-0000-1000-8000-00805f9b34fb';
  static const String sternSoapUuid = '00001006-0000-1000-8000-00805f9b34fb';
  static const String sternWaveOnOffUuid = '00001007-0000-1000-8000-00805f9b34fb';
  static const String sternFoamSoapUuid = '00001008-0000-1000-8000-00805f9b34fb';

  // Services
  static const String uuidDataInformationService = '00001300-5374-4563-5561-466e52655473';
  static const String uuidCalenderService = '00001000-5374-4563-5561-466e52655473';
  static const String uuidDataOperateService = '00001200-5374-4563-5561-466e52655473';
  static const String uuidLightService = '00001f00-5374-4563-5561-466e52655473';
  static const String uuidDataSettingsService = '00001100-5374-4563-5561-466e52655473';
  static const String uuidStatisticsInfoService = '00001200-5374-4563-5561-466e52655473';
  static const String uuidWatchService = '00001600-1212-EFDE-1523-785FEABCD123';

  // Characteristics
  static const String uuidCalenderCharacteristicReadWrite = '00001001-5374-4563-5561-466e52655473';
  static const String uuidOpenCloseValveWrite = '00001205-5374-4563-5561-466e52655473';
  static const String uuidOpenCloseValveNotification = '00001203-5374-4563-5561-466e52655473';
  static const String uuidInformationWrite = '00001304-5374-4563-5561-466e52655473';
  static const String uuidOperateReadWrite = '00001203-5374-4563-5561-466e52655473';
  static const String uuidStatisticsInfo = '00001204-5374-4563-5561-466e52655473';
  static const String uuidInformationRead = '00001303-5374-4563-5561-466e52655473';
  static const String uuidScheduledCharacteristic = '00001301-5374-4563-5561-466e52655473';
  static const String uuidHygieneFlushStandbyReadWriteNotify = '00001303-5374-4563-5561-466e52655473';
  static const String uuidWatchReadNotify = '00001601-1212-EFDE-1523-785FEABCD123';
  static const String uuidResetCharacteristic = '00001fff-5374-4563-5561-466e52655473';
  static const String uuidLightWrite = '00001502-1212-EFDE-1523-785FEABCD123';
  static const String uuidLightReadNotify = '00001f01-5374-4563-5561-466e52655473';

  // Settings characteristics
  static const String uuidSettingsGeneralRead = '00001101-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesDelayIn = '00001101-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesDelayOut = '00001102-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesLongFlush = '00001103-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesShortWash = '00001104-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesSecurityTime = '00001105-5374-4563-5561-466e52655473';
  static const String uuidSettingsRemotesBetweenTime = '00001106-5374-4563-5561-466e52655473';
  static const String uuidSettingsDetectionRange = '00001122-5374-4563-5561-466e52655473';
  static const String uuidSettingsSimpleControls = '00001120-5374-4563-5561-466e52655473';
  static const String uuidSettingsSoapDosage = '00001124-5374-4563-5561-466e52655473';
  static const String uuidSettingsFoamSoap = '00001123-5374-4563-5561-466e52655473';
  static const String uuidWaterSoapActivityStatistics = '00001204-5374-4563-5561-466e52655473';
}
