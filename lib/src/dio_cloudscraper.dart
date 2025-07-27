import 'package:dio/dio.dart';

import 'cloudscraper.dart';
import 'interpre/base.dart';
import 'simple_cookie_jar.dart';

class DioCloudscraper implements Cloudscraper {
  @override
  final bool debug;
  @override
  double? delay;
  @override
  final JavaScriptInterpreter interpreter;
  @override
  final Map<String, String> headers;

  final Dio _dio;
  final SimpleCookieJar cookieJar;

  DioCloudscraper(
    this._dio, {
    required this.interpreter,
    required this.cookieJar,
    this.debug = false,
    Map<String, String>? headers,
  }) : headers = headers ?? {} {
    _dio.options.validateStatus = (_) => true;
  }

  @override
  CfResponse decodeBrotli(CfResponse resp) => resp;

  @override
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

  @override
  Future<CfResponse> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Map<String, String>? data,
    bool allowRedirects = true,
  }) async {
    final reqHeaders = {...this.headers, if (headers != null) ...headers};
    final cookie = cookieJar.header(url);
    if (cookie != null) {
      reqHeaders['Cookie'] = cookie;
    }

    final options = Options(
      method: method,
      headers: reqHeaders,
      followRedirects: allowRedirects,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    );

    Response res;
    if (method.toUpperCase() == 'GET') {
      res = await _dio.getUri(url, options: options);
    } else {
      res = await _dio.requestUri(url, options: options, data: data);
    }

    final setCookies = res.headers.map['set-cookie'];
    if (setCookies != null) {
      cookieJar.save(res.realUri, setCookies);
    }

    final headerMap = <String, String>{};
    res.headers.forEach((k, v) => headerMap[k] = v.join(','));

    return CfResponse(
      statusCode: res.statusCode ?? 0,
      headers: headerMap,
      body: res.data?.toString() ?? '',
      url: res.realUri,
      request: CfRequest(method, url),
    );
  }
}
