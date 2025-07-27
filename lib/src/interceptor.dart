import 'package:dio/dio.dart';

import 'cloudflare_v2.dart';
import 'cloudflare_v3.dart';
import 'cloudscraper.dart';
import 'dio_cloudscraper.dart';
import 'interpre/base.dart';
import 'interpre/nodejs.dart';
import 'simple_cookie_jar.dart';

class CloudScraperInterceptor extends Interceptor {
  final bool debug;
  final JavaScriptInterpreter interpreter;
  final SimpleCookieJar _jar = SimpleCookieJar();

  CloudScraperInterceptor({
    JavaScriptInterpreter? interpreter,
    this.debug = false,
  }) : interpreter = interpreter ?? NodeJSInterpreter();

  DioCloudscraper _buildScraper(Dio dio) {
    return DioCloudscraper(
      dio,
      interpreter: interpreter,
      cookieJar: _jar,
      debug: debug,
    );
  }

  CfResponse _toCfResponse(Response res) {
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k] = v.join(','));
    return CfResponse(
      statusCode: res.statusCode ?? 0,
      headers: headers,
      body: res.data?.toString() ?? '',
      url: res.realUri,
      request: CfRequest(res.requestOptions.method, res.requestOptions.uri),
    );
  }

  Response _toDioResponse(CfResponse resp, RequestOptions base) {
    final hdr = <String, List<String>>{};
    resp.headers.forEach((k, v) => hdr[k] = [v]);
    return Response(
      data: resp.body,
      headers: Headers.fromMap(hdr),
      statusCode: resp.statusCode,
      requestOptions: base,
    );
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cookie = _jar.header(options.uri);
    if (cookie != null) {
      options.headers['Cookie'] = cookie;
    }
    handler.next(options);
  }

  bool _isChallenge(Response res) {
    if (res.headers.value('cf-mitigated') == 'challenge') {
      return true;
    }
    final cf = _toCfResponse(res);
    return CloudflareV3.isV3Challenge(cf) ||
        CloudflareV2.isV2Challenge(cf) ||
        Cloudflare.isIUAMChallenge(cf);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final setCookies = response.headers.map['set-cookie'];
    if (setCookies != null) {
      _jar.save(response.realUri, setCookies);
    }

    if (!_isChallenge(response)) {
      handler.next(response);
      return;
    }

    final dio = Dio();
    final scraper = _buildScraper(dio);
    final cfResp = _toCfResponse(response);
    final headers = response.requestOptions.headers.cast<String, String>();

    CfResponse solved;
    if (CloudflareV3.isV3Challenge(cfResp)) {
      solved = await CloudflareV3(
        scraper,
      ).handleV3Challenge(cfResp, headers: headers);
    } else if (CloudflareV2.isV2Challenge(cfResp)) {
      solved = await CloudflareV2(
        scraper,
      ).handleV2Challenge(cfResp, headers: headers);
    } else {
      solved = await Cloudflare(
        scraper,
      ).challengeResponse(cfResp, headers: headers);
    }

    final result = _toDioResponse(solved, response.requestOptions);
    handler.resolve(result);
  }
}
