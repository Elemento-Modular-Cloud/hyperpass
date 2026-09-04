import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../grpc_client.dart';

/// Opens an SSH session to [instanceName], runs [action], then closes.
Future<T> withGuestSsh<T>(
  GrpcClient grpc,
  String instanceName,
  Future<T> Function(SSHClient client) action,
) async {
  final sshInfo = await grpc.sshInfo(instanceName);
  if (sshInfo == null) {
    throw StateError('SSH is not available for $instanceName');
  }

  final pem = SSHPem.decode(sshInfo.privKeyBase64);
  final rsa = RsaKeyPair.decode(pem);
  final socket = await SSHSocket.connect(sshInfo.host, sshInfo.port);
  final client = SSHClient(
    socket,
    username: sshInfo.username,
    identities: [rsa.getPrivateKeys()],
  );

  try {
    return await action(client);
  } finally {
    client.close();
  }
}

Future<({int exitCode, String stdout, String stderr})> runGuestCommand(
  SSHClient client,
  String command,
) async {
  final result = await client.runWithResult(command);
  return (
    exitCode: result.exitCode ?? -1,
    stdout: utf8.decode(result.stdout, allowMalformed: true).trim(),
    stderr: utf8.decode(result.stderr, allowMalformed: true).trim(),
  );
}

/// Prefer passwordless sudo; fall back to the bare path if sudo is unavailable.
String guestPrivilegedCommand(String path) {
  final escaped = path.replaceAll("'", r"'\''");
  return "sudo -n '$escaped' 2>/dev/null || '$escaped'";
}
