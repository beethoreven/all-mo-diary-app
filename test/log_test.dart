import 'package:allmodiary/core/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one log message is cut at 300 characters; feedback attachments are kept whole', () {
    final long = List.filled(100, 'line of logcat text').join('\n');
    expect(AppLog.redact(long).length, 301, reason: '300 characters and the ellipsis');
    final whole = AppLog.redact(long, maxLength: null);
    expect(whole, long);
    expect(AppLog.redact('mail me at someone@example.com', maxLength: null), 'mail me at [email]',
        reason: 'keeping it whole still masks personal data');
  });
}
