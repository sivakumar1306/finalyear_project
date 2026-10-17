import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/utils/ring_names.dart';

void main() {
  test('ring model names are accepted', () {
    expect(isRingDeviceName('R08_B406'), isTrue);
    expect(isRingDeviceName('R02_1234'), isTrue);
    expect(isRingDeviceName('QC_RING'), isTrue);
    expect(isRingDeviceName('SUNDR Ring'), isTrue);
  });

  test('previously bonded headphones are not rings', () {
    expect(isRingDeviceName('QCY T13'), isFalse);
    expect(isRingDeviceName('Realme Buds Air'), isFalse);
    expect(isRingDeviceName('Sony WH-1000XM4'), isFalse);
    expect(isRingDeviceName('Galaxy Buds'), isFalse);
    expect(isRingDeviceName(''), isFalse);
    expect(isRingDeviceName('   '), isFalse);
  });
}
