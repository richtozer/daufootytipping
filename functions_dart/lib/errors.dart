import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;

// firebase_functions 0.7 replaced its specialized HttpsError subclasses with
// HttpResponseException. These adapters preserve the existing domain-specific
// catch clauses while using the new runtime-recognized exception type.
class InvalidArgumentError extends HttpResponseException {
  InvalidArgumentError(String message)
    : super(400, message, status: 'INVALID_ARGUMENT');
}

class UnauthenticatedError extends HttpResponseException {
  UnauthenticatedError(String message)
    : super(401, message, status: 'UNAUTHENTICATED');
}

class PermissionDeniedError extends HttpResponseException {
  PermissionDeniedError(String message)
    : super(403, message, status: 'PERMISSION_DENIED');
}

class NotFoundError extends HttpResponseException {
  NotFoundError(String message) : super(404, message, status: 'NOT_FOUND');
}

class AbortedError extends HttpResponseException {
  AbortedError(String message) : super(409, message, status: 'ABORTED');
}

class InternalError extends HttpResponseException {
  InternalError(String message) : super(500, message, status: 'INTERNAL');
}

class UnavailableError extends HttpResponseException {
  UnavailableError(String message) : super(503, message, status: 'UNAVAILABLE');
}
