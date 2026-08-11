/// Coverage for typed errors (C14).
///
/// Every failure used to surface as one of three shapes — ArgumentError, a
/// bare Exception(String), or a non-throwing ApiResponse — none carrying a
/// status or a machine-readable code. Telling "wrong password" from "server
/// unreachable" meant matching on message text.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/models/api_response.dart';
import 'package:flexdocs_flutter/src/models/flexdocs_exception.dart';

ApiResponse failure(int status, {String? code, String message = 'nope'}) {
  return ApiResponse(
    ok: false,
    status: status,
    error: message,
    message: message,
    code: code,
  );
}

void main() {
  group('ApiResponse parses the server code field', () {
    Response dioResponse(int status, Map<String, dynamic> body) => Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: status,
          data: body,
        );

    test('reads code off an error body', () {
      final response = ApiResponse.fromDioResponse(
        dioResponse(404, {'message': 'Document not found', 'code': 'NOT_FOUND'}),
      );
      expect(response.ok, isFalse);
      expect(response.code, 'NOT_FOUND');
      expect(response.message, 'Document not found');
    });

    test('leaves code null on success', () {
      final response = ApiResponse.fromDioResponse(dioResponse(200, {'a': 1}));
      expect(response.ok, isTrue);
      expect(response.code, isNull);
    });

    // An API predating typed error responses still has to work.
    test('leaves code null when the server omits it', () {
      final response = ApiResponse.fromDioResponse(
        dioResponse(500, {'message': 'boom'}),
      );
      expect(response.code, isNull);
      expect(response.error, 'boom');
    });
  });

  group('FlexDocsException.fromResponse picks the subtype', () {
    test('401 is an auth failure', () {
      expect(FlexDocsException.fromResponse(failure(401)),
          isA<FlexDocsAuthException>());
    });

    test('403 is a permission failure, distinct from 401', () {
      final e = FlexDocsException.fromResponse(failure(403));
      expect(e, isA<FlexDocsPermissionException>());
      expect(e, isNot(isA<FlexDocsAuthException>()));
    });

    test('404 is not-found', () {
      expect(FlexDocsException.fromResponse(failure(404)),
          isA<FlexDocsNotFoundException>());
    });

    test('400 and 422 are validation failures', () {
      expect(FlexDocsException.fromResponse(failure(400)),
          isA<FlexDocsValidationException>());
      expect(FlexDocsException.fromResponse(failure(422)),
          isA<FlexDocsValidationException>());
    });

    test('429 is rate limiting', () {
      expect(FlexDocsException.fromResponse(failure(429)),
          isA<FlexDocsRateLimitException>());
    });

    test('5xx is a server failure', () {
      expect(FlexDocsException.fromResponse(failure(500)),
          isA<FlexDocsServerException>());
      expect(FlexDocsException.fromResponse(failure(503)),
          isA<FlexDocsServerException>());
    });

    // The distinction the old string-matching could never make reliably, and
    // the only one where retrying a non-idempotent call is safe.
    test('status 0 means the request never reached the server', () {
      expect(FlexDocsException.fromResponse(failure(0)),
          isA<FlexDocsNetworkException>());
    });

    test('an unmapped status still yields the base type, not a crash', () {
      final e = FlexDocsException.fromResponse(failure(418));
      expect(e, isA<FlexDocsException>());
      expect(e.status, 418);
    });

    test('carries code, status and message through', () {
      final e = FlexDocsException.fromResponse(
        failure(403, code: 'FORBIDDEN', message: 'Access denied'),
      );
      expect(e.code, 'FORBIDDEN');
      expect(e.status, 403);
      expect(e.message, 'Access denied');
    });

    test('every subtype is catchable as the base type', () {
      for (final status in [0, 400, 401, 403, 404, 429, 500]) {
        expect(FlexDocsException.fromResponse(failure(status)),
            isA<FlexDocsException>());
      }
    });

    test('toString names the code and status without hiding the message', () {
      final text = FlexDocsException.fromResponse(
        failure(404, code: 'NOT_FOUND', message: 'Document not found'),
      ).toString();
      expect(text, contains('Document not found'));
      expect(text, contains('NOT_FOUND'));
      expect(text, contains('404'));
    });
  });

  group('ApiResponse.orThrow', () {
    test('returns the data when the call succeeded', () {
      const response = ApiResponse(ok: true, status: 200, data: {'a': 1});
      expect(response.orThrow(), {'a': 1});
      expect(response.exception, isNull);
    });

    test('throws the matching typed exception on failure', () {
      expect(
        () => failure(403, code: 'FORBIDDEN').orThrow(),
        throwsA(isA<FlexDocsPermissionException>()),
      );
    });

    test('lets a caller separate an empty result from a denied one', () {
      // Both look identical to a read that returns [] on error, which is
      // exactly what this exists to fix.
      const empty = ApiResponse(ok: true, status: 200, data: []);
      expect(empty.orThrow(), isEmpty);
      expect(() => failure(403).orThrow(), throwsA(isA<FlexDocsException>()));
    });
  });

  group('FlexDocsUploadException', () {
    test('is a FlexDocsException carrying no HTTP status', () {
      const e = FlexDocsUploadException('Upload cancelled', code: 'UPLOAD_CANCELLED');
      expect(e, isA<FlexDocsException>());
      expect(e.status, isNull);
      expect(e.code, 'UPLOAD_CANCELLED');
    });
  });
}
