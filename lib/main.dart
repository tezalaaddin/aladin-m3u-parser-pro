import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'views/aladin_home_view.dart';

void main() {
  // Durum çubuğunu (StatusBar) şeffaf ve uygulama temasına uygun yapalım
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemChromeOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const AladinIPTVProApp());
}

class AladinIPTVProApp extends StatelessWidget {
  const AladinIPTVProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aladin IPTV Pro',
      debugShowCheckedModeBanner: false,
      
      // Uygulama genelinde modern "Dark Mode" teması
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Home view ile aynı koyu ton
        
        // Font tasarımı ve metin stilleri
        fontFamily: 'Roboto', // Varsa özel fontun buraya yazabilirsin
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        
        // Kart yapıları için genel stil
        cardTheme: CardTheme(
          color: Colors.white.withOpacity(0.05),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      
      home: const AladinHomeView(),
    );
  }
}