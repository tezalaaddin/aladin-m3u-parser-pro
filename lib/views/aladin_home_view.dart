import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http; // HTTP paketi eklendi
import '../models/aladin_iptv_item.dart';
import '../services/aladin_m3u_parser_service.dart';
import '../services/aladin_excel_export_service.dart';

class AladinHomeView extends StatefulWidget {
  const AladinHomeView({super.key});

  @override
  State<AladinHomeView> createState() => _AladinHomeViewState();
}

class _AladinHomeViewState extends State<AladinHomeView> {
  List<AladinIPTVItem> _items = [];
  List<AladinIPTVItem> _filteredItems = [];
  bool _loading = false;
  final TextEditingController _searchController = TextEditingController();

  // GitHub Web Sitesini Açma
  Future<void> _launchUrl() async {
    final Uri url = Uri.parse('https://github.com/tezalaaddin/aladin-m3u-parser-pro');
    if (!await launchUrl(url)) {
      _showError("GitHub sayfası açılamadı.");
    }
  }

  // Hata Mesajı Gösterimi
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // 1. YÖNTEM: Yerel Dosya Seçme
  Future<void> _processLocalFile() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (res != null) {
      setState(() => _loading = true);
      try {
        final content = await File(res.files.single.path!).readAsString();
        _parseAndSetData(content);
      } catch (e) {
        setState(() => _loading = false);
        _showError("Dosya okuma hatası: $e");
      }
    }
  }

  // 2. YÖNTEM: M3U URL'den Çekme
  Future<void> _fetchFromUrl(String url) async {
    if (url.isEmpty) return;
    setState(() => _loading = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        _parseAndSetData(response.body);
      } else {
        throw "Bağlantı hatası: ${response.statusCode}";
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError("URL yüklenemedi: $e");
    }
  }

  // Ortak Parser Tetikleyici
  Future<void> _parseAndSetData(String rawData) async {
    try {
      final result = await AladinM3UParserService.aladinParseM3U(rawData);
      setState(() {
        _items = result;
        _filteredItems = result;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError("Veri ayrıştırma hatası: $e");
    }
  }

  // Arama/Filtreleme
  void _filter(String query) {
    setState(() {
      _filteredItems = _items
          .where((item) => item.aladinTitle.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // Excel Dışa Aktarma
  Future<void> _export() async {
    if (_filteredItems.isEmpty) return;
    final bytes = await AladinExcelExportService.aladinGenerateV3Excel(_filteredItems);
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/aladin_analiz_raporu.xlsx').writeAsBytes(bytes);
    Share.shareXFiles([XFile(file.path)], text: "aladin M3U Parser Pro Analiz Raporu");
  }

  // --- DIALOGLAR ---

  void _showUrlDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("M3U URL Yükle"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "http://example.com/playlist.m3u"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchFromUrl(controller.text.trim());
            },
            child: const Text("YÜKLE"),
          ),
        ],
      ),
    );
  }

  void _showXtreamDialog() {
    final serverC = TextEditingController();
    final userC = TextEditingController();
    final passC = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xtream API Girişi"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: serverC, decoration: const InputDecoration(hintText: "Sunucu (http://host:port)")),
            TextField(controller: userC, decoration: const InputDecoration(hintText: "Kullanıcı Adı")),
            TextField(controller: passC, decoration: const InputDecoration(hintText: "Şifre"), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final fullUrl = "${serverC.text}/get.php?username=${userC.text}&password=${passC.text}&type=m3u_plus&output=ts";
              _fetchFromUrl(fullUrl);
            },
            child: const Text("BAĞLAN"),
          ),
        ],
      ),
    );
  }

  void _showSourceMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.file_open, color: Colors.blueAccent),
              title: const Text("Yerel M3U Dosyası Seç"),
              onTap: () { Navigator.pop(context); _processLocalFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.greenAccent),
              title: const Text("M3U URL Adresi Yapıştır"),
              onTap: () { Navigator.pop(context); _showUrlDialog(); },
            ),
            ListTile(
              leading: const Icon(Icons.dns, color: Colors.orangeAccent),
              title: const Text("Xtream API Bilgileri ile Gir"),
              onTap: () { Navigator.pop(context); _showXtreamDialog(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: InkWell(
          onTap: _launchUrl,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/aladin_icon_logo.png', width: 28, height: 28),
                const SizedBox(width: 12),
                const Text("aladin M3U Parser Pro", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(onPressed: _export, icon: const Icon(Icons.description_outlined, color: Colors.greenAccent)),
        ],
      ),
      body: Column(
        children: [
          _buildStatsHeader(),
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                : _items.isEmpty
                    ? _buildEmptyState()
                    : _buildListView(),
          ),
          _buildSignature(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSourceMenu, // Menüyü açar
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("VERİ YÜKLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatsHeader() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("Toplam", _items.length.toString(), Colors.blue),
          _statItem("Dizi", _items.where((e) => e.aladinType == AladinItemType.series).length.toString(), Colors.purpleAccent),
          _statItem("Film", _items.where((e) => e.aladinType == AladinItemType.movie).length.toString(), Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: _searchController,
        onChanged: _filter,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "İçerik ismiyle ara...",
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            onTap: () => _showItemDetails(item),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.aladinLogo.isNotEmpty
                  ? Image.network(
                      item.aladinLogo, width: 45, height: 45, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallbackIcon(item.aladinType),
                    )
                  : _fallbackIcon(item.aladinType),
            ),
            title: Text(item.aladinTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  if (item.aladinRating != null) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 12),
                    Text(" ${item.aladinRating}  ", style: const TextStyle(color: Colors.amber, fontSize: 11)),
                  ],
                  if (item.aladinYear != null)
                    Text("${item.aladinYear}  ", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(item.aladinQuality, style: const TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.info_outline, color: Colors.white24, size: 18),
          ),
        );
      },
    );
  }

  Widget _fallbackIcon(AladinItemType type) {
    IconData icon = type == AladinItemType.movie ? Icons.movie_outlined : (type == AladinItemType.series ? Icons.video_library_outlined : Icons.tv);
    return Container(width: 45, height: 45, color: Colors.white.withOpacity(0.05), child: Icon(icon, color: Colors.white24, size: 20));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo.png', width: 180, opacity: const AlwaysStoppedAnimation(0.6)),
          const SizedBox(height: 20),
          Text("M3U analizine hazır.\nLütfen bir veri kaynağı seçin.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
        ],
      ),
    );
  }

  void _showItemDetails(AladinIPTVItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Text("TEKNİK PARAMETRELER", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
              const SizedBox(height: 16),
              _detailRow("Clean Title", item.aladinTitle),
              _detailRow("Type", item.aladinType.name.toUpperCase()),
              _detailRow("Quality", item.aladinQuality),
              _detailRow("IMDb Rating", item.aladinRating ?? "N/A"),
              _detailRow("Year", item.aladinYear ?? "N/A"),
              _detailRow("Group / Category", item.aladinGroup),
              _detailRow("Container", item.aladinContainer ?? "Unknown"),
              _detailRow("Stream URL", item.aladinUrl),
              _detailRow("Raw Name", item.aladinRawName),
              if (item.aladinType == AladinItemType.series) ...[
                _detailRow("Series Title", item.aladinSeriesTitle),
                _detailRow("Season / Episode", "${item.aladinSeason} / ${item.aladinEpisode}"),
              ],
              _detailRow("Detection Reason", item.aladinTypeReason ?? "Default"),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildSignature() {
    return SafeArea(top: false, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text("DESIGNED BY ALAADDIN SPECIALISTS", style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 9, letterSpacing: 2))));
  }
}