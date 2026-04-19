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
  bool _loading = false;

  Future<void> _processFile() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles();
    if (res != null) {
      setState(() => _loading = true);
      final content = await File(res.files.single.path!).readAsString();
      _items = await AladinM3UParserService.aladinParseM3U(content);
      setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    final bytes = await AladinExcelExportService.aladinGenerateV3Excel(_items);
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/aladin_rapor.xlsx').writeAsBytes(bytes);
    Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Aladin IPTV Parser V3.2"), actions: [if(_items.isNotEmpty) IconButton(onPressed: _export, icon: const Icon(Icons.download))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _items.length,
        itemBuilder: (c, i) => ListTile(
          title: Text(_items[i].aladinTitle),
          subtitle: Text("IMDb: ${_items[i].aladinRating ?? '-'} | Yıl: ${_items[i].aladinYear ?? '-'}"),
          trailing: Text(_items[i].aladinQuality),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _processFile, child: const Icon(Icons.add)),
    );
  }
}