# FlexDocs Flutter SDK

A Flutter/Dart SDK for [FlexDocs](https://github.com/khalid-arafa/flexdocs-js) — a Backend-as-a-Service providing **Database**, **Authentication**, and **Storage** services with real-time capabilities.

## Features

- **Database**: Full CRUD, fluent query builder with MongoDB-style operators, real-time watch via Streams
- **Authentication**: Email/password, token-based, anonymous login, password management, email verification
- **Storage**: Chunked file uploads over Socket.IO with progress tracking, bucket management, file search
- **Real-time**: Live data sync via Socket.IO — watch collections and documents for changes
- **Type-safe**: Strong Dart typing with dedicated model classes
- **Retry logic**: Automatic retries with exponential backoff on network errors

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flexdocs_flutter:
    git:
      url: https://github.com/khalid-arafa/flexdocs-flutter.git
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:flexdocs_flutter/flexdocs_flutter.dart';

// Initialize with your project credentials
final creds = Credentials(
  baseUrl: 'https://your-server.com',
  projectCode: 'my-app',
  projectToken: 'your-project-token',
);

// Get service singletons
final db = FlexDocs.getDatabase(creds);
final auth = FlexDocs.getAuth(creds);
final storage = FlexDocs.getStorage(creds);
```

## Database

### Query documents

```dart
final users = await db.col('users')
  .where('age', WhereFilter(isGreaterThan: 18))
  .where('status', WhereFilter(isEqualTo: 'active'))
  .sort('name', SortDirection.ascending)
  .select(['name', 'email'])
  .page(1, 20)
  .get();
```

### CRUD operations

```dart
// Add a document
await db.col('users').add({'name': 'Alice', 'age': 30});

// Get a document
final user = await db.doc('users/user_1').get();

// Update (merge fields)
await db.doc('users/user_1').update({'age': 31});

// Replace entire document
await db.doc('users/user_1').replace({'name': 'Alice', 'age': 31});

// Delete
await db.doc('users/user_1').delete();
```

### Bulk operations

```dart
// Update many
await db.col('users').updateMany(
  filter: {'status': 'inactive'},
  newData: {'status': 'archived'},
);

// Delete many
await db.col('users').deleteMany(filter: {'status': 'archived'});
```

### Real-time watch

```dart
// Watch a collection
final stream = db.col('posts').watch();
final subscription = stream.listen((event) {
  print('Data: ${event.data}');
  print('Added: ${event.added}');
  print('Updated: ${event.updated}');
  print('Removed: ${event.removed}');
});

// Stop watching
subscription.cancel();

// Watch a single document
db.doc('users/user_1').watch().listen((event) {
  print('Action: ${event.action}'); // update or delete
  print('Doc: ${event.doc}');
});
```

### Query operators

| Dart | MongoDB | Example |
|------|---------|---------|
| `isEqualTo` | `$eq` | `WhereFilter(isEqualTo: 'active')` |
| `isNotEqualTo` | `$ne` | `WhereFilter(isNotEqualTo: 'deleted')` |
| `isGreaterThan` | `$gt` | `WhereFilter(isGreaterThan: 18)` |
| `isGreaterThanOrEqualTo` | `$gte` | `WhereFilter(isGreaterThanOrEqualTo: 18)` |
| `isLessThan` | `$lt` | `WhereFilter(isLessThan: 65)` |
| `isLessThanOrEqualTo` | `$lte` | `WhereFilter(isLessThanOrEqualTo: 100)` |
| `whereIn` | `$in` | `WhereFilter(whereIn: ['admin', 'mod'])` |
| `whereNotIn` | `$nin` | `WhereFilter(whereNotIn: ['banned'])` |
| `exists` | `$exists` | `WhereFilter(exists: true)` |
| `regex` | `$regex` | `WhereFilter(regex: '@example\\.com\$')` |

For `$and` / `$or`, use `whereRaw`:

```dart
db.col('users').whereRaw({
  '\$or': [
    {'role': 'admin'},
    {'isModerator': true},
  ]
});
```

### Collection management

```dart
await db.collections();                                    // List all
await db.createCollection(name: 'orders');                 // Create
await db.renameCollection(oldName: 'orders', newName: 'purchases'); // Rename
```

## Authentication

```dart
final auth = FlexDocs.getAuth(creds);

// Register
await auth.registerWithEmail(
  email: 'user@example.com',
  password: 'password123',
  name: 'Alice',
  roles: ['user'],
);

// Login
final response = await auth.loginWithEmail(
  email: 'user@example.com',
  password: 'password123',
);
final token = response.data['token'];

// Token login
await auth.loginWithToken(token: existingJwt);

// Anonymous login
await auth.anonymousLogin(name: 'Guest');

// Get current user
final user = await auth.getCurrentUser();

// Password management
await auth.changePassword(oldPassword: 'old123', newPassword: 'new456');
await auth.sendResetPasswordEmail(email: 'user@example.com');

// Email verification
await auth.sendEmailVerification();

// Logout
await auth.logout();
```

## Storage

### File uploads

```dart
final storage = FlexDocs.getStorage(creds);

final upload = storage.upload(
  files: [
    UploadFileInfo(name: 'photo.jpg', bytes: imageBytes, mimeType: 'image/jpeg'),
  ],
  bucketId: 'my-bucket',
);

// Track progress
upload.progress.listen((progressList) {
  for (final p in progressList) {
    print('${p.name}: ${p.progress.toStringAsFixed(1)}%');
  }
});

// Wait for completion
final urls = await upload.result;

// Cancel if needed
upload.cancel();
```

### File operations

```dart
// Get a download URL
final url = storage.getFileUrl(
  fileId: 'file123',
  filename: 'photo.jpg',
  size: '200x200', // optional resize
);

// Delete a file
await storage.deleteFile(fileId: 'file123');
```

### Bucket management

```dart
// Create
await storage.createBucket(name: 'Photos', description: 'My photos');

// Create nested bucket
await storage.createBucket(name: 'Vacation', parentId: 'parentBucketId');

// Update
await storage.updateBucket(bucketId: 'b1', name: 'Renamed');

// Get contents
await storage.getBucketContent(bucketId: 'b1', page: 1, ipp: 20);

// Search
await storage.search(searchTerm: 'vacation', bucketId: 'b1');

// Delete
await storage.deleteBucket(bucketId: 'b1');
```

## Security

- **Use HTTPS.** The SDK requires an `https://` `baseUrl` in production; plaintext
  `http://` is only accepted for `localhost`/loopback during development. This keeps
  your `projectToken` and user JWT off the wire in cleartext.
- **Store tokens securely.** The SDK never persists tokens itself — it reads them
  on demand via the `getToken` callback. Keep the user JWT (and any cached
  `projectToken`) in platform-secure storage such as
  [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
  (Keychain on iOS, Keystore-backed on Android), **not** `SharedPreferences`,
  which is plaintext.
- **Don't put tokens in shareable URLs.** `getFileUrl(..., token: ...)` embeds the
  token as a query parameter; avoid logging, persisting, or sharing those URLs.
  Prefer a short-lived, single-use download token from your backend where possible.

## Configuration

### Custom options

```dart
final db = FlexDocs.getDatabase(
  creds,
  options: ServiceOptions(
    apiOptions: ApiClientOptions(
      timeout: 10000,           // 10 second timeout
      retryAttempts: 5,         // retry up to 5 times
      retryDelay: 2000,         // start with 2s delay (doubles each retry)
      getToken: () async => savedToken,  // auth token provider
      onError: (error) => print('API error: $error'),
    ),
    socketOptions: SocketServiceOptions(
      chunkSize: 32768,         // 32KB upload chunks
      reconnectionDelay: 2000,
      onConnect: () => print('Connected'),
      onDisconnect: (reason) => print('Disconnected: $reason'),
    ),
  ),
);
```

### Logger

```dart
import 'package:flexdocs_flutter/flexdocs_flutter.dart';

// Change log level globally
logger.setLevel(LogLevel.debug);  // debug, info, warn, error, none
```

## Cleanup

```dart
// Always dispose when done to close the socket and free resources
FlexDocs.dispose();
```

## Running Tests

```bash
flutter test
```
