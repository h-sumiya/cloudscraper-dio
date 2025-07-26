import 'package:cloudscraper_dio/src/interceptor.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  const userAgents = [
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.5615.136 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.199 Safari/537.36",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/117.0",
  ];

  for (int i = 0; i < userAgents.length; i++) {
    final userAgent = userAgents[i];
    final deviceType = i == 0
        ? 'Android'
        : i == 1
        ? 'iPhone'
        : i == 2
        ? 'Windows'
        : 'Linux';

    test(
      'LIVE: 実URLにアクセスして情報を取得できる ($deviceType)',
      () async {
        final dio = Dio();
        dio.options.validateStatus = (status) => (status ?? 0) < 500;
        dio.options.headers = {
          "origin": "https://www.iwara.tv",
          "referer": "https://www.iwara.tv/",
          "accept-encoding": "gzip",
          "user-agent": userAgent,
        };
        dio.interceptors.add(CloudScraperInterceptor());
        final res = await dio.get("https://api.iwara.tv/rules");
        expect(res.statusCode, 200);
        expect(res.data, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }
}
