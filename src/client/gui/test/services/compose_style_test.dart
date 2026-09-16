import 'package:elp_gui/brand.dart';
import 'package:elp_gui/services/compose/compose_style.dart';
import 'package:elp_gui/services/service_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known contracts keep distinct colors', () {
    expect(
      composeContractColor(openaiCompatibleContract),
      Brand.workloadAi,
    );
    expect(composeContractColor(caddyCaContract), Brand.info);
    expect(composeContractColor('qdrant'), Brand.workloadVm);
    expect(
      composeContractColor(openaiCompatibleContract),
      isNot(composeContractColor(caddyCaContract)),
    );
  });

  test('unknown contracts hash stably', () {
    expect(composeContractColor('minio'), composeContractColor('minio'));
    expect(composeContractColor('minio'), isNot(composeContractColor('redis')));
  });

  testWidgets('multiple pin paints three pips instead of a solid fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ComposePinBullet(
                key: ValueKey('single'),
                color: Colors.teal,
                multiple: false,
              ),
              ComposePinBullet(
                key: ValueKey('multiple'),
                color: Colors.teal,
                multiple: true,
              ),
            ],
          ),
        ),
      ),
    );

    final single = tester.widget<ComposePinBullet>(
      find.byKey(const ValueKey('single')),
    );
    final multiple = tester.widget<ComposePinBullet>(
      find.byKey(const ValueKey('multiple')),
    );
    expect(single.multiple, isFalse);
    expect(multiple.multiple, isTrue);
    expect(find.byType(ComposePinBullet), findsNWidgets(2));
  });

  test('workload tab colors match the resource monitor', () {
    expect(composeWorkloadTabColor(0), Brand.workloadService);
    expect(composeWorkloadTabColor(1), Brand.workloadVm);
    expect(composeWorkloadTabColor(2), Brand.workloadAi);
  });
}
