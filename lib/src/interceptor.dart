import 'package:dio/dio.dart';

import 'cloudflare_v3.dart';
import 'cloudscraper.dart';
import 'dio_cloudscraper.dart';
import 'interpre/nodejs.dart';

class CloudScraperInterceptor extends Interceptor {
  final DioCloudscraper _scraper;

  CloudScraperInterceptor({Dio? dio, bool debug = false})
    : _scraper = DioCloudscraper(
        dio: dio ?? Dio(),
        debug: debug,
        interpreter: NodeJSInterpreter(),
      );

  Future<Response<dynamic>> _perform(RequestOptions options) async {
    final headers = <String, String>{};
    options.headers.forEach((k, v) => headers[k] = v.toString());

    Map<String, String>? data;
    if (options.data is Map) {
      data = {};
      (options.data as Map).forEach((k, v) {
        data![k.toString()] = v.toString();
      });
    }

    CfResponse resp = await _scraper.request(
      options.method,
      options.uri,
      headers: headers,
      data: data,
    );

    if (_scraper.debug) {
      // ignore: avoid_print
      print('CloudScraperInterceptor: initial status ${resp.statusCode}');
    }

    if (CloudflareV3.isV3Challenge(resp)) {
      if (_scraper.debug) {
        // ignore: avoid_print
        print('CloudScraperInterceptor: detected v3 challenge');
      }
      resp = await CloudflareV3(
        _scraper,
      ).handleV3Challenge(resp, headers: headers, data: data);
      if (_scraper.debug) {
        // ignore: avoid_print
        print('CloudScraperInterceptor: challenge solved, retrying');
      }
      resp = await _scraper.request(
        options.method,
        options.uri,
        headers: headers,
        data: data,
      );
    }

    final hMap = <String, List<String>>{};
    resp.headers.forEach((k, v) => hMap[k] = [v]);

    return Response(
      requestOptions: options,
      statusCode: resp.statusCode,
      headers: Headers.fromMap(hMap),
      data: resp.body,
    );
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final response = await _perform(options);
      handler.resolve(response);
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          stackTrace: st,
          type: DioExceptionType.badResponse,
        ),
      );
    }
  }
}
