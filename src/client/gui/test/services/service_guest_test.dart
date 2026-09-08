import 'package:elp_gui/services/service_guest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses sudo only when sudo itself works, not when the script fails', () {
    final command = guestPrivilegedCommand('/opt/elemento/bin/healthcheck');

    expect(command, contains('sudo -n true'));
    expect(command, contains("sudo -n -- '/opt/elemento/bin/healthcheck'"));
    expect(
      command,
      isNot(contains("sudo -n '/opt/elemento/bin/healthcheck' 2>/dev/null ||")),
    );
  });

  test('shell-escapes single quotes in the guest path', () {
    final command = guestPrivilegedCommand("/opt/elemento/bin/it's-check");

    expect(command, contains(r"'/opt/elemento/bin/it'\''s-check'"));
  });
}
