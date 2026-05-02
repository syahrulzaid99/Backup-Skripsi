import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// GANTI sesuai server kamu
const String baseUrl = 'http://192.168.1.23:3000';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue);
    final cs = base.colorScheme;

    return MaterialApp(
      title: 'Aqua Stock Cabang',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: cs.surface,
        cardTheme: CardThemeData(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cs.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// ============================
/// AUTH STORE
/// ============================
class AuthStore {
  static const _kToken = 'auth_token';
  static const _kUsername = 'auth_username';

  static Future<SharedPreferences> _sp() => SharedPreferences.getInstance();

  static Future<bool> hasToken() async {
    final sp = await _sp();
    final t = sp.getString(_kToken);
    return t != null && t.trim().isNotEmpty;
  }

  static Future<String?> token() async {
    final sp = await _sp();
    final t = sp.getString(_kToken);
    if (t == null) return null;
    final tt = t.trim();
    return tt.isEmpty ? null : tt;
  }

  static Future<String?> username() async {
    final sp = await _sp();
    return sp.getString(_kUsername);
  }

  static Future<void> setAuth(
      {required String token, required String username}) async {
    final sp = await _sp();
    await sp.setString(_kToken, token);
    await sp.setString(_kUsername, username);
  }

  static Future<void> clear() async {
    final sp = await _sp();
    await sp.remove(_kToken);
    await sp.remove(_kUsername);
  }
}

/// ============================
/// API CLIENT
/// ============================
class ApiClient {
  static const _timeout = Duration(seconds: 18);
  static Uri _u(String path) => Uri.parse('$baseUrl$path');

  static Future<Map<String, String>> _authHeaders() async {
    final t = await AuthStore.token();
    return t == null ? {} : {'Authorization': 'Bearer $t'};
  }

  static Future<void> login(String username, String password) async {
    final res = await http
        .post(
          _u('/api/v1/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Login gagal (${res.statusCode})');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Token kosong dari server');
    }

    await AuthStore.setAuth(token: token.trim(), username: username);
  }

  static Future<http.Response> getShipment(String kode) async {
    final headers = await _authHeaders();
    return http
        .get(
          _u('/api/v1/cabang/shipments/${Uri.encodeComponent(kode)}'),
          headers: headers,
        )
        .timeout(_timeout);
  }

  static Future<http.StreamedResponse> confirmShipment({
    required String kode,
    required String aksi, // diterima/ditolak
    required String keterangan,
    required List<Map<String, dynamic>> items, // [{idx, qty_diterima, catatan}]
    required List<XFile> photos,
  }) async {
    final headers = await _authHeaders();

    final req = http.MultipartRequest(
      'POST',
      _u('/api/v1/cabang/shipments/${Uri.encodeComponent(kode)}/confirm'),
    );
    req.headers.addAll(headers);

    req.fields['aksi'] = aksi;
    req.fields['keterangan'] = keterangan;
    req.fields['items_json'] = jsonEncode(items);

    for (final ph in photos) {
      final bytes = await ph.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes(
        'photos',
        bytes,
        filename: p.basename(ph.path),
      ));
    }

    return req.send().timeout(_timeout);
  }

  /// List semua pengiriman masuk untuk cabang
  static Future<http.Response> getShipments() async {
    final headers = await _authHeaders();
    return http
        .get(_u('/api/v1/cabang/shipments'), headers: headers)
        .timeout(_timeout);
  }

  /// List semua produk
  static Future<http.Response> getProducts() async {
    final headers = await _authHeaders();
    return http
        .get(_u('/api/v1/cabang/products'), headers: headers)
        .timeout(_timeout);
  }

  /// Buat order baru
  static Future<http.Response> createOrder({
    required List<Map<String, dynamic>> items,
    String keterangan = '',
  }) async {
    final headers = await _authHeaders();
    headers['Content-Type'] = 'application/json';
    return http
        .post(
          _u('/api/v1/cabang/orders'),
          headers: headers,
          body: jsonEncode({'items': items, 'keterangan': keterangan}),
        )
        .timeout(_timeout);
  }

  /// List semua order cabang
  static Future<http.Response> getOrders() async {
    final headers = await _authHeaders();
    return http
        .get(_u('/api/v1/cabang/orders'), headers: headers)
        .timeout(_timeout);
  }
}

/// helper url gambar
String absolutizeUrl(String? u) {
  if (u == null) return '';
  var s = u.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  if (!s.startsWith('/')) s = '/$s';
  return '$baseUrl$s';
}

int _toInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString()) ?? def;
}

String _formatCurrency(num? value) {
  if (value == null) return 'Rp 0';
  final s = value.toInt().toString();
  var res = '';
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && i % 3 == 0) res = '.$res';
    res = '${s[s.length - 1 - i]}$res';
  }
  return 'Rp $res';
}

/// ============================
/// AUTH GATE
/// ============================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _has;

  @override
  void initState() {
    super.initState();
    _has = AuthStore.hasToken();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _has,
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snap.data == true ? const HomePage() : const LoginPage();
      },
    );
  }
}

/// ============================
/// LOGIN PAGE
/// ============================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _doLogin() async {
    final user = _u.text.trim();
    final pass = _p.text;

    if (user.isEmpty || pass.isEmpty) {
      _snack('Username & password wajib diisi');
      return;
    }

    setState(() => _loading = true);
    try {
      await ApiClient.login(user, pass);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: cs.primaryContainer,
                  child:
                      Icon(Icons.local_shipping, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aqua Stock Cabang',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('Login untuk scan & konfirmasi resi',
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _u,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _p,
                      obscureText: _obscure,
                      onSubmitted: (_) => _loading ? null : _doLogin(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _loading ? null : _doLogin,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('Login'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================
/// HOME PAGE (BOTTOM NAV)
/// ============================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _idx = 1; // default ke Scan

  Future<void> _logout() async {
    await AuthStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const StockPage(),
      const ScanPage(),
      const OrderPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aqua Stock Cabang'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: IndexedStack(index: _idx, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stok Masuk',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan Resi',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Order',
          ),
        ],
      ),
    );
  }
}

/// ============================
/// SCAN PAGE
/// ============================
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _handled = false;
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _openDetail(String kode) {
    final k = kode.trim();
    if (k.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => DetailPage(kode: k)))
        .then((_) => setState(() => _handled = false));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.trim().isEmpty) return;
    setState(() => _handled = true);
    _openDetail(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<String?>(
          future: AuthStore.username(),
          builder: (_, snap) => Card(
            color: cs.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: cs.onSecondaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Login: ${snap.data ?? '-'}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('Arahkan ke barcode resi',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: MobileScanner(onDetect: _onDetect),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    decoration: const InputDecoration(
                      labelText: 'Input manual',
                      hintText: 'TRX-YYYYMMDD-XXXX',
                      prefixIcon: Icon(Icons.qr_code_2),
                    ),
                    onSubmitted: _openDetail,
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                    onPressed: () => _openDetail(_manual.text),
                    child: const Text('Cek')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ============================
/// DETAIL PAGE + CONFIRM
/// ============================
class DetailPage extends StatefulWidget {
  final String kode;
  const DetailPage({super.key, required this.kode});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _busy = false;

  // confirm state
  String _aksi = 'diterima'; // diterima/ditolak
  final _keteranganCtrl = TextEditingController();
  final List<TextEditingController> _qtyCtrls = [];
  final List<TextEditingController> _catCtrls = [];

  // photos
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _localPhotos = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    for (final c in _catCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _gotoLogin() async {
    await AuthStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _resetItemControllers(int len, List<dynamic> items) {
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    for (final c in _catCtrls) {
      c.dispose();
    }
    _qtyCtrls.clear();
    _catCtrls.clear();

    for (int i = 0; i < len; i++) {
      final it = Map<String, dynamic>.from(items[i] as Map);
      final qty = _toInt(it['qty'] ?? it['_qty'] ?? it['jumlah'] ?? 0);
      _qtyCtrls.add(TextEditingController(text: qty.toString()));
      _catCtrls.add(TextEditingController(text: ''));
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.getShipment(widget.kode);

      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        _data = m;

        final items = (m['items'] as List<dynamic>? ?? []);
        if (_qtyCtrls.length != items.length) {
          _resetItemControllers(items.length, items);
        }
        if (mounted) setState(() {});
        return;
      }

      if (res.statusCode == 401) {
        _snack('Sesi habis. Login ulang.');
        await _gotoLogin();
        return;
      }

      if (res.statusCode == 403) {
        _snack('Resi ini bukan untuk cabang kamu.');
        if (mounted) Navigator.pop(context);
        return;
      }

      if (res.statusCode == 404) {
        _snack('Resi tidak ditemukan.');
        if (mounted) Navigator.pop(context);
        return;
      }

      _snack('Gagal ambil data (${res.statusCode})');
    } catch (_) {
      _snack('Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCamera() async {
    final ph =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (ph != null) setState(() => _localPhotos.add(ph));
  }

  Future<void> _pickGallery() async {
    final list = await _picker.pickMultiImage(imageQuality: 80);
    if (list.isNotEmpty) setState(() => _localPhotos.addAll(list));
  }

  Future<void> _confirm() async {
    final data = _data;
    if (data == null) {
      _snack('Data tidak tersedia');
      return;
    }

    // Validasi: cek apakah sudah locked
    if (_isLocked(data)) {
      _snack('Resi sudah dikonfirmasi sebelumnya');
      return;
    }

    setState(() => _busy = true);
    try {
      final itemsRaw = (data['items'] as List<dynamic>? ?? []);
      final items = <Map<String, dynamic>>[];

      // Build items untuk dikirim ke server
      for (int i = 0; i < itemsRaw.length; i++) {
        final qtyText = _qtyCtrls[i].text.trim();
        final qty = int.tryParse(qtyText) ?? 0;

        items.add({
          'idx': i,
          'qty_diterima': qty,
          'catatan': _catCtrls[i].text.trim(),
        });
      }

      print('🚀 Mengirim konfirmasi:');
      print('   Kode: ${widget.kode}');
      print('   Aksi: $_aksi');
      print('   Items: ${items.length}');
      print('   Photos: ${_localPhotos.length}');

      final res = await ApiClient.confirmShipment(
        kode: widget.kode,
        aksi: _aksi,
        keterangan: _keteranganCtrl.text.trim(),
        items: items,
        photos: _localPhotos,
      );

      print('📥 Response status: ${res.statusCode}');

      if (res.statusCode == 200) {
        _localPhotos.clear();
        _snack('✅ Konfirmasi berhasil: ${_aksi.toUpperCase()}');
        await _fetch(); // Refresh data
        return;
      }

      if (res.statusCode == 401) {
        _snack('Sesi habis. Login ulang.');
        await _gotoLogin();
        return;
      }

      if (res.statusCode == 403) {
        _snack('Tidak boleh: resi bukan milik cabang kamu.');
        if (mounted) Navigator.pop(context);
        return;
      }

      if (res.statusCode == 409) {
        _snack('Resi sudah pernah dikonfirmasi.');
        await _fetch(); // Refresh untuk update UI
        return;
      }

      // Error lainnya
      final body = await res.stream.bytesToString();
      print('❌ Error body: $body');
      _snack('Gagal konfirmasi (${res.statusCode})');
    } catch (e, stackTrace) {
      print('❌ Exception: $e');
      print('Stack: $stackTrace');
      _snack('Gagal konfirmasi: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isLocked(Map<String, dynamic> data) {
    final st = (data['status'] ?? '').toString().toLowerCase();
    return st == 'diterima' || st == 'ditolak';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading && data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.kode)),
        body: const Center(child: Text('Data tidak tersedia')),
      );
    }

    final locked = _isLocked(data);
    final items = (data['items'] as List<dynamic>? ?? []);

    final pengirim = (data['pengirim'] ?? '-').toString();
    final penerima = (data['penerima'] ?? '-').toString();
    final status = (data['status'] ?? '-').toString();

    final alamatJalan = (data['alamat_penerima_jalan'] ?? '').toString();
    final alamatKota = (data['alamat_penerima_kota'] ?? '').toString();
    final alamatProv = (data['alamat_penerima_provinsi'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(data['kode_pengiriman']?.toString() ?? widget.kode),
        actions: [
          IconButton(
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // SUMMARY
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['kode_pengiriman']?.toString() ??
                                  widget.kode,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                          ),
                          _StatusChip(status: status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                          icon: Icons.storefront,
                          label: 'Pengirim',
                          value: pengirim),
                      const SizedBox(height: 6),
                      _InfoRow(
                          icon: Icons.home_work,
                          label: 'Penerima',
                          value: penerima),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      _InfoRow(
                          icon: Icons.monetization_on,
                          label: 'Total Harga',
                          value: _formatCurrency(data['total_harga'] ?? 0)),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text('Alamat Penerima',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                if (alamatJalan.isNotEmpty) alamatJalan,
                                [
                                  if (alamatKota.isNotEmpty) alamatKota,
                                  if (alamatProv.isNotEmpty) alamatProv
                                ].join(', '),
                              ]
                                  .where((e) => e.toString().trim().isNotEmpty)
                                  .join('\n'),
                            ),
                          ),
                        ],
                      ),
                    ]),
              ),
            ),

            const SizedBox(height: 14),

            // ITEMS LIST
            const Text('Daftar Barang',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Belum ada item')))
            else
              ...items.asMap().entries.map((e) {
                final it = Map<String, dynamic>.from(e.value as Map);

                final nama =
                    (it['nama_produk'] ?? it['_nama_produk'] ?? '-').toString();
                final barcode =
                    (it['barcode'] ?? it['_barcode'] ?? '').toString();
                final sku = (it['sku'] ?? '').toString();
                final satuan = (it['satuan'] ?? '').toString();
                final qty =
                    _toInt(it['qty'] ?? it['_qty'] ?? it['jumlah'] ?? 0);
                final harga = it['harga'] ?? 0;

                final img = absolutizeUrl(
                  (it['gambar_url'] ?? it['imageUrl'] ?? it['image_url'])
                      ?.toString(),
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    leading: _Thumb(url: img),
                    title: Text(nama,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(
                      [
                        if (sku.isNotEmpty) 'SKU: $sku',
                        if (barcode.isNotEmpty) 'Barcode: $barcode',
                        if (satuan.isNotEmpty) 'Satuan: $satuan',
                        'Harga: ${_formatCurrency(harga)} (Subtotal: ${_formatCurrency(qty * harga)})',
                      ].join('\n'),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context).colorScheme.primaryContainer,
                      ),
                      child: Text(
                        'Qty\n$qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 14),

            // CONFIRM SECTION
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Konfirmasi Penerimaan',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Diterima'),
                          selected: _aksi == 'diterima',
                          onSelected: locked
                              ? null
                              : (_) => setState(() => _aksi = 'diterima'),
                        ),
                        ChoiceChip(
                          label: const Text('Ditolak'),
                          selected: _aksi == 'ditolak',
                          onSelected: locked
                              ? null
                              : (_) => setState(() => _aksi = 'ditolak'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _keteranganCtrl,
                      enabled: !locked,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Keterangan / Kondisi Umum',
                        hintText:
                            'Contoh: dus penyok, segel aman, ada item kurang, dll.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Kondisi per Item',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      const Text('Tidak ada item')
                    else
                      ...items.asMap().entries.map((e) {
                        final idx = e.key;
                        final it = Map<String, dynamic>.from(e.value as Map);
                        final nama =
                            (it['nama_produk'] ?? it['_nama_produk'] ?? '-')
                                .toString();
                        final qtyAwal = _toInt(
                            it['qty'] ?? it['_qty'] ?? it['jumlah'] ?? 0);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ExpansionTile(
                            title: Text(nama,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            subtitle: Text('Qty awal: $qtyAwal'),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _qtyCtrls[idx],
                                      enabled: !locked,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Qty diterima',
                                        prefixIcon: Icon(Icons.numbers),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _catCtrls[idx],
                                enabled: !locked,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Catatan kondisi item',
                                  hintText:
                                      'Contoh: segel rusak 1, botol bocor, dll.',
                                  prefixIcon: Icon(Icons.note_alt),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: locked || _busy ? null : _confirm,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.verified),
                      label: Text(locked ? 'Sudah Dikonfirmasi' : 'Konfirmasi'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // SERVER PROOFS
            const Text('Bukti di Server',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            _ServerProofs(
                urls: (data['bukti_penerimaan_urls'] as List<dynamic>? ?? [])
                    .map((e) => e.toString())
                    .toList()),

            const SizedBox(height: 14),

            // LOCAL PHOTOS
            const Text('Foto Bukti (Belum Dikirim)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            _LocalProofs(
              photos: _localPhotos,
              onRemove: locked || _busy
                  ? null
                  : (i) => setState(() {
                        _localPhotos.removeAt(i);
                      }),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: locked || _busy ? null : _pickCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: locked || _busy ? null : _pickGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeri'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================
/// STOCK PAGE (Stok Masuk)
/// ============================
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  List<Map<String, dynamic>> _shipments = [];
  bool _loading = false;
  String _filter = 'semua';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.getShipments();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['shipments'] as List<dynamic>? ?? []);
        _shipments = list.cast<Map<String, dynamic>>();
      } else if (res.statusCode == 401) {
        _snack('Sesi habis. Login ulang.');
      } else {
        _snack('Gagal memuat data (${res.statusCode})');
      }
    } catch (_) {
      _snack('Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'semua') return _shipments;
    return _shipments
        .where((s) =>
            (s['status'] ?? '').toString().toLowerCase() == _filter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: _loading && _shipments.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      for (final f in ['semua', 'dikirim', 'diterima', 'ditolak'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(f[0].toUpperCase() + f.substring(1)),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                // List
                Expanded(
                  child: _filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 64, color: Colors.black26),
                                  SizedBox(height: 12),
                                  Text('Belum ada pengiriman',
                                      style: TextStyle(color: Colors.black45)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final s = _filtered[i];
                            final kode = s['kode_pengiriman'] ?? '-';
                            final status = s['status'] ?? '-';
                            final pengirim = s['pengirim'] ?? '-';
                            final total = s['total_harga'] ?? 0;
                            final jumlahItem = s['jumlah_item'] ?? 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DetailPage(kode: kode),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              kode,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15),
                                            ),
                                          ),
                                          _StatusChip(status: status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.storefront,
                                              size: 16,
                                              color: cs.primary),
                                          const SizedBox(width: 6),
                                          Text('Dari: $pengirim',
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.inventory_2,
                                              size: 16,
                                              color: cs.primary),
                                          const SizedBox(width: 6),
                                          Text('$jumlahItem item',
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          const Spacer(),
                                          Text(
                                            _formatCurrency(total),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// ============================
/// ORDER PAGE
/// ============================
class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.add_shopping_cart), text: 'Buat Order'),
            Tab(icon: Icon(Icons.history), text: 'Riwayat'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _CreateOrderTab(onCreated: () {
                _tabCtrl.animateTo(1);
              }),
              const _OrderHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// ============================
/// CREATE ORDER TAB
/// ============================
class _CreateOrderTab extends StatefulWidget {
  final VoidCallback? onCreated;
  const _CreateOrderTab({this.onCreated});

  @override
  State<_CreateOrderTab> createState() => _CreateOrderTabState();
}

class _CreateOrderTabState extends State<_CreateOrderTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _products = [];
  final Map<String, int> _cart = {}; // product_id -> qty
  final _keteranganCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _sending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetchProducts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.getProducts();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _products = (data['products'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
      } else {
        _snack('Gagal memuat produk');
      }
    } catch (_) {
      _snack('Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) {
      final nama = (p['nama_produk'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      return nama.contains(q) || sku.contains(q);
    }).toList();
  }

  int get _totalItems => _cart.values.fold(0, (a, b) => a + b);

  num get _totalHarga {
    num total = 0;
    for (final e in _cart.entries) {
      final p = _products.firstWhere(
        (p) => p['id'] == e.key,
        orElse: () => <String, dynamic>{},
      );
      total += (p['harga_jual'] ?? 0) * e.value;
    }
    return total;
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) {
      _snack('Pilih minimal 1 produk');
      return;
    }

    setState(() => _sending = true);
    try {
      final items = _cart.entries
          .map((e) => {'product_id': e.key, 'qty': e.value})
          .toList();

      final res = await ApiClient.createOrder(
        items: items,
        keterangan: _keteranganCtrl.text.trim(),
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _snack('✅ Order ${body['kode_order']} berhasil dibuat!');
        _cart.clear();
        _keteranganCtrl.clear();
        setState(() {});
        widget.onCreated?.call();
      } else {
        _snack('Gagal membuat order (${res.statusCode})');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),
        ),
        // Product list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredProducts.length,
            itemBuilder: (_, i) {
              final p = _filteredProducts[i];
              final id = p['id'] as String;
              final nama = p['nama_produk'] ?? '-';
              final sku = p['sku'] ?? '';
              final satuan = p['satuan'] ?? '';
              final harga = p['harga_jual'] ?? 0;
              final stok = p['stok'] ?? 0;
              final img = absolutizeUrl(p['gambar_url']?.toString());
              final qty = _cart[id] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _Thumb(url: img),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nama,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            if (sku.isNotEmpty)
                              Text('SKU: $sku',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            Text(
                              '${_formatCurrency(harga)} / $satuan',
                              style: TextStyle(
                                  fontSize: 12, color: cs.primary),
                            ),
                            Text('Stok: $stok',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black45)),
                          ],
                        ),
                      ),
                      // Qty controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (qty > 0)
                            IconButton(
                              icon: Icon(Icons.remove_circle,
                                  color: cs.error),
                              onPressed: () {
                                setState(() {
                                  if (qty <= 1) {
                                    _cart.remove(id);
                                  } else {
                                    _cart[id] = qty - 1;
                                  }
                                });
                              },
                            ),
                          if (qty > 0)
                            Text('$qty',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16)),
                          IconButton(
                            icon: Icon(Icons.add_circle,
                                color: cs.primary),
                            onPressed: () {
                              setState(() {
                                _cart[id] = qty + 1;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom bar: summary + submit
        if (_cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _keteranganCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (opsional)',
                    prefixIcon: Icon(Icons.note_alt),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$_totalItems produk',
                              style: const TextStyle(fontSize: 13)),
                          Text(
                            _formatCurrency(_totalHarga),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _sending ? null : _submitOrder,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                      label: const Text('Kirim Order'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ============================
/// ORDER HISTORY TAB
/// ============================
class _OrderHistoryTab extends StatefulWidget {
  const _OrderHistoryTab();

  @override
  State<_OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<_OrderHistoryTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.getOrders();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _orders = (data['orders'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
      } else {
        _snack('Gagal memuat riwayat order');
      }
    } catch (_) {
      _snack('Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'diproses':
        return Colors.blue;
      case 'dikirim':
        return Colors.indigo;
      case 'selesai':
        return Colors.green;
      case 'ditolak':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: _orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 64, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('Belum ada order',
                          style: TextStyle(color: Colors.black45)),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final o = _orders[i];
                final kode = o['kode_order'] ?? '-';
                final status = (o['status'] ?? 'pending').toString();
                final total = o['total_harga'] ?? 0;
                // jumlah_item available in o['jumlah_item']
                final items =
                    (o['items'] as List<dynamic>? ?? []);
                final ket = o['keterangan'] ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    title: Text(kode,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(_formatCurrency(total),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.primary)),
                      ],
                    ),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      if (ket.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.note_alt,
                                  size: 16, color: Colors.black45),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(ket,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54)),
                              ),
                            ],
                          ),
                        ),
                      ...items.map((it) {
                        final item =
                            Map<String, dynamic>.from(it as Map);
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['nama_produk'] ?? '-',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                'x${item['qty']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  _formatCurrency(
                                      item['subtotal'] ?? 0),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// ============================
/// SMALL UI WIDGETS
/// ============================
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.black54))),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    IconData icon = Icons.hourglass_bottom;
    String text = status;

    if (s.contains('diterima')) {
      icon = Icons.check_circle;
      text = 'Diterima';
    } else if (s.contains('ditolak')) {
      icon = Icons.cancel;
      text = 'Ditolak';
    } else if (s.contains('draft')) {
      icon = Icons.edit_note;
      text = 'Draft';
    } else if (s.contains('kirim') || s.contains('dikirim')) {
      icon = Icons.local_shipping;
      text = 'Dikirim';
    }

    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (url.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest,
        ),
        child: Icon(Icons.inventory_2, color: cs.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        loadingBuilder: (c, w, p) => p == null
            ? w
            : Container(color: Colors.black12, width: 56, height: 56),
        errorBuilder: (_, __, ___) => Container(
          width: 56,
          height: 56,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ServerProofs extends StatelessWidget {
  final List<String> urls;
  const _ServerProofs({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Belum ada bukti di server')));
    }

    final fixed =
        urls.map((u) => absolutizeUrl(u)).where((u) => u.isNotEmpty).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fixed.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          fixed[i],
          fit: BoxFit.cover,
          loadingBuilder: (c, w, p) =>
              p == null ? w : Container(color: Colors.black12),
          errorBuilder: (_, __, ___) => Container(
              color: Colors.black12, child: const Icon(Icons.broken_image)),
        ),
      ),
    );
  }
}

class _LocalProofs extends StatelessWidget {
  final List<XFile> photos;
  final void Function(int index)? onRemove;

  const _LocalProofs({required this.photos, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(14), child: Text('Belum ada foto')));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (_, i) {
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(File(photos[i].path), fit: BoxFit.cover),
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: 6,
                top: 6,
                child: InkWell(
                  onTap: () => onRemove!(i),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child:
                        const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
