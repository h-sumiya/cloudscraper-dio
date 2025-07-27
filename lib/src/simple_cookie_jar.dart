class SimpleCookieJar {
  final Map<String, Map<String, String>> _store = {};

  void save(Uri uri, List<String> setCookies) {
    if (setCookies.isEmpty) return;
    final domain = uri.host;
    final jar = _store.putIfAbsent(domain, () => {});
    for (final c in setCookies) {
      final parts = c.split(';')[0];
      final eq = parts.indexOf('=');
      if (eq > 0) {
        final name = parts.substring(0, eq).trim();
        final value = parts.substring(eq + 1).trim();
        if (name.isNotEmpty) jar[name] = value;
      }
    }
  }

  String? header(Uri uri) {
    final domain = uri.host;
    final jar = _store[domain];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
