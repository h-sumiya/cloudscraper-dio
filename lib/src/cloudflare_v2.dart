import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloudscraper_dio/src/cloudscraper.dart';

class CloudflareV2 {
  final Cloudscraper cloudscraper;
  final double delaySeconds;

  CloudflareV2(this.cloudscraper)
    : delaySeconds =
          cloudscraper.delay ??
          (1.0 + Random().nextDouble() * 4.0); // [1.0, 5.0)

  // --- Utils ---
  static String _h(Map<String, String> headers, String name) {
    final key = headers.keys.firstWhere(
      (k) => k.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    return key.isEmpty ? '' : headers[key] ?? '';
  }

  // --- Detection ---

  /// Cloudflare v2 JS challenge (non-captcha)
  static bool isV2Challenge(CfResponse resp) {
    try {
      return _h(
            resp.headers,
            'Server',
          ).toLowerCase().startsWith('cloudflare') &&
          (resp.statusCode == 403 ||
              resp.statusCode == 429 ||
              resp.statusCode == 503) &&
          RegExp(
            r'''cpo\.src\s*=\s*['"]/cdn-cgi/challenge-platform/\S+orchestrate/jsch/v1''',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body);
    } catch (_) {
      return false;
    }
  }

  /// Cloudflare v2 captcha (未対応だが検出のみ可能)
  static bool isV2CaptchaChallenge(CfResponse resp) {
    try {
      return _h(
            resp.headers,
            'Server',
          ).toLowerCase().startsWith('cloudflare') &&
          resp.statusCode == 403 &&
          RegExp(
            r'''cpo\.src\s*=\s*['"]/cdn-cgi/challenge-platform/\S+orchestrate/(captcha|managed)/v1''',
            multiLine: true,
            dotAll: true,
          ).hasMatch(resp.body);
    } catch (_) {
      return false;
    }
  }

  /// 1020 Firewall
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

  /// ラッパー（v2 captcha は未対応として例外通知）
  bool isChallengeRequest(CfResponse resp) {
    if (isFirewallBlocked(resp)) {
      cloudscraper.simpleException(
        CloudflareCode1020,
        'Cloudflare has blocked this request (Code 1020 detected).',
      );
    }

    if (isV2CaptchaChallenge(resp)) {
      cloudscraper.simpleException(
        CloudflareChallengeError,
        'Detected a Cloudflare v2 captcha challenge; captcha is not implemented in this build.',
      );
    }

    return isV2Challenge(resp);
  }

  // --- Extractors ---

  /// ページから challenge データ(JSON)と form action を抽出
  ({Map<String, dynamic> challengeData, String formAction})
  extractChallengeData(CfResponse resp) {
    try {
      final mJson = RegExp(
        r'window\._cf_chl_opt=({.*?});',
        dotAll: true,
      ).firstMatch(resp.body);
      if (mJson == null) {
        throw CloudflareChallengeError(
          "Could not find Cloudflare challenge data",
        );
      }
      final Map<String, dynamic> challengeData =
          json.decode(mJson.group(1)!) as Map<String, dynamic>;

      final mForm = RegExp(
        r'<form .*?id="challenge-form" action="([^"]+)"',
        dotAll: true,
      ).firstMatch(resp.body);
      if (mForm == null) {
        throw CloudflareChallengeError(
          "Could not find Cloudflare challenge form",
        );
      }
      final formAction = mForm.group(1)!;

      return (challengeData: challengeData, formAction: formAction);
    } catch (e) {
      throw CloudflareChallengeError(
        "Error extracting Cloudflare challenge data: $e",
      );
    }
  }

  /// 送信用ペイロード作成（captcha 関連は含めない）
  Map<String, String> generateChallengePayload(
    Map<String, dynamic> challengeData,
    CfResponse resp,
  ) {
    try {
      final mR = RegExp(r'name="r"\s+value="([^"]+)"').firstMatch(resp.body);
      if (mR == null) {
        throw CloudflareChallengeError("Could not find 'r' token");
      }

      final payload = <String, String>{
        'r': mR.group(1)!,
        'cf_ch_verify': 'plat', // プラットフォーム検証フラグ
        // v2 の非Captcha では通常 vc/captcha_vc は空で問題ないケースが多い
        'vc': '',
        'captcha_vc': '',
      };

      if (challengeData.containsKey('cvId')) {
        payload['cv_chal_id'] = '${challengeData['cvId']}';
      }
      if (challengeData.containsKey('chlPageData')) {
        payload['cf_chl_page_data'] = '${challengeData['chlPageData']}';
      }

      return payload;
    } catch (e) {
      throw CloudflareChallengeError(
        "Error generating Cloudflare challenge payload: $e",
      );
    }
  }

  // --- Handler (no-captcha) ---

  /// v2 JS チャレンジを処理（captcha ではないパス）
  Future<CfResponse> handleV2Challenge(
    CfResponse resp, {
    Map<String, String>? headers,
    Map<String, String>? data,
  }) async {
    try {
      final info = extractChallengeData(resp);

      // 要求ディレイ（乱数 or 事前設定）
      final ms = (delaySeconds * 1000).clamp(0, 15000).toInt(); // 上限 15s 程度でガード
      await Future.delayed(Duration(milliseconds: ms));

      final payload = generateChallengePayload(info.challengeData, resp);

      final url = resp.url;
      final challengeUrl = Uri.parse(
        '${url.scheme}://${url.host}${info.formAction}',
      );

      final postHeaders = {
        ...(headers ?? {}),
        'Origin': '${url.scheme}://${url.host}',
        'Referer': url.toString(),
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
        throw CloudflareSolveError('Failed to solve Cloudflare v2 challenge');
      }

      // リダイレクトが来たら手動追従（Cookie 設定後の通過を安定化）
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
        'Error handling Cloudflare v2 challenge: $e',
      );
    }
  }
}
