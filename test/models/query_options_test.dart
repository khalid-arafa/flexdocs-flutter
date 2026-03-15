import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/models/query_options.dart';

void main() {
  group('SortDirection', () {
    test('ascending has value 1', () {
      expect(SortDirection.ascending.value, 1);
    });

    test('descending has value -1', () {
      expect(SortDirection.descending.value, -1);
    });
  });

  group('WhereFilter', () {
    test('equality-only returns simple value', () {
      final filter = WhereFilter(isEqualTo: 'active');
      expect(filter.toFilterValue(), 'active');
    });

    test('numeric equality returns simple value', () {
      final filter = WhereFilter(isEqualTo: 42);
      expect(filter.toFilterValue(), 42);
    });

    test('single operator returns map', () {
      final filter = WhereFilter(isGreaterThan: 18);
      expect(filter.toFilterValue(), {'\$gt': 18});
    });

    test('multiple operators return combined map', () {
      final filter = WhereFilter(isGreaterThanOrEqualTo: 18, isLessThan: 65);
      final result = filter.toFilterValue() as Map<String, dynamic>;
      expect(result['\$gte'], 18);
      expect(result['\$lt'], 65);
    });

    test('whereIn operator', () {
      final filter = WhereFilter(whereIn: ['admin', 'mod']);
      expect(filter.toFilterValue(), {'\$in': ['admin', 'mod']});
    });

    test('whereNotIn operator', () {
      final filter = WhereFilter(whereNotIn: ['banned']);
      expect(filter.toFilterValue(), {'\$nin': ['banned']});
    });

    test('exists operator', () {
      final filter = WhereFilter(exists: true);
      expect(filter.toFilterValue(), {'\$exists': true});
    });

    test('regex operator', () {
      final filter = WhereFilter(regex: '@example\\.com\$');
      expect(filter.toFilterValue(), {'\$regex': '@example\\.com\$'});
    });

    test('notEqualTo operator', () {
      final filter = WhereFilter(isNotEqualTo: 'deleted');
      expect(filter.toFilterValue(), {'\$ne': 'deleted'});
    });

    test('equality with other operators returns map with \$eq', () {
      final filter = WhereFilter(isEqualTo: 'x', isNotEqualTo: 'y');
      final result = filter.toFilterValue() as Map<String, dynamic>;
      expect(result['\$eq'], 'x');
      expect(result['\$ne'], 'y');
    });
  });
}
