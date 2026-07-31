import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/model_value_parser.dart';

void main() {
  test('optional integer accepts numbers and rejects implicit strings', () {
    expect(readOptionalInt(null, 'value'), isNull);
    expect(readOptionalInt(12, 'value'), 12);
    expect(readOptionalInt(12.8, 'value'), 12);
    expect(
      () => readOptionalInt('12', 'value'),
      throwsA(isA<FormatException>()),
    );
  });

  test('integer list validates its container and every item', () {
    expect(readIntList(null, 'ids'), isEmpty);
    expect(readIntList(<num>[1, 2.9], 'ids'), <int>[1, 2]);
    expect(
      () => readIntList(<Object?>[1, '2'], 'ids'),
      throwsA(isA<FormatException>()),
    );
    expect(() => readIntList('1,2', 'ids'), throwsA(isA<FormatException>()));
  });

  test('optional date accepts database and import formats', () {
    final timestamp = DateTime(2026, 7, 31).millisecondsSinceEpoch;

    expect(
      readOptionalDate(timestamp, 'date')?.millisecondsSinceEpoch,
      timestamp,
    );
    expect(
      readOptionalDate('$timestamp', 'date')?.millisecondsSinceEpoch,
      timestamp,
    );
    expect(readOptionalDate('2026-07-31', 'date'), DateTime(2026, 7, 31));
    expect(
      () => readOptionalDate('not-a-date', 'date'),
      throwsA(isA<FormatException>()),
    );
  });
}
