import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
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

  // Dosya Seçme ve İşleme
  Future<void> _processFile() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (res != null) {
      setState(() => _loading = true);
      try {
        final content = await File(res.files.single.path!).readAsString();
        final result = await AladinM3UParserService.aladinParseM3U(content);
        setState(() {
          _items = result;
          _filteredItems = result;
          _loading = false;
        });
      } catch (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
      }
    }
  }

  // Arama Fonksiyonu
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
    Share.shareXFiles([XFile(file.path)], text: "Aladin IPTV Pro Analiz Raporu");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Modern Koyu Mavi/Siyah
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("ALADIN IPTV PRO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
        onPressed: _processFile,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.file_upload_outlined),
        label: const Text("M3U YÜKLE"),
      ),
    );
  }

  // İstatistik Paneli
  Widget _buildStatsHeader() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("Toplam", _items.length.toString(), Colors.blue),
          _statItem("Dizi", _items.where((e) => e.aladinType == AladinItemType.series).length.toString(), Colors.purple),
          _statItem("Film", _items.where((e) => e.aladinType == AladinItemType.movie).length.toString(), Colors.orange),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  // Arama Çubuğu
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        onChanged: _filter,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "İçerik ara...",
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // Liste Tasarımı
  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.aladinLogo.isNotEmpty 
                  ? Image.network(item.aladinLogo, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallbackIcon(item.aladinType))
                  : _fallbackIcon(item.aladinType),
            ),
            title: Text(item.aladinTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item.aladinRating != null) ...[
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      Text(" ${item.aladinRating}  ", style: const TextStyle(color: Colors.amber, fontSize: 12)),
                    ],
                    if (item.aladinYear != null)
                      Text("• ${item.aladinYear}  ", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.aladinQuality, style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _fallbackIcon(AladinItemType type) {
    IconData icon = Icons.tv;
    if (type == AladinItemType.movie) icon = Icons.movie_outlined;
    if (type == AladinItemType.series) icon = Icons.video_library_outlined;
    return Container(
      width: 50, height: 50,
      color: Colors.white.withOpacity(0.1),
      child: Icon(icon, color: Colors.white54),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 80, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text("Henüz veri yok.\nBir M3U dosyası yükleyerek başlayın.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // Senin İmzan
  Widget _buildSignature() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        "Designed by Alaaddin Specialists",
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 2),
      ),
    );
  }
}