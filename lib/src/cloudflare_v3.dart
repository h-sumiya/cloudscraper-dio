import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:cloudscraper_dio/src/cloudscraper.dart';

// ---- model ----
class V3ChallengeInfo {
  final Map<String, dynamic> ctxData;
  final Map<String, dynamic> optData;
  final String formAction;
  final String? vmScript;
  V3ChallengeInfo({
    required this.ctxData,
    required this.optData,
    required this.formAction,
    required this.vmScript,
  });
}

class CloudflareV3 {
  final Cloudscraper cloudscraper;
  final double delaySeconds;

  CloudflareV3(this.cloudscraper)
    : delaySeconds = cloudscraper.delay ?? (1.0 + Random().nextDouble() * 4.0);

  // ---- utils ----
  static String _h(Map<String, String> headers, String name) {
    final key = headers.keys.firstWhere(
      (k) => k.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    return key.isEmpty ? '' : headers[key] ?? '';
  }

  // ---- detection ----
  static bool isV3Challenge(CfResponse resp) {
    try {
      final server = _h(resp.headers, 'Server').toLowerCase();
      final cfRay = _h(resp.headers, 'cf-ray');
      final mitigated = _h(resp.headers, 'cf-mitigated');
      final isCf =
          server.startsWith('cloudflare') ||
          cfRay.isNotEmpty ||
          mitigated.toLowerCase() == 'challenge';
      return isCf &&
          (resp.statusCode == 403 ||
              resp.statusCode == 429 ||
              resp.statusCode == 503) &&
          (RegExp(
                r'''cpo\.src\s*=\s*['"]/cdn-cgi/challenge-platform/\S+orchestrate/jsch/v3''',
                multiLine: true,
                dotAll: true,
              ).hasMatch(resp.body) ||
              RegExp(
                r'window\._cf_chl_ctx\s*=',
                multiLine: true,
                dotAll: true,
              ).hasMatch(resp.body) ||
              RegExp(
                r'window\._cf_chl_opt\s*=',
                multiLine: true,
                dotAll: true,
              ).hasMatch(resp.body) ||
              RegExp(
                r'<form[^>]*id="challenge-form"[^>]*action="[^"]*__cf_chl_rt_tk=',
                multiLine: true,
                dotAll: true,
              ).hasMatch(resp.body));
    } catch (_) {
      return false;
    }
  }

  // ---- extractors ----
  Future<V3ChallengeInfo> extractV3ChallengeData(CfResponse resp) async {
    try {
      final mCtx = RegExp(
        r'window\._cf_chl_ctx\s*=\s*({.*?});',
        dotAll: true,
      ).firstMatch(resp.body);
      final mOpt = RegExp(
        r'window\._cf_chl_opt\s*=\s*({.*?});',
        dotAll: true,
      ).firstMatch(resp.body);
      Map<String, dynamic> ctxData = {};
      Map<String, dynamic> optData = {};
      if (mCtx != null) {
        try {
          ctxData = json.decode(mCtx.group(1)!) as Map<String, dynamic>;
        } catch (_) {}
      }
      if (mOpt != null) {
        final raw = mOpt.group(1)!;
        if (cloudscraper.debug) {
          // ignore: avoid_print
          print('raw opt: ' + raw.substring(0, 60));
        }
        try {
          optData = json.decode(raw) as Map<String, dynamic>;
        } catch (_) {
          // Fallback: very loose regex extraction for key:'value' pairs
          for (final m in RegExp(r"(\w+):\s*'([^']*)'").allMatches(raw)) {
            optData[m.group(1)!] = m.group(2)!;
          }
        }
      }

      final mForm = RegExp(
        r'<form[^>]*id="challenge-form"[^>]*action="([^"]+)"',
        dotAll: true,
      ).firstMatch(resp.body);
      String? action;
      if (mForm != null) {
        action = mForm.group(1);
      } else {
        final mFa = RegExp(r'fa:"([^"]+)"').firstMatch(resp.body);
        if (mFa != null) {
          action = mFa.group(1);
        }
      }
      if (action == null) {
        throw CloudflareChallengeError(
          "Could not find Cloudflare v3 challenge form",
        );
      }

      // VM スクリプト（_cf_chl_enter 付近）をゆるく抽出
      String? vmScript;
      final mScript = RegExp(
        r'<script[^>]*>\s*(.*?window\._cf_chl_enter.*?)</script>',
        dotAll: true,
      ).firstMatch(resp.body);
      if (mScript != null) {
        vmScript = mScript.group(1);
      } else {
        final mSrc = RegExp(
          r'''a\.src\s*=\s*[\"']([^\"']+)[\"']''',
        ).firstMatch(resp.body);
        if (mSrc != null) {
          final src = mSrc.group(1)!;
          final scriptUrl = src.startsWith('http')
              ? Uri.parse(src)
              : resp.url.resolve(src);
          final scriptResp = await cloudscraper.request('GET', scriptUrl);
          vmScript = scriptResp.body;
        }
      }

      return V3ChallengeInfo(
        ctxData: ctxData,
        optData: optData,
        formAction: action,
        vmScript: vmScript,
      );
    } catch (e) {
      throw CloudflareChallengeError(
        "Error extracting Cloudflare v3 challenge data: $e",
      );
    }
  }

  // ---- VM execution ----
  Future<String> executeVmChallenge(V3ChallengeInfo info, String domain) async {
    try {
      if (info.vmScript == null || info.vmScript!.isEmpty) {
        return _generateFallbackResponse(info);
      }

      final jsContext =
          '''
      var window = {
        location: {
          href: 'https://$domain/',
          hostname: '$domain',
          protocol: 'https:',
          pathname: '/'
        },
        navigator: {
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          platform: 'Win32',
          language: 'en-US'
        },
        document: {
          getElementById: function(id) { return { value: '', style: {} }; },
          createElement: function(tag) { return { firstChild: { href: 'https://$domain/' }, style: {} }; }
        },
        _cf_chl_ctx: ${jsonEncode(info.ctxData)},
        _cf_chl_opt: ${jsonEncode(info.optData)},
        _cf_chl_enter: function() { return true; }
      };
      var document = window.document;
      var location = window.location;
      var navigator = window.navigator;

      ${info.vmScript}

      // 最終的な回答値を返す
      (function() {
        if (typeof window._cf_chl_answer !== 'undefined') { return window._cf_chl_answer; }
        if (typeof _cf_chl_answer !== 'undefined') { return _cf_chl_answer; }
        return Math.floor(Math.random() * 1e6);
      })();
      ''';

      // 既存の JavaScriptInterpreter を利用
      // （型が num 戻りの想定なので、toString で吸収。失敗時はフォールバックへ）
      try {
        final resultNum = await cloudscraper.interpreter.eval(
          jsContext,
          domain,
        );
        return resultNum.toString();
      } catch (jsError) {
        return _generateFallbackResponse(info);
      }
    } catch (e) {
      return _generateFallbackResponse(info);
    }
  }

  // ---- fallback ----
  static int _stableHash(String s) {
    // 簡易 FNV-1a 32-bit
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffset;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  String _generateFallbackResponse(V3ChallengeInfo info) {
    final opt = info.optData;
    final ctx = info.ctxData;

    if (opt.containsKey('chlPageData')) {
      final s = '${opt['chlPageData']}';
      return (_stableHash(s) % 1000000).toString();
    }
    if (ctx.containsKey('cvId')) {
      final s = '${ctx['cvId']}';
      return (_stableHash(s) % 1000000).toString();
    }
    return (100000 + Random().nextInt(900000)).toString();
  }

  // ---- payload ----
  Map<String, String> generateV3ChallengePayload(
    V3ChallengeInfo info,
    CfResponse resp,
    String challengeAnswer,
  ) {
    try {
      String? rToken;
      final mR = RegExp(r'name="r"\s+value="([^"]+)"').firstMatch(resp.body);
      if (mR != null) {
        rToken = mR.group(1);
      } else {
        // Fallback: try to derive from extracted challenge data
        rToken =
            info.optData['cRay']?.toString() ?? info.ctxData['r']?.toString();
      }
      if (rToken == null || rToken.isEmpty) {
        throw CloudflareChallengeError("Could not find 'r' token");
      }

      final LinkedHashMap<String, String> formFields = LinkedHashMap();
      for (final m in RegExp(
        r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"',
        dotAll: true,
      ).allMatches(resp.body)) {
        final name = m.group(1)!;
        final value = m.group(2)!;
        if (name != 'jschl_answer') {
          formFields[name] = value;
        }
      }

      final payload = <String, String>{};
      payload['r'] = rToken;
      payload['jschl_answer'] = challengeAnswer;

      formFields.forEach((k, v) {
        if (!payload.containsKey(k)) {
          payload[k] = v;
        }
      });

      return payload;
    } catch (e) {
      throw CloudflareChallengeError(
        "Error generating v3 challenge payload: $e",
      );
    }
  }

  // ---- handler ----
  Future<CfResponse> handleV3Challenge(
    CfResponse resp, {
    Map<String, String>? headers,
    Map<String, String>? data,
  }) async {
    try {
      if (cloudscraper.debug) {
        // ignore: avoid_print
        print('Handling Cloudflare v3 JavaScript VM challenge.');
      }

      final info = await extractV3ChallengeData(resp);
      if (cloudscraper.debug) {
        // ignore: avoid_print
        print('V3 optData keys: ' + info.optData.keys.take(5).join(','));
      }

      // 待機（上限ガード）
      final ms = (delaySeconds * 1000).clamp(0, 15000).toInt();
      await Future.delayed(Duration(milliseconds: ms));

      final domain = resp.url.host;
      final answer = await executeVmChallenge(info, domain);

      final payload = generateV3ChallengePayload(info, resp, answer);

      // action が相対なら補完
      Uri challengeUrl;
      final action = info.formAction;
      if (action.startsWith('http://') || action.startsWith('https://')) {
        challengeUrl = Uri.parse(action);
      } else {
        challengeUrl = Uri.parse(
          '${resp.url.scheme}://${resp.url.host}$action',
        );
      }

      final postHeaders = {
        ...(headers ?? {}),
        'Origin': '${resp.url.scheme}://${resp.url.host}',
        'Referer': resp.url.toString(),
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final postResp = await cloudscraper.request(
        'POST',
        challengeUrl,
        headers: postHeaders,
        data: payload,
        allowRedirects: false,
      );

      if (postResp.statusCode == 403) {
        throw CloudflareSolveError("Failed to solve Cloudflare v3 challenge");
      }

      if (postResp.isRedirect && postResp.locationHeader != null) {
        final redirectLocation = postResp.url.resolve(postResp.locationHeader!);
        final getHeaders = {
          ...(headers ?? {}),
          'Referer': postResp.url.toString(),
        };
        return cloudscraper.request(
          resp.request.method,
          redirectLocation,
          headers: getHeaders,
        );
      }

      return postResp;
    } catch (e) {
      throw CloudflareChallengeError(
        "Error handling Cloudflare v3 challenge: $e",
      );
    }
  }
}
