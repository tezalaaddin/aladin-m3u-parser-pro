import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'views/aladin_home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // HATA 1 DÜZELTME: SystemChromeOverlayStyle -> SystemUiOverlayStyle
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        
        // HATA 2 DÜZELTME: CardTheme -> CardThemeData
        cardTheme: CardThemeData(
          color: Colors.white.withOpacity(0.05),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const AladinHomeView(),
    );
  }
}