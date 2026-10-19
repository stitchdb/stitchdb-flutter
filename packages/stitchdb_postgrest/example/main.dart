import 'package:stitchdb_postgrest/stitchdb_postgrest.dart';

/// Example to use with StitchDB API https://stitchdb.com/
dynamic main() async {
  const stitchUrl = '';
  const stitchKey = '';
  final client = PostgrestClient(
    '$stitchUrl/rest/v1',
    headers: {'apikey': stitchKey},
    schema: 'public',
  );
  try {
    final response = await client.from('countries').select();
    print(response);
  } on PostgrestException catch (e) {
    // handle PostgrestError
    print(e.code);
    print(e.message);
  }
}
