import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/aladin_iptv_item.dart';

class AladinM3UParserService {
  static Future<List<AladinIPTVItem>> aladinParseM3U(String content) async {
    final List<Map<String, dynamic>> raw = await compute(_aladinParseTaskMap, content);
    return raw.map(_mapToItem).toList(growable: false);
  }

  static List<Map<String, dynamic>> _aladinParseTaskMap(String content) {
    final List<Map<String, dynamic>> playlist = [];
    final lines = const LineSplitter().convert(content);

    final qRegex = RegExp(r'(HEVC|(?:50|60)\s?FPS|4K|UHD|FHD|1080P|HD\+|HD|720P|SD)', caseSensitive: false);
    // IMDb için \b kaldırıldı, daha agresif yakalama yapar:
    final imdbRegex = RegExp(r'(?:IMDb|IMDB)\s*[:\]\-]?\s*(\d{1,2}(?:[.,]\d{1,2})?)', caseSensitive: false);
    final yearRegex = RegExp(r'[\(\[\{]\s*(19\d{2}|20\d{2})\s*[\)\]\}]');
    final seRegex = RegExp(r'\bS(\d{1,2})\s*E(\d{1,3})\b', caseSensitive: false);
    final diziStartRegex = RegExp(r'^\s*DIZI\b', caseSensitive: false);
    final diziPrefixRegex = RegExp(r'^\s*DIZI\s+[A-ZÇĞİÖŞÜ]+\s*:\s*', caseSensitive: false);
    final dateRegex = RegExp(r'\b(\d{2}\.\d{2}\.\d{4})\b');
    
    final tvgNameRegex = RegExp(r'tvg-name="(.*?)"', caseSensitive: false);
    final logoRegex = RegExp(r'tvg-logo="(.*?)"', caseSensitive: false);
    final groupRegex = RegExp(r'group-title="(.*?)"', caseSensitive: false);
    final vlcOptRegex = RegExp(r'^#EXTVLCOPT:(.*)$', caseSensitive: false);
    final videoExtRegex = RegExp(r'\.(mkv|mp4|avi|mov|wmv|flv|mpg|mpeg|m4v)$', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final extinf = lines[i].trim();
      if (!extinf.startsWith('#EXTINF:')) continue;

      final scan = _scanUrlAndOptions(lines: lines, startIndex: i + 1, vlcOptRegex: vlcOptRegex);
      final url = scan.url;
      if (url.isEmpty || !url.startsWith('http')) continue;

      final rawNameOriginal = extinf.split(',').last.trim();
      final tvgNameAttr = tvgNameRegex.firstMatch(extinf)?.group(1)?.trim() ?? '';
      
      // ✅ İSTEK 1: aladinRawName = tvg-name olmalı
      String aladinRawNameValue = tvgNameAttr.isNotEmpty ? tvgNameAttr : rawNameOriginal;

      // ✅ İSTEK 2: IMDb/Yıl yakalamak için hibrit kaynak
      final metaSource = "$tvgNameAttr | $rawNameOriginal";

      if (_isSeparator(rawNameOriginal)) continue;

      final logo = logoRegex.firstMatch(extinf)?.group(1) ?? '';
      final groupRaw = groupRegex.firstMatch(extinf)?.group(1) ?? 'Genel';
      final group = _normalizeGroup(groupRaw);

      final lowerUrl = url.toLowerCase();
      final seMatch = seRegex.firstMatch(metaSource);
      final isDizi = diziStartRegex.hasMatch(metaSource);

      final looksSeries = lowerUrl.contains('/series/') || seMatch != null || isDizi;
      final looksMovie = lowerUrl.contains('/movie/') || videoExtRegex.hasMatch(lowerUrl);

      AladinItemType type = AladinItemType.tv;
      String typeReason = 'default-tv';
      String sNum = '', eNum = '', sTitle = '';
      int? sNo, eNo;

      if (looksSeries) {
        type = AladinItemType.series;
        if (isDizi) {
          typeReason = 'prefix:DIZI';
          var show = rawNameOriginal.replaceFirst(diziPrefixRegex, '').trim();
          final dm = dateRegex.firstMatch(show);
          if (dm != null) {
            eNum = dm.group(1)!;
            sNum = eNum.split('.').last;
            show = show.replaceAll(eNum, '').trim();
          }
          sTitle = show.replaceAll(RegExp(r'[\(\)\[\]\{\}]'), '').trim();
        } else if (seMatch != null) {
          typeReason = 'pattern:SxxExx';
          sNum = seMatch.group(1)!; eNum = seMatch.group(2)!;
          sNo = int.tryParse(sNum); eNo = int.tryParse(eNum);
          sTitle = rawNameOriginal.split(seMatch.group(0)!).first.trim();
        }
      } else if (looksMovie) {
        type = AladinItemType.movie;
        typeReason = lowerUrl.contains('/movie/') ? 'url:/movie/' : 'ext:video';
      }

      final imdbMatch = imdbRegex.firstMatch(metaSource);
      String? rating = imdbMatch?.group(1)?.replaceAll(',', '.');
      if (rating != null && (double.tryParse(rating) ?? 0) <= 0) rating = null;

      final yMatches = yearRegex.allMatches(metaSource).toList();
      final year = yMatches.isNotEmpty ? yMatches.last.group(1) : null;

      final qTags = qRegex.allMatches(metaSource).map((m) => _normalizeQualityToken(m.group(0)!)).toSet();
      final quality = _buildOrderedQualityString(qTags);

      playlist.add({
        'aladinTitle': (isDizi && sTitle.isNotEmpty) ? sTitle : _cleanTitle(rawNameOriginal, qRegex, imdbRegex, yearRegex),
        'aladinRawName': aladinRawNameValue,
        'aladinSeriesTitle': sTitle,
        'aladinYear': year,
        'aladinRating': rating,
        'aladinQuality': quality,
        'aladinGroup': group,
        'aladinUrl': url,
        'aladinLogo': logo,
        'aladinType': type.name,
        'aladinSeason': sNum,
        'aladinEpisode': eNum,
        'aladinTypeReason': typeReason,
        'aladinContainer': _detectContainer(lowerUrl),
        'aladinLineIndex': i,
      });
    }
    return playlist;
  }

  // Yardımcı metodlar (Önceki sürümlerdeki _normalizeQualityToken, _cleanTitle vb. aynen dahil edilmeli)
  static String _normalizeQualityToken(String t) {
    t = t.toUpperCase().trim();
    if (t.contains('50FPS')) return '50FPS';
    if (t.contains('60FPS')) return '60FPS';
    return t.replaceAll(' ', '');
  }

  static String _buildOrderedQualityString(Set<String> tags) {
    if (tags.isEmpty) return '';
    const order = ['HEVC', '4K', 'UHD', 'FHD', '1080P', 'HD+', 'HD', '720P', 'SD', '60FPS', '50FPS'];
    return order.where(tags.contains).join(' ');
  }

  static String _cleanTitle(String r, RegExp q, RegExp im, RegExp y) {
    return r.replaceAll(q, '').replaceAll(im, '').replaceAll(y, '').replaceAll(RegExp(r'[\._\(\)\[\]\{\}]'), ' ').trim();
  }

  static bool _isSeparator(String n) => n.trim().isEmpty || n.contains('####') || RegExp(r'^[#\*\-_= ]{3,}$').hasMatch(n);
  static String _normalizeGroup(String r) => r.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  static String _detectContainer(String u) => RegExp(r'\.(m3u8|mpd|mkv|mp4|avi)$').firstMatch(u.split('?').first)?.group(1) ?? '';

  static _ScanResult _scanUrlAndOptions({required List<String> lines, required int startIndex, required RegExp vlcOptRegex}) {
    for (int j = startIndex; j < lines.length; j++) {
      if (lines[j].startsWith('http')) return _ScanResult(url: lines[j].trim());
    }
    return _ScanResult(url: '');
  }

  static AladinIPTVItem _mapToItem(Map<String, dynamic> m) {
    return AladinIPTVItem(
      aladinTitle: m['aladinTitle'], aladinRawName: m['aladinRawName'],
      aladinSeriesTitle: m['aladinSeriesTitle'], aladinYear: m['aladinYear'],
      aladinRating: m['aladinRating'], aladinQuality: m['aladinQuality'],
      aladinGroup: m['aladinGroup'], aladinUrl: m['aladinUrl'],
      aladinLogo: m['aladinLogo'], aladinSeason: m['aladinSeason'],
      aladinEpisode: m['aladinEpisode'], aladinType: AladinItemType.values.byName(m['aladinType']),
      aladinTypeReason: m['aladinTypeReason'], aladinContainer: m['aladinContainer'], aladinLineIndex: m['aladinLineIndex'],
    );
  }
}

class _ScanResult { final String url; _ScanResult({required this.url}); }