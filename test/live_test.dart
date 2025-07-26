import 'package:cloudscraper_dio/src/interceptor.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('LIVE: 実URLにアクセスして情報を取得できる', () async {
    final dio = Dio();
    dio.options.validateStatus = (status) => (status ?? 0) < 500;
    dio.options.headers = {
      "origin": "https://www.iwara.tv",
      "referer": "https://www.iwara.tv/",
      "accept-encoding": "gzip",
      "user-agent": "Access Bot", //確実にチャレンジページをトリガーしたい
    };
    dio.interceptors.add(CloudScraperInterceptor());
    final res = await dio.get("https://api.iwara.tv/rules");
    expect(res.statusCode, 200);
    expect(res.data, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
