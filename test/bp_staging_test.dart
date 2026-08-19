import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/utils/bp_staging.dart';

void main() {
  group('classifyBp', () {
    test('no data when either reading is non-positive', () {
      expect(classifyBp(0, 80), BpStage.noData);
      expect(classifyBp(120, 0), BpStage.noData);
      expect(classifyBp(-1, 70), BpStage.noData);
    });

    test('normal: both under 120/80', () {
      expect(classifyBp(119, 79), BpStage.normal);
      expect(classifyBp(100, 70), BpStage.normal);
    });

    test('elevated: sbp 120-129 and dbp under 80', () {
      expect(classifyBp(120, 79), BpStage.elevated);
      expect(classifyBp(129, 70), BpStage.elevated);
    });

    test('stage 1 requires both sbp < 140 and dbp < 90', () {
      expect(classifyBp(130, 80), BpStage.stage1);
      expect(classifyBp(139, 89), BpStage.stage1);
      expect(classifyBp(139, 79), BpStage.stage1);
      expect(classifyBp(120, 85), BpStage.stage1);
    });

    test('stage 2 when either threshold is met (not OR-as-stage1)', () {
      expect(classifyBp(140, 90), BpStage.stage2);
      expect(classifyBp(140, 80), BpStage.stage2);
      expect(classifyBp(130, 90), BpStage.stage2);
      expect(classifyBp(139, 95), BpStage.stage2);
      expect(classifyBp(180, 120), BpStage.stage2);
    });

    test('labels match stages', () {
      expect(bpStatusLabel(110, 70), 'Normal');
      expect(bpStatusLabel(125, 75), 'Elevated');
      expect(bpStatusLabel(135, 85), 'Stage 1');
      expect(bpStatusLabel(139, 95), 'Stage 2');
      expect(bpCompactStatusLabel(0, 0), 'No data');
    });

    test('boundary: 120/80 is stage 1 not elevated', () {
      expect(classifyBp(120, 80), BpStage.stage1);
    });

    test('boundary: 130/80 is stage 1', () {
      expect(classifyBp(130, 80), BpStage.stage1);
    });

    test('boundary: 140/89 is stage 2 via sbp', () {
      expect(classifyBp(140, 89), BpStage.stage2);
    });

    test('compact label empty stage uses No data only for noData', () {
      expect(bpCompactStatusLabel(110, 70), 'Normal');
      expect(BpStage.noData.compactLabel, 'No data');
      expect(BpStage.stage1.label, 'Stage 1');
    });

    test('status colors differ by stage', () {
      final normal = bpStatusColor(110, 70);
      final stage2 = bpStatusColor(160, 100);
      expect(normal, isNot(stage2));
    });
  });
}
