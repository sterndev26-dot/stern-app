import '../utils/constants.dart';

enum SternTypes {
  soapDispenser,
  foamSoapDispenser,
  faucet,
  shower,
  urinal,
  wc,
  waveOnOff,
  unpluggedConnectors,
}

extension SternTypesExtension on SternTypes {
  String get displayName {
    switch (this) {
      case SternTypes.soapDispenser:
        return 'Soap Dispenser';
      case SternTypes.foamSoapDispenser:
        return 'Foam Soap Dispenser';
      case SternTypes.faucet:
        return 'Faucet';
      case SternTypes.shower:
        return 'Shower';
      case SternTypes.urinal:
        return 'Urinal';
      case SternTypes.wc:
        return 'WC';
      case SternTypes.waveOnOff:
        return 'Wave On/Off';
      case SternTypes.unpluggedConnectors:
        return 'Unplugged';
    }
  }

  String get imagePath {
    switch (this) {
      case SternTypes.soapDispenser:
        return 'assets/images/soapel.png';
      case SternTypes.foamSoapDispenser:
        return 'assets/images/foam.png';
      case SternTypes.faucet:
        return 'assets/images/sinkel.png';
      case SternTypes.shower:
        return 'assets/images/shower.png';
      case SternTypes.urinal:
        return 'assets/images/urinal.png';
      case SternTypes.wc:
        return 'assets/images/toilet.png';
      case SternTypes.waveOnOff:
        return 'assets/images/hand.png';
      case SternTypes.unpluggedConnectors:
        return 'assets/images/unplugged_connectors.png';
    }
  }

  static SternTypes fromUuid(String uuid) {
    switch (uuid.toLowerCase()) {
      case BleGattAttributes.sternSoapUuid:
        return SternTypes.soapDispenser;
      case BleGattAttributes.sternFoamSoapUuid:
        return SternTypes.foamSoapDispenser;
      case BleGattAttributes.sternFaucetUuid:
        return SternTypes.faucet;
      case BleGattAttributes.sternShowerUuid:
        return SternTypes.shower;
      case BleGattAttributes.sternUrinalUuid:
        return SternTypes.urinal;
      case BleGattAttributes.sternWcUuid:
        return SternTypes.wc;
      case BleGattAttributes.sternWaveOnOffUuid:
        return SternTypes.waveOnOff;
      default:
        return SternTypes.unpluggedConnectors;
    }
  }

  static SternTypes fromString(String name) {
    switch (name) {
      case 'SOAP_DISPENSER':
        return SternTypes.soapDispenser;
      case 'FOAM_SOAP_DISPENSER':
        return SternTypes.foamSoapDispenser;
      case 'FAUCET':
        return SternTypes.faucet;
      case 'SHOWER':
        return SternTypes.shower;
      case 'URINAL':
        return SternTypes.urinal;
      case 'WC':
        return SternTypes.wc;
      case 'WAVE_ON_OFF':
        return SternTypes.waveOnOff;
      default:
        return SternTypes.unpluggedConnectors;
    }
  }

  String toStorageString() {
    return name.toUpperCase();
  }
}
