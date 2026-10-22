import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;

/// The structured detail that carries an identity [reason] to the client: a
/// `google.rpc.ErrorInfo`, which the callable runtime sends in the error's
/// `details`. Null when there is no reason.
List<Map<String, Object?>>? _reasonDetails(String? reason) {
  if (reason == null) {
    return null;
  }
  return <Map<String, Object?>>[
    <String, Object?>{
      '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
      'reason': reason,
      'domain': identityErrorDomain,
    },
  ];
}

// firebase_functions 0.7 replaced its specialized HttpsError subclasses with
// HttpResponseException. These adapters preserve the existing domain-specific
// catch clauses while using the new runtime-recognized exception type.
class InvalidArgumentError extends HttpResponseException {
  InvalidArgumentError(String message, {String? reason})
    : super(
        400,
        message,
        status: 'INVALID_ARGUMENT',
        details: _reasonDetails(reason),
      );
}

/// The system is not in a state for this request (for example the identity
/// callables are switched off). Not retryable until something changes.
class FailedPreconditionError extends HttpResponseException {
  FailedPreconditionError(String message, {String? reason})
    : super(
        400,
        message,
        status: 'FAILED_PRECONDITION',
        details: _reasonDetails(reason),
      );
}

class UnauthenticatedError extends HttpResponseException {
  UnauthenticatedError(String message)
    : super(401, message, status: 'UNAUTHENTICATED');
}

class PermissionDeniedError extends HttpResponseException {
  PermissionDeniedError(String message, {String? reason})
    : super(
        403,
        message,
        status: 'PERMISSION_DENIED',
        details: _reasonDetails(reason),
      );
}

class NotFoundError extends HttpResponseException {
  NotFoundError(String message) : super(404, message, status: 'NOT_FOUND');
}

class AbortedError extends HttpResponseException {
  AbortedError(String message, {String? reason})
    : super(409, message, status: 'ABORTED', details: _reasonDetails(reason));
}

class InternalError extends HttpResponseException {
  InternalError(String message) : super(500, message, status: 'INTERNAL');
}

class UnavailableError extends HttpResponseException {
  UnavailableError(String message, {String? reason})
    : super(
        503,
        message,
        status: 'UNAVAILABLE',
        details: _reasonDetails(reason),
      );
}
