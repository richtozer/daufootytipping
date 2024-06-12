//used for firebase messaging
class DeviceToken {
  final String token;
  final DateTime
      timestamp; // this is used to track how fresh the token is, if it is older than 30 days, it is considered stale and should be refreshed or deleted

  const DeviceToken({required this.token, required this.timestamp});

  factory DeviceToken.fromJson(Map<String, dynamic> data) {
    return DeviceToken(
        token: data['token'] ?? '',
        timestamp: DateTime.parse(data['timestamp'] ?? ''));
  }

  Map<String, dynamic> toJson() {
    return {"token": token, "timestamp": timestamp.toIso8601String()};
  }
}
