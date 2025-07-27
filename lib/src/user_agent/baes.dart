import 'dart:math';

import 'package:cloudscraper_dio/src/user_agent/browsers.dart';

class UserAgent {
  Map<String, String> headers;
  List<String> cipherSuite;

  final String? browser;
  final String? platform;
  final bool desktop;
  final bool mobile;
  final String? custom;
  final bool allowBrotli;

  static const List<String> _platforms = [
    'linux',
    'windows',
    'darwin',
    'android',
    'ios',
  ];
  static const List<String> _browsers = ['chrome', 'firefox'];

  UserAgent._internal({
    required this.headers,
    required this.cipherSuite,
    required this.browser,
    required this.platform,
    required this.desktop,
    required this.mobile,
    required this.custom,
    required this.allowBrotli,
  });

  /// 同期版ビルダー：必要に応じてファイルを同期読み込みします
  factory UserAgent.build({
    String? browser,
    String? platform,
    bool desktop = true,
    bool mobile = true,
    String? custom,
    bool allowBrotli = false,
    Map<String, dynamic>? data,
    String? browsersJsonPath,
  }) {
    if (!desktop && !mobile) {
      throw StateError("mobile と desktop を同時に false にはできません。");
    }

    final Map<String, dynamic> userAgents =
        data ??
        _loadUserAgentDataSync(browsersJsonPath: browsersJsonPath) ??
        _fallbackData;

    Map<String, String> headers = {};
    List<String> cipherSuite = [];

    String? chosenBrowser = browser;
    String? chosenPlatform = platform;

    // custom 指定がある場合：一致する UA を検索
    if (custom != null && custom.isNotEmpty) {
      final matched = _tryMatchCustom(userAgents, custom);
      if (matched != null) {
        headers = Map<String, String>.from(matched.$1);
        headers['User-Agent'] = custom;
        cipherSuite = List<String>.from(matched.$2);
      } else {
        // 見つからなかった場合のフォールバック（Python に合わせる）
        cipherSuite = [
          // 近い意味合いのフォールバック（OpenSSL名をそのままは扱いにくいので簡略）
          'DEFAULT',
          '!AES128-SHA',
          '!ECDHE-RSA-AES256-SHA',
        ];
        headers = {
          'User-Agent': custom,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip, deflate, br',
        };
      }
    } else {
      // browser 候補のバリデーション
      if (chosenBrowser != null && !_browsers.contains(chosenBrowser)) {
        throw ArgumentError(
          'browser="$chosenBrowser" は無効です。有効: ${_browsers.join(", ")}',
        );
      }

      // platform が未指定ならランダム選択
      chosenPlatform ??= _randomChoice(_platforms);

      if (!_platforms.contains(chosenPlatform)) {
        throw ArgumentError(
          'platform="$chosenPlatform" は無効です。有効: ${_platforms.join(", ")}',
        );
      }

      // デバイス種別でフィルタ
      final filtered = _filterAgents(
        userAgents['user_agents'] as Map<String, dynamic>,
        mobile: mobile,
        desktop: desktop,
        platform: chosenPlatform,
      );

      // browser が未指定なら、存在するキーからランダム選択
      while (chosenBrowser == null || filtered[chosenBrowser] == null) {
        final keys = filtered.keys.toList();
        if (keys.isEmpty) break;
        chosenBrowser = _randomChoice(keys);
      }

      final list = filtered[chosenBrowser];
      if (list == null || list.isEmpty) {
        throw StateError(
          'browser="$chosenBrowser" は platform="$chosenPlatform" に見つかりませんでした。',
        );
      }

      cipherSuite = List<String>.from(
        (userAgents['cipherSuite'] as Map<String, dynamic>)[chosenBrowser]
            as List<dynamic>,
      );
      headers = Map<String, String>.from(
        (userAgents['headers'] as Map<String, dynamic>)[chosenBrowser]
            as Map<String, dynamic>,
      );

      headers['User-Agent'] = _randomChoice(list);
    }

    if (!allowBrotli && headers.containsKey('Accept-Encoding')) {
      final enc = headers['Accept-Encoding']!;
      final parts = enc
          .split(',')
          .map((e) => e.trim())
          .where((e) => e != 'br')
          .toList();
      headers['Accept-Encoding'] = parts.join(',').trim();
    }

    return UserAgent._internal(
      headers: headers,
      cipherSuite: cipherSuite,
      browser: chosenBrowser,
      platform: chosenPlatform,
      desktop: desktop,
      mobile: mobile,
      custom: custom,
      allowBrotli: allowBrotli,
    );
  }

  /// browsers.json からの同期読み込み。見つからなければ null。
  static Map<String, dynamic>? _loadUserAgentDataSync({
    String? browsersJsonPath,
  }) {
    return browserJson;
  }

  static Map<String, List<String>> _filterAgents(
    Map<String, dynamic> uaRoot, {
    required bool mobile,
    required bool desktop,
    required String? platform,
  }) {
    final Map<String, List<String>> filtered = {};
    if (mobile) {
      final mob =
          (uaRoot['mobile'] as Map<String, dynamic>)[platform]
              as Map<String, dynamic>?;
      if (mob != null) {
        for (final e in mob.entries) {
          filtered[e.key] = List<String>.from(e.value as List<dynamic>);
        }
      }
    }
    if (desktop) {
      final desk =
          (uaRoot['desktop'] as Map<String, dynamic>)[platform]
              as Map<String, dynamic>?;
      if (desk != null) {
        for (final e in desk.entries) {
          filtered.update(
            e.key,
            (prev) => [...prev, ...List<String>.from(e.value as List<dynamic>)],
            ifAbsent: () => List<String>.from(e.value as List<dynamic>),
          );
        }
      }
    }
    return filtered;
  }

  /// custom と一致する UA を全探索。見つかったら (headers, cipherSuite) を返す。
  static (Map<String, String>, List<String>)? _tryMatchCustom(
    Map<String, dynamic> data,
    String custom,
  ) {
    final root = data['user_agents'] as Map<String, dynamic>;
    for (final deviceType in root.keys) {
      final platforms = root[deviceType] as Map<String, dynamic>;
      for (final platform in platforms.keys) {
        final browsers = platforms[platform] as Map<String, dynamic>;
        for (final browser in browsers.keys) {
          final uaList = List<String>.from(browsers[browser] as List<dynamic>);
          if (uaList.any((ua) => ua.contains(custom))) {
            final headers = Map<String, String>.from(
              (data['headers'] as Map<String, dynamic>)[browser]
                  as Map<String, dynamic>,
            );
            final cipher = List<String>.from(
              (data['cipherSuite'] as Map<String, dynamic>)[browser]
                  as List<dynamic>,
            );
            return (headers, cipher);
          }
        }
      }
    }
    return null;
  }

  static T _randomChoice<T>(List<T> list) {
    final rnd = Random.secure();
    return list[rnd.nextInt(list.length)];
  }

  static const Map<String, dynamic> _fallbackData = {
    "headers": {
      "chrome": {
        "User-Agent": null,
        "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "gzip, deflate, br",
      },
      "firefox": {
        "User-Agent": null,
        "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Accept-Encoding": "gzip, deflate, br",
      },
    },
    "cipherSuite": {
      "chrome": [
        "TLS_AES_128_GCM_SHA256",
        "TLS_AES_256_GCM_SHA384",
        "ECDHE-ECDSA-AES128-GCM-SHA256",
        "ECDHE-RSA-AES128-GCM-SHA256",
        "ECDHE-ECDSA-AES256-GCM-SHA384",
        "ECDHE-RSA-AES256-GCM-SHA384",
      ],
      "firefox": [
        "TLS_AES_128_GCM_SHA256",
        "TLS_CHACHA20_POLY1305_SHA256",
        "TLS_AES_256_GCM_SHA384",
        "ECDHE-ECDSA-AES128-GCM-SHA256",
        "ECDHE-RSA-AES128-GCM-SHA256",
        "ECDHE-ECDSA-AES256-GCM-SHA384",
      ],
    },
    "user_agents": {
      "desktop": {
        "windows": {
          "chrome": [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          ],
          "firefox": [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0",
            "Mozilla/5.0 (Windows NT 10.0; WOW64; rv:120.0) Gecko/20100101 Firefox/120.0",
          ],
        },
        "linux": {
          "chrome": [
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          ],
          "firefox": [
            "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
            "Mozilla/5.0 (X11; Linux i686; rv:120.0) Gecko/20100101 Firefox/120.0",
          ],
        },
        "darwin": {
          "chrome": [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          ],
          "firefox": [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0",
          ],
        },
      },
      "mobile": {
        "android": {
          "chrome": [
            "Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          ],
          "firefox": [
            "Mozilla/5.0 (Mobile; rv:120.0) Gecko/120.0 Firefox/120.0",
          ],
        },
        "ios": {
          "chrome": [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1",
          ],
          "firefox": [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/120.0.0.0 Mobile/15E148 Safari/605.1.15",
          ],
        },
      },
    },
  };
}
