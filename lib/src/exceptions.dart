// cloudscraper_exceptions.dart
//
// Dart port of cloudscraper.exceptions
// -----------------------------------------------------------------------------

/// Base exception class for Cloudflare-related errors.
abstract class CloudflareException implements Exception {
  final String message;
  const CloudflareException([this.message = 'Cloudflare error']);

  @override
  String toString() => '$runtimeType: $message';
}

/// Raise an exception for recursive depth protection.
class CloudflareLoopProtection extends CloudflareException {
  const CloudflareLoopProtection([
    super.message = 'Recursive depth protection triggered',
  ]);
}

/// Raise an exception for Cloudflare code 1020 block.
class CloudflareCode1020 extends CloudflareException {
  const CloudflareCode1020([
    super.message = 'Blocked by Cloudflare (code 1020)',
  ]);
}

/// Raise an error for problem extracting IUAM parameters from Cloudflare payload.
class CloudflareIUAMError extends CloudflareException {
  const CloudflareIUAMError([
    super.message = 'Problem extracting IUAM parameters from payload',
  ]);
}

/// Raise an error when detected new Cloudflare challenge.
class CloudflareChallengeError extends CloudflareException {
  const CloudflareChallengeError([
    super.message = 'Detected new/unsupported Cloudflare challenge',
  ]);
}

/// Raise an error when issue with solving Cloudflare challenge.
class CloudflareSolveError extends CloudflareException {
  const CloudflareSolveError([
    super.message = 'Failed to solve Cloudflare challenge',
  ]);
}

/// Raise an error for problem extracting Captcha parameters from Cloudflare payload.
class CloudflareCaptchaError extends CloudflareException {
  const CloudflareCaptchaError([
    super.message = 'Problem extracting Captcha parameters from payload',
  ]);
}

/// Raise an exception for no Captcha provider loaded for Cloudflare.
class CloudflareCaptchaProvider extends CloudflareException {
  const CloudflareCaptchaProvider([
    super.message = 'No Captcha provider configured for Cloudflare',
  ]);
}

/// Raise an error for problem with Cloudflare Turnstile challenge.
class CloudflareTurnstileError extends CloudflareException {
  const CloudflareTurnstileError([
    super.message = 'Error with Cloudflare Turnstile challenge',
  ]);
}

/// Raise an error for problem with Cloudflare v3 JavaScript VM challenge.
class CloudflareV3Error extends CloudflareException {
  const CloudflareV3Error([
    super.message = 'Error with Cloudflare v3 JavaScript VM challenge',
  ]);
}

// -----------------------------------------------------------------------------
// Captcha exceptions
// -----------------------------------------------------------------------------

/// Base exception class for captcha providers.
abstract class CaptchaException implements Exception {
  final String message;
  const CaptchaException([this.message = 'Captcha error']);

  @override
  String toString() => '$runtimeType: $message';
}

/// Raise an exception for external services that cannot be reached.
class CaptchaServiceUnavailable extends CaptchaException {
  const CaptchaServiceUnavailable([
    super.message = 'Captcha service unavailable',
  ]);
}

/// Raise an error for error from API response.
class CaptchaAPIError extends CaptchaException {
  const CaptchaAPIError([super.message = 'Captcha API error']);
}

/// Raise an error for captcha provider account problem.
class CaptchaAccountError extends CaptchaException {
  const CaptchaAccountError([super.message = 'Captcha account error']);
}

/// Raise an exception for captcha provider taking too long.
class CaptchaTimeout extends CaptchaException {
  const CaptchaTimeout([super.message = 'Captcha solve timed out']);
}

/// Raise an exception for bad or missing parameter.
class CaptchaParameter extends CaptchaException {
  const CaptchaParameter([super.message = 'Bad or missing captcha parameter']);
}

/// Raise an exception for invalid job id.
class CaptchaBadJobID extends CaptchaException {
  const CaptchaBadJobID([super.message = 'Invalid captcha job ID']);
}

/// Raise an error for captcha provider unable to report bad solve.
class CaptchaReportError extends CaptchaException {
  const CaptchaReportError([
    super.message = 'Unable to report bad captcha solve',
  ]);
}
