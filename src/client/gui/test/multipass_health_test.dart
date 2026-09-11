import 'package:elp_gui/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing Multipass is hidden and does not degrade health', () {
    final status = resolveMultipassSidebarStatus(
      showEnabled: true,
      discovered: false,
      needsAuth: false,
      clientAvailable: false,
      online: false,
    );
    expect(status, MultipassSidebarStatus.hidden);
    expect(isSystemHealthy(true, status), isTrue);
  });

  test('installed but down Multipass is offline and degrades health', () {
    final status = resolveMultipassSidebarStatus(
      showEnabled: true,
      discovered: true,
      needsAuth: false,
      clientAvailable: false,
      online: false,
    );
    expect(status, MultipassSidebarStatus.offline);
    expect(isSystemHealthy(true, status), isFalse);
  });

  test('disabled Multipass stays healthy when elpd is up', () {
    final status = resolveMultipassSidebarStatus(
      showEnabled: false,
      discovered: true,
      needsAuth: false,
      clientAvailable: true,
      online: true,
    );
    expect(status, MultipassSidebarStatus.disabled);
    expect(isSystemHealthy(true, status), isTrue);
  });

  test('elpd down is unhealthy even when Multipass is hidden', () {
    expect(isSystemHealthy(false, MultipassSidebarStatus.hidden), isFalse);
  });
}
