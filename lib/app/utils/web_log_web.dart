import 'dart:html' as html;

void reportWebLog(String message) {
  final String payload = message.length > 8000
      ? '${message.substring(0, 8000)}...[truncated]'
      : message;
  try {
    html.HttpRequest.request(
      '/__log',
      method: 'POST',
      sendData: payload,
      requestHeaders: <String, String>{
        'Content-Type': 'text/plain; charset=utf-8',
      },
    );
  } catch (_) {}
}
