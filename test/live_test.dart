import 'package:cloudscraper_dio/src/interceptor.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('LIVE: 実URLにアクセスして情報を取得できる', () async {
    final dio = Dio();
    dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3';
    dio.options.validateStatus = (status) => (status ?? 0) < 500;
    dio.options.headers = {
      "origin": "https://www.iwara.tv",
      "referer": "https://www.iwara.tv/",
      "accept-encoding": "gzip",
      "user-agent":
          "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.76 Mobile Safari/537.36",
    };
    dio.interceptors.add(CloudScraperInterceptor());

    final res = await dio.get("https://api.iwara.tv/rules");
    expect(res.statusCode, 200);
    expect(res.data, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
