// ignore_for_file: avoid_print

import 'package:stitchdb_functions/stitchdb_functions.dart';

/// Example to use with StitchDB Edge Functions https://stitchdb.com/
Future<void> main() async {
  const stitchUrl = '';
  const stitchKey = '';
  final client = FunctionsClient(
    '$stitchUrl/functions/v1',
    {
      'Authorization': 'Bearer $stitchKey',
    },
  );

  try {
    final response = await client.invoke(
      'get_countries',
      body: {'name': 'The Shire'},
    );
    print('status: ${response.status}');
    print('data: ${response.data}');
  } on FunctionException catch (error) {
    print('Function error: ${error.status} ${error.details}');
  }
}
