import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/models/api_response.dart';

void main() {
  group('ApiResponse', () {
    test('creates a successful response', () {
      final response = ApiResponse(
        ok: true,
        status: 200,
        data: {'id': '123'},
      );

      expect(response.ok, isTrue);
      expect(response.status, 200);
      expect(response.data, {'id': '123'});
      expect(response.error, isNull);
    });

    test('creates an error response', () {
      final response = ApiResponse.error(error: 'Not found', status: 404);

      expect(response.ok, isFalse);
      expect(response.status, 404);
      expect(response.error, 'Not found');
      expect(response.data, isNull);
    });

    test('error factory defaults status to 0', () {
      final response = ApiResponse.error(error: 'Network error');
      expect(response.status, 0);
    });
  });

  group('ApiResponse.fromDioResponse', () {
    // Note: DioResponse tests are deferred to api_client_test.dart
    // since they require Dio dependency. Here we test the pure constructors.
    test('toString returns summary', () {
      final response = ApiResponse(ok: true, status: 200);
      expect(response.toString(), 'ApiResponse(ok: true, status: 200)');
    });
  });
}
