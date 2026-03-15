/// Sort direction for query results.
enum SortDirection {
  ascending(1),
  descending(-1);

  final int value;
  const SortDirection(this.value);
}

/// Builds a MongoDB-style filter map from named parameters.
///
/// Usage:
/// ```dart
/// col.where('age', WhereFilter(isGreaterThan: 18, isLessThan: 65));
/// ```
class WhereFilter {
  final dynamic isEqualTo;
  final dynamic isNotEqualTo;
  final dynamic isGreaterThan;
  final dynamic isGreaterThanOrEqualTo;
  final dynamic isLessThan;
  final dynamic isLessThanOrEqualTo;
  final List<dynamic>? whereIn;
  final List<dynamic>? whereNotIn;
  final bool? exists;
  final String? regex;

  const WhereFilter({
    this.isEqualTo,
    this.isNotEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.whereIn,
    this.whereNotIn,
    this.exists,
    this.regex,
  });

  /// Converts this filter to a MongoDB-style operator map.
  ///
  /// Returns a simple value for equality, or a map of operators.
  dynamic toFilterValue() {
    if (isEqualTo != null &&
        isNotEqualTo == null &&
        isGreaterThan == null &&
        isGreaterThanOrEqualTo == null &&
        isLessThan == null &&
        isLessThanOrEqualTo == null &&
        whereIn == null &&
        whereNotIn == null &&
        exists == null &&
        regex == null) {
      return isEqualTo;
    }

    final map = <String, dynamic>{};
    if (isEqualTo != null) map['\$eq'] = isEqualTo;
    if (isNotEqualTo != null) map['\$ne'] = isNotEqualTo;
    if (isGreaterThan != null) map['\$gt'] = isGreaterThan;
    if (isGreaterThanOrEqualTo != null) map['\$gte'] = isGreaterThanOrEqualTo;
    if (isLessThan != null) map['\$lt'] = isLessThan;
    if (isLessThanOrEqualTo != null) map['\$lte'] = isLessThanOrEqualTo;
    if (whereIn != null) map['\$in'] = whereIn;
    if (whereNotIn != null) map['\$nin'] = whereNotIn;
    if (exists != null) map['\$exists'] = exists;
    if (regex != null) map['\$regex'] = regex;
    return map;
  }
}
