abstract class ResumeDiagnosticsStorage {
  Future<List<String>> readLines();

  Future<void> appendLine(String encodedEvent);

  Future<void> replaceLines(List<String> encodedEvents);
}
