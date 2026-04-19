import 'package:excel/excel.dart';
import '../models/aladin_iptv_item.dart';

class AladinExcelExportService {
  static Future<List<int>> aladinGenerateV3Excel(List<AladinIPTVItem> items) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['M3U_Analiz_Raporu'];
    excel.delete('Sheet1');

    sheet.appendRow([
      "Tip", "Neden", "Ham İsim (tvg-name)", "Dizi Adı", "Başlık", "Sezon", "Bölüm", "Yıl", "IMDb", "Kalite", "URL"
    ].map((e) => TextCellValue(e)).toList());

    for (var item in items) {
      sheet.appendRow([
        TextCellValue(item.aladinType.name.toUpperCase()),
        TextCellValue(item.aladinTypeReason ?? ""),
        TextCellValue(item.aladinRawName),
        TextCellValue(item.aladinSeriesTitle),
        TextCellValue(item.aladinTitle),
        TextCellValue(item.aladinSeason),
        TextCellValue(item.aladinEpisode),
        TextCellValue(item.aladinYear ?? ""),
        TextCellValue(item.aladinRating ?? ""),
        TextCellValue(item.aladinQuality),
        TextCellValue(item.aladinUrl),
      ].map((e) => e).toList());
    }
    return excel.encode()!;
  }
}