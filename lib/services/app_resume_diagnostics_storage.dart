import 'app_resume_diagnostics_storage_contract.dart';
import 'app_resume_diagnostics_storage_stub.dart'
    if (dart.library.io) 'app_resume_diagnostics_storage_io.dart'
    as implementation;

export 'app_resume_diagnostics_storage_contract.dart';

Future<ResumeDiagnosticsStorage> createResumeDiagnosticsStorage() {
  return implementation.createResumeDiagnosticsStorage();
}
