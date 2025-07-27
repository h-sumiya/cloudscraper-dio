import 'dart:async';

import 'package:cloudscraper_dio/src/interpre/base.dart';
import 'package:cloudscraper_dio/src/utils/html_unescape/html_unescape.dart';

/// ===== Exceptions =====

final escape = HtmlUnescape();

class CloudflareCode1020 implements Exception {
  final String message;
  CloudflareCode1020([this.message = 'Cloudflare 1020 (Firewall) detected.']);
  @override
  String toString() => 'CloudflareCode1020: $message';
}

class CloudflareIUAMError implements Exception {
  final String message;
  CloudflareIUAMError(this.message);
  @override
  String toString() => 'CloudflareIUAMError: $message';
}

class CloudflareSolveError implements Exception {
  final String message;
  CloudflareSolveError(this.message);
  @override
  String toString() => 'CloudflareSolveError: $message';
}

class CloudflareChallengeError implements Exception {
  final String message;
  CloudflareChallengeError(this.message);
  @override
  String toString() => 'CloudflareChallengeError: $message';
}

/// ===== Minimal request/response abstractions =====

class CfRequest {
  final String method;
  final Uri url;
  CfRequest(this.method, this.url);
}

class CfResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Uri url;
  final CfRequest request;

  CfResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.url,
    required this.request,
  });

  bool get isRedirect =>
      statusCode >= 300 &&
      statusCode < 400 &&
      headers.keys.any((k) => k.toLowerCase() == 'location');

  String? get locationHeader {
    final key = headers.keys.firstWhere(
      (k) => k.toLowerCase() == 'location',
      orElse: () => '',
    );
    return key.isEmpty ? null : headers[key];
  }
}

/// ===== cloudscraper-like interface =====

abstract class Cloudscraper {
  bool get debug;
  double? get delay; // seconds; may be null initially
  set delay(double? value);

  JavaScriptInterpreter get interpreter;
  Map<String, String> get headers;

  /// Perform HTTP request. If [allowRedirects] is false, do not auto-follow.
  Future<CfResponse> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Map<String, String>? data, // form-encoded
    bool allowRedirects = true,
  });

  /// If you use Brotli and need manual decode, implement here; otherwise return resp.
  CfResponse decodeBrotli(CfResponse resp) => resp;

  Never simpleException(Object errorType, String message) {
    if (errorType is Type && errorType == CloudflareCode1020) {
      throw CloudflareCode1020(message);
    } else if (errorType is Type && errorType == CloudflareIUAMError) {
      throw CloudflareIUAMError(message);
    } else if (errorType is Type && errorType == CloudflareChallengeError) {
      throw CloudflareChallengeError(message);
    } else if (errorType is Type && errorType == CloudflareSolveError) {
      throw CloudflareSolveError(message);
    } else if (errorType is Exception) {
      throw errorType;
    } else {
      throw Exception(message);
    }
  }
}

/// ===== Cloudflare helper (IUAM only; no CAPTCHA) =====

class Cloudflare {
  final Cloudscraper cloudscraper;
  Cloudflare(this.cloudscraper);

  /// HTML entity unescape
  static String unescape(String htmlText) {
    return escape.convert(htmlText);
  }

  /// Helpers
  static String _h(Map<String, String> headers, String name) {
    final key = headers.keys.firstWhere(
      (k) => k.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    return key.isEmpty ? '' : headers[key] ?? '';
  }

  /// --- Detection ---

  static bool isIUAMChallenge(CfResponse resp) {
    try {
      return _h(
            resp.headers,
            'Server',
          ).toLowerCase().startsWith('cloudflare') &&
          (resp.statusCode == 429 || resp.statusCode == 503) &&
          RegExp(
            r'/cdn-cgi/images/trace/jsch/',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body) &&
          RegExp(
            r'''<form .*?="challenge-form" action="/\S+__cf_chl_f_tk=''',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body);
    } catch (_) {
      return false;
    }
  }

  bool isNewIUAMChallenge(CfResponse resp) {
    try {
      return isIUAMChallenge(resp) &&
          RegExp(
            r'''cpo\.src\s*=\s*['"]/cdn-cgi/challenge-platform/\S+orchestrate/jsch/v1''',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body);
    } catch (_) {
      return false;
    }
  }

  static bool isFirewallBlocked(CfResponse resp) {
    try {
      return _h(
            resp.headers,
            'Server',
          ).toLowerCase().startsWith('cloudflare') &&
          resp.statusCode == 403 &&
          RegExp(
            r'<span class="cf-error-code">1020</span>',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body);
    } catch (_) {
      return false;
    }
  }

  /// Wrapper for the above (no CAPTCHA branch)
  bool isChallengeRequest(CfResponse resp) {
    if (isFirewallBlocked(resp)) {
      cloudscraper.simpleException(
        CloudflareCode1020,
        'Cloudflare has blocked this request (Code 1020 Detected).',
      );
    }

    if (isNewIUAMChallenge(resp)) {
      cloudscraper.simpleException(
        CloudflareChallengeError,
        'Detected a Cloudflare version 2 challenge; unsupported in this build.',
      );
    }

    if (isIUAMChallenge(resp)) {
      if (cloudscraper.debug) {
        // ignore: avoid_print
        print('Detected a Cloudflare version 1 IUAM challenge.');
      }
      return true;
    }

    return false;
  }

  /// --- IUAM solving ---

  Future<Map<String, dynamic>> _iuamChallengeResponse(
    String body,
    Uri url,
    JavaScriptInterpreter interpreter,
  ) async {
    try {
      final formMatch = RegExp(
        r'<form (.*?="challenge-form" action="(.*?__cf_chl_f_tk=\S+)"(.*?)</form>)',
        multiLine: true,
        dotAll: true,
      ).firstMatch(body);

      if (formMatch == null || formMatch.groupCount < 2) {
        cloudscraper.simpleException(
          CloudflareIUAMError,
          "Cloudflare IUAM detected, couldn't extract the parameters.",
        );
      }

      final formHtml = formMatch.group(1)!; // entire <form ...>...</form>
      final challengeUUID = formMatch.group(2)!;

      final payload = <String, String>{};

      final inputRe = RegExp(
        r'^\s*<input\s(.*?)/>',
        multiLine: true,
        dotAll: true,
      );
      for (final m in inputRe.allMatches(formHtml)) {
        final attrs = m.group(1) ?? '';
        final map = <String, String>{};
        for (final m2 in RegExp(r'(\S+)="(\S+)"').allMatches(attrs)) {
          map[m2.group(1)!] = m2.group(2)!;
        }
        final name = map['name'];
        if (name != null &&
            (name == 'r' || name == 'jschl_vc' || name == 'pass')) {
          payload[name] = map['value'] ?? '';
        }
      }

      // Compute jschl_answer via JS interpreter
      try {
        final answer = await interpreter.solveChallenge(body, url.host);
        payload['jschl_answer'] = answer;
      } catch (e) {
        cloudscraper.simpleException(
          CloudflareIUAMError,
          "Unable to parse Cloudflare anti-bots page: $e",
        );
      }

      final submitUrl = Uri.parse(
        '${url.scheme}://${url.host}${unescape(challengeUUID)}',
      );

      return {'url': submitUrl, 'data': payload};
    } catch (e) {
      cloudscraper.simpleException(
        CloudflareIUAMError,
        "Cloudflare IUAM detected, couldn't extract the parameters.",
      );
    }
  }

  /// Handle IUAM challenge end-to-end (no CAPTCHA path).
  Future<CfResponse> challengeResponse(
    CfResponse resp, {
    Map<String, String>? headers,
    Map<String, String>? data,
  }) async {
    if (!isIUAMChallenge(resp)) {
      // No challenge; re-issue original request (idempotent assumption).
      return cloudscraper.request(
        resp.request.method,
        resp.request.url,
        headers: headers,
        data: data,
      );
    }

    // Extract delay from the page if not already set
    if (cloudscraper.delay == null) {
      try {
        final m = RegExp(
          r'submit\(\);\r?\n\s*},\s*([0-9]+)',
          multiLine: true,
          dotAll: true,
        ).firstMatch(resp.body);
        final ms = m != null ? double.parse(m.group(1)!) : null;
        if (ms != null) {
          cloudscraper.delay = ms / 1000.0;
        }
      } catch (_) {
        cloudscraper.simpleException(
          CloudflareIUAMError,
          'Cloudflare IUAM possibly malformed; issue extracting delay value.',
        );
      }
    }

    // Wait required delay
    final delaySeconds = cloudscraper.delay ?? 4.0;
    await Future.delayed(
      Duration(milliseconds: (delaySeconds * 1000).clamp(0, 15000).toInt()),
    );

    // Build submission (form payload + jschl_answer)
    final submit = await _iuamChallengeResponse(
      resp.body,
      resp.url,
      cloudscraper.interpreter,
    );

    // Prepare POST back to Cloudflare
    final submitUrl = submit['url'] as Uri;
    final submitData = (submit['data'] as Map).cast<String, String>();

    final postHeaders = {
      ...(headers ?? {}),
      'Origin': '${resp.url.scheme}://${resp.url.host}',
      'Referer': resp.url.toString(),
    };

    final postResp = await cloudscraper.request(
      'POST',
      submitUrl,
      headers: postHeaders,
      data: submitData,
      allowRedirects: false,
    );

    if (postResp.statusCode == 400) {
      cloudscraper.simpleException(
        CloudflareSolveError,
        'Invalid challenge answer detected; Cloudflare may have changed.',
      );
    }

    // Pass-through (no redirect)
    if (!postResp.isRedirect) {
      return postResp;
    }

    // Follow redirect manually (also handle scheme changes)
    final loc = postResp.locationHeader!;
    final redirectLocation = postResp.url.resolve(loc);

    final getHeaders = {...(headers ?? {}), 'Referer': postResp.url.toString()};

    return cloudscraper.request(
      resp.request.method,
      redirectLocation,
      headers: getHeaders,
    );
  }
}
