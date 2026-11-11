/// Limits and timings in one place.
library;

abstract final class Limits {
  /// Title: required, single line, at most 20 characters (an emoji counts as one).
  static const titleMaxChars = 20;

  /// User name shown as「名字的日記」: at most 8 characters.
  static const userNameMaxChars = 8;

  /// Search text: 10 characters for now, to be tuned against the real layout width.
  static const searchMaxChars = 10;

  /// Years the calendar, filter and date picker offer.
  static const yearMin = 2020;
  static const yearMax = 2080;

  /// Feedback: description ≤ 1000 characters, 3 a day, unsent reports kept 30 days
  /// and retried at most 5 times a day.
  static const feedbackMaxChars = 1000;
  static const feedbackPerDay = 3;
  static const feedbackQueueDays = 30;
  static const feedbackRetriesPerDay = 5;
}

abstract final class Timing {
  /// Changing month needs a drag past half the width (distance only, not fling speed).
  static const monthSwipeFraction = 0.5;
  static const monthSlide = Duration(milliseconds: 220);

  /// While writing, an unsaved draft is written to the phone this often.
  static const draftSaveInterval = Duration(seconds: 3);

  /// Cloud: compare with the cloud on opening the app or returning to it, at most once a minute;
  /// failed syncs retry every 5 minutes, at most 10 times per half day.
  static const syncMinInterval = Duration(minutes: 1);
  static const syncRetryInterval = Duration(minutes: 5);
  static const syncRetriesPerHalfDay = 10;

  /// Daily check failures: at least 2 hours apart, at most 5 retries a day.
  static const dailyCheckRetryGap = Duration(hours: 2);
  static const dailyCheckRetriesPerDay = 5;

  /// The diagnostic log keeps 7 days, at most 2 MB.
  static const logRetention = Duration(days: 7);
  static const logMaxBytes = 2 * 1024 * 1024;

  /// "The app closed unexpectedly last time" is offered at most once a day.
  static const crashPromptGap = Duration(days: 1);
}

/// Feedback attachment limits; always below the server's (1 MiB compressed, 4 MiB decompressed).
abstract final class FeedbackSpec {
  static const logcatLines = 500;
  static const traceMaxBytes = 512 * 1024;
  static const uploadMaxCompressed = 1000 * 1000;
}

/// An image shown from the cloud waits at most this long, then shows 「無法顯示」 instead of spinning
/// forever; the next time it's opened it tries again.
abstract final class ImageSpec {
  static const loadTimeout = Duration(seconds: 45);
}

/// Editor formatting choices.
abstract final class EditorSpec {
  /// Font sizes in points. Stored in the diary as the point number ("12").
  static const fontSizes = [8, 10, 12, 14, 16, 18, 20];
  static const defaultFontSize = 12;

  /// Points are drawn at 4/3 logical pixels each (the CSS pt→px ratio), so 12 pt reads like
  /// body text in other apps. Applied as a text scale around the body only; images aren't scaled.
  static const pointToPixel = 4 / 3;

  /// The built-in font. Not deletable, and the fallback for anything missing.
  static const defaultFontFamily = 'NotoSansTC';
  static const defaultFontName = 'Noto Sans TC';
}
