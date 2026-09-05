import 'dart:io';

import 'logger.dart';
import 'platform/platform.dart';

/// Credentials and address needed to talk to a stock Multipass daemon.
class MultipassConnectionConfig {
  final Uri address;
  final List<int> rootCert;
  final List<int> clientCert;
  final List<int> clientKey;

  const MultipassConnectionConfig({
    required this.address,
    required this.rootCert,
    required this.clientCert,
    required this.clientKey,
  });
}

/// Discovers stock Multipass daemon endpoints and TLS material on disk.
///
/// Returns null when Multipass does not appear to be installed / reachable
/// (missing socket, root CA, or client certificates).
MultipassConnectionConfig? discoverMultipassConnection() {
  try {
    final address = _multipassServerAddress();
    if (!_addressLooksAvailable(address)) {
      logger.w('Multipass socket/address not available: $address');
      return null;
    }

    final rootCertPath = _multipassRootCertPath();
    final rootFile = File(rootCertPath);
    if (!rootFile.existsSync()) {
      logger.w('Multipass root CA missing: $rootCertPath');
      return null;
    }

    final certDir = _multipassClientCertDir();
    final certFile = File('$certDir/multipass_cert.pem');
    final keyFile = File('$certDir/multipass_cert_key.pem');
    if (!certFile.existsSync() || !keyFile.existsSync()) {
      logger.w('Multipass client certificates missing under $certDir');
      return null;
    }

    logger.i('Discovered Multipass at $address (certs under $certDir)');
    return MultipassConnectionConfig(
      address: address,
      rootCert: rootFile.readAsBytesSync(),
      clientCert: certFile.readAsBytesSync(),
      clientKey: keyFile.readAsBytesSync(),
    );
  } catch (e, st) {
    logger.w('Failed to discover Multipass connection', error: e, stackTrace: st);
    return null;
  }
}

Uri _multipassServerAddress() {
  final override = Platform.environment['ELP_MULTIPASS_ADDRESS'];
  if (override != null && override.isNotEmpty) {
    return _parseServerAddress(override);
  }

  if (Platform.isMacOS) {
    return _parseServerAddress('unix:/var/run/multipass_socket');
  }
  if (Platform.isWindows) {
    return _parseServerAddress('localhost:50051');
  }
  // Linux: prefer snap common path, then classic /run.
  final snapCommon = Platform.environment['SNAP_COMMON'];
  if (snapCommon != null && snapCommon.isNotEmpty) {
    final snapSocket = File('$snapCommon/multipass_socket');
    if (snapSocket.existsSync()) {
      return _parseServerAddress('unix:$snapCommon/multipass_socket');
    }
  }
  const snapHostPath = '/var/snap/multipass/common/multipass_socket';
  if (File(snapHostPath).existsSync()) {
    return _parseServerAddress('unix:$snapHostPath');
  }
  return _parseServerAddress('unix:/run/multipass_socket');
}

String _multipassRootCertPath() {
  if (Platform.isMacOS) {
    return '/usr/local/etc/multipassd/multipass_root_cert.pem';
  }
  if (Platform.isWindows) {
    final programData =
        Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
    return '$programData\\Multipass\\data\\multipassd\\multipass_root_cert.pem';
  }
  final snapCommon = Platform.environment['SNAP_COMMON'];
  if (snapCommon != null && snapCommon.isNotEmpty) {
    final snapPath =
        '$snapCommon/data/multipassd/multipass_root_cert.pem';
    if (File(snapPath).existsSync()) return snapPath;
  }
  const snapHostCert =
      '/var/snap/multipass/common/data/multipassd/multipass_root_cert.pem';
  if (File(snapHostCert).existsSync()) return snapHostCert;
  return '/usr/local/etc/multipassd/multipass_root_cert.pem';
}

String _multipassClientCertDir() {
  if (Platform.isMacOS) {
    final home = mpPlatform.homeDirectory ??
        Platform.environment['HOME'] ??
        '';
    return '$home/Library/Application Support/multipass-client-certificate';
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\multipass-client-certificate';
  }
  // Linux XDG data home
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return '$xdg/multipass-client-certificate';
  }
  final home = mpPlatform.homeDirectory ??
      Platform.environment['HOME'] ??
      '';
  return '$home/.local/share/multipass-client-certificate';
}

Uri _parseServerAddress(String address) {
  final unixRegex = RegExp('unix:(.+)');
  final unixSocketPath = unixRegex.firstMatch(address)?.group(1);
  if (unixSocketPath != null) {
    return Uri(scheme: InternetAddressType.unix.name, path: unixSocketPath);
  }
  final tcpRegex = RegExp(r'^(.+):(\d+)$');
  final tcpMatch = tcpRegex.firstMatch(address);
  if (tcpMatch != null) {
    return Uri(host: tcpMatch.group(1), port: int.parse(tcpMatch.group(2)!));
  }
  throw FormatException('Invalid Multipass server address: $address');
}

bool _addressLooksAvailable(Uri address) {
  if (address.scheme == InternetAddressType.unix.name) {
    return File(address.path).existsSync();
  }
  // TCP: cannot cheaply probe without connecting; allow attempt when configured.
  return true;
}
