import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw caught error into something safe to show a user, logging the
/// real one via debugPrint first so it isn't lost for debugging -- this app
/// has no crash-reporting service, so a console log is the only trace of it.
String humanizeError(Object error, {String context = ''}) {
  debugPrint('${context.isNotEmpty ? '$context: ' : ''}$error');

  final raw = error.toString().toLowerCase();

  final isNetworkIssue = raw.contains('sslv3') ||
      raw.contains('handshake') ||
      raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('connection') ||
      raw.contains('timeoutexception') ||
      raw.contains('failed host lookup');

  if (isNetworkIssue) {
    return 'Network issue — check your connection and try again.';
  }

  // Supabase Auth already writes these in plain English for end users
  // (e.g. "Password should be at least 6 characters", "Invalid login
  // credentials") -- pass it through instead of masking a real, actionable
  // message.
  if (error is AuthException) return error.message;

  // PostgrestException is NOT given the same treatment -- its messages can
  // leak raw constraint/column/SQL detail, so it falls through to the
  // generic message instead of the plain-Exception branch below.
  if (error is PostgrestException) {
    return 'Something went wrong. Please try again.';
  }

  // A bare `throw Exception('...')` is how this codebase already signals a
  // deliberate, human-written message (e.g. "Not logged in", "Insufficient
  // wallet balance") -- show it, stripping Dart's own "Exception: " prefix.
  if (error is Exception) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  return 'Something went wrong. Please try again.';
}
