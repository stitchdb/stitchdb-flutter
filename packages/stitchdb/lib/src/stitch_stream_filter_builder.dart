part of './stitch_stream_builder.dart';

class StitchStreamFilterBuilder extends StitchStreamBuilder {
  StitchStreamFilterBuilder({
    required super.queryBuilder,
    required super.realtimeTopic,
    required super.realtimeClient,
    required super.schema,
    required super.table,
    required super.primaryKey,
    required super.private,
  });

  /// Filters the results where [column] equals [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).eq('name', 'StitchDB');
  /// ```
  StitchStreamFilterBuilder eq(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.eq,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] does not equal [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).neq('name', 'StitchDB');
  /// ```
  StitchStreamFilterBuilder neq(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.neq,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is less than [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).lt('likes', 100);
  /// ```
  StitchStreamFilterBuilder lt(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.lt,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is less than or equal to [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).lte('likes', 100);
  /// ```
  StitchStreamFilterBuilder lte(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.lte,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is greater than [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).gt('likes', '100');
  /// ```
  StitchStreamFilterBuilder gt(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.gt,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is greater than or equal to [value].
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).gte('likes', 100);
  /// ```
  StitchStreamFilterBuilder gte(String column, Object value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.gte,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is included in [values].
  ///
  /// ```dart
  /// stitchdb
  ///     .from('users')
  ///     .stream(primaryKey: ['id'])
  ///     .inFilter('name', ['Andy', 'Amy', 'Terry']);
  /// ```
  StitchStreamFilterBuilder inFilter(String column, List<Object> values) {
    _streamFilters.add((
      type: PostgresChangeFilterType.inFilter,
      column: column,
      value: values,
    ));
    return this;
  }

  /// Filters the results where [column] matches the [pattern] case-sensitive.
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).like('title', '%foo%');
  /// ```
  StitchStreamFilterBuilder like(String column, String pattern) {
    _streamFilters.add((
      type: PostgresChangeFilterType.like,
      column: column,
      value: pattern,
    ));
    return this;
  }

  /// Filters the results where [column] matches the [pattern] case-insensitive.
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).ilike('title', '%foo%');
  /// ```
  StitchStreamFilterBuilder ilike(String column, String pattern) {
    _streamFilters.add((
      type: PostgresChangeFilterType.ilike,
      column: column,
      value: pattern,
    ));
    return this;
  }

  /// Filters the results where [column] matches the PostgreSQL regular
  /// expression [pattern] case-sensitive.
  ///
  /// ```dart
  /// stitchdb
  ///     .from('users')
  ///     .stream(primaryKey: ['id'])
  ///     .matchRegex('slug', r'^post-\d+$');
  /// ```
  StitchStreamFilterBuilder matchRegex(String column, String pattern) {
    _streamFilters.add((
      type: PostgresChangeFilterType.match,
      column: column,
      value: pattern,
    ));
    return this;
  }

  /// Filters the results where [column] matches the PostgreSQL regular
  /// expression [pattern] case-insensitive.
  ///
  /// ```dart
  /// stitchdb
  ///     .from('users')
  ///     .stream(primaryKey: ['id'])
  ///     .imatchRegex('slug', r'^post-\d+$');
  /// ```
  StitchStreamFilterBuilder imatchRegex(String column, String pattern) {
    _streamFilters.add((
      type: PostgresChangeFilterType.imatch,
      column: column,
      value: pattern,
    ));
    return this;
  }

  /// Filters the results where [column] is `null`, `true` or `false`.
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).isFilter('data', null);
  /// ```
  StitchStreamFilterBuilder isFilter(String column, bool? value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.isFilter,
      column: column,
      value: value,
    ));
    return this;
  }

  /// Filters the results where [column] is not equal to [value] treating `null`
  /// as a distinct value.
  ///
  /// ```dart
  /// stitchdb.from('users').stream(primaryKey: ['id']).isDistinct('age', null);
  /// ```
  StitchStreamFilterBuilder isDistinct(String column, Object? value) {
    _streamFilters.add((
      type: PostgresChangeFilterType.isDistinct,
      column: column,
      value: value,
    ));
    return this;
  }
}
