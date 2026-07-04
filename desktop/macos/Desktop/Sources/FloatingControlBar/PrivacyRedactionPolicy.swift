import Foundation

/// Pure, dependency-free policy for stripping PII from text before it is sent
/// to a downstream model, written to a log, or otherwise leaves the user's
/// machine. The level is chosen by the caller; the policy itself is a pure
/// function of (text, level) — no clock, no I/O, no shared state — so tests
/// can drive it deterministically and the UI can layer it on top of any
/// string pipeline (chat transcriptions, tool inputs/outputs, debug dumps).
enum PrivacyRedactionPolicy {

  /// How aggressive the policy is. Ordered by strictness; `.off` is identity.
  enum Level: String, CaseIterable, Equatable, Sendable {
    /// No redaction at all — pass the text through unchanged.
    case off
    /// Replace every email address with the literal token `[email]`.
    case emails
    /// Emails, plus phone numbers and any run of 7+ consecutive digits,
    /// are replaced with the literal token `[redacted]`.
    case aggressive
  }

  /// The placeholder for redacted email addresses.
  private static let emailToken = "[email]"
  /// The placeholder for redacted phone numbers and long digit runs.
  private static let redactedToken = "[redacted]"

  // Pre-compiled patterns. Static-let so the regex is built once per process;
  // `try!` is safe because every pattern below is a literal known-valid regex.
  private static let emailPattern: NSRegularExpression = {
    // Practical email matcher: local-part @ domain.tld, with the common
    // subset of characters allowed by RFC 5322 in practice. Intentionally
    // not over-greedy — `+` is allowed, trailing dots are not.
    return try! NSRegularExpression(
      pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
    )
  }()

  private static let phonePattern: NSRegularExpression = {
    // Match a US-style phone: optional `+1` country code, then groups of
    // digits separated by spaces, dashes, or dots. Requires 10 digits
    // total (or 11 with leading 1) once separators are stripped.
    return try! NSRegularExpression(
      pattern: #"(?:\+?1[ \-\.]?)?\(?[0-9]{3}\)?[ \-\.]?[0-9]{3}[ \-\.]?[0-9]{4}"#
    )
  }()

  private static let longDigitRunPattern: NSRegularExpression = {
    // 7 or more consecutive digits with no separators between them.
    return try! NSRegularExpression(
      pattern: #"[0-9]{7,}"#
    )
  }()

  /// Redact PII from `text` according to `level`. Pure function: same input
  /// always yields the same output, no side effects, no global state.
  ///
  /// Order of operations within `.aggressive` is intentional:
  /// 1. emails → `[email]`
  /// 2. phones → `[redacted]`
  /// 3. long digit runs (7+) → `[redacted]`
  ///
  /// Emails are replaced first so their digit runs (rare, but legal — e.g.
  /// `91234@…`) are not double-processed by the digit-run pass on the raw
  /// form; by the time the digit pass runs, those digits are gone.
  static func redact(_ text: String, level: Level) -> String {
    switch level {
    case .off:
      return text
    case .emails:
      return replace(text, pattern: emailPattern, with: emailToken)
    case .aggressive:
      var out = replace(text, pattern: emailPattern, with: emailToken)
      out = replace(out, pattern: phonePattern, with: redactedToken)
      out = replace(out, pattern: longDigitRunPattern, with: redactedToken)
      return out
    }
  }

  /// Run `pattern` over `text` and replace every full match with `template`.
  /// Uses an explicit NSRange built from the input string's UTF-16 length to
  /// keep behavior stable regardless of any later Swift String changes.
  private static func replace(
    _ text: String,
    pattern: NSRegularExpression,
    with template: String
  ) -> String {
    let range = NSRange(location: 0, length: (text as NSString).length)
    return pattern.stringByReplacingMatches(
      in: text,
      options: [],
      range: range,
      withTemplate: template
    )
  }
}
