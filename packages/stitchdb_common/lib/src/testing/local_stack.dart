import 'package:meta/meta.dart';

/// Host the local StitchDB CLI stack is reachable at.
@visibleForTesting
const localStackHost = '127.0.0.1';

/// Port of the API gateway of the local StitchDB CLI stack.
@visibleForTesting
const localStackPort = 54421;

/// Base URL of the API gateway, which every service is exposed through.
@visibleForTesting
const localStackUrl = 'http://$localStackHost:$localStackPort';

/// PostgREST endpoint of the local stack.
@visibleForTesting
const localStackRestUrl = '$localStackUrl/rest/v1';

/// Auth endpoint of the local stack.
@visibleForTesting
const localStackAuthUrl = '$localStackUrl/auth/v1';

/// Storage endpoint of the local stack.
@visibleForTesting
const localStackStorageUrl = '$localStackUrl/storage/v1';

/// Realtime WebSocket endpoint of the local stack.
@visibleForTesting
const localStackRealtimeUrl =
    'ws://$localStackHost:$localStackPort/realtime/v1';

/// Web interface of the mail server of the local stack, which collects the
/// mails the auth service would have sent. The `[inbucket]` section of
/// `stitchdb/config.toml` exposes it.
@visibleForTesting
const localStackMailPort = 54424;

/// Base URL of the mail server web interface of the local stack.
@visibleForTesting
const localStackMailUrl = 'http://$localStackHost:$localStackMailPort';

/// Port Postgres itself is exposed on, for tests that need to run SQL.
@visibleForTesting
const localStackDatabasePort = 54422;

/// Database of the local stack.
@visibleForTesting
const localStackDatabaseName = 'postgres';

/// Username of the Postgres superuser of the local stack.
@visibleForTesting
const localStackDatabaseUsername = 'postgres';

/// Password of the Postgres superuser of the local stack.
@visibleForTesting
const localStackDatabasePassword = 'postgres';

/// Anon API key of the local stack.
///
/// An RS256 JWT signed by the committed `stitchdb/signing_keys.json`, so it
/// stays valid as long as that key is in place. The services verify it against
/// the JWKS the key is published as.
@visibleForTesting
const localStackAnonKey =
    'eyJhbGciOiJSUzI1NiIsImtpZCI6IjNkZjU5YWIxLWI4ZWMtNDlkMy05YzkyLThiOWQ0MmNhYzFmZSIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdGl0Y2hkYi1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjIwOTY4OTUxOTF9._RnnbOw3dDjSQL6VWFf7PtxvUlXFL2rqVM3POxyTOUM';

/// Service role API key of the local stack, which bypasses row level security.
///
/// Signed like [localStackAnonKey].
@visibleForTesting
const localStackServiceRoleKey =
    'eyJhbGciOiJSUzI1NiIsImtpZCI6IjNkZjU5YWIxLWI4ZWMtNDlkMy05YzkyLThiOWQ0MmNhYzFmZSIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdGl0Y2hkYi1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MjA5Njg5NTE5Mn0.deGp5scUHGpJug94vJ9J5k9W_zBNHuIKR3MKUNImdIM';

/// Secret the local stack signs and verifies HS256 tokens with.
@visibleForTesting
const localStackJwtSecret =
    'super-secret-jwt-token-with-at-least-32-characters-long';
