import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Required for PointerDeviceKind
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; // 🔔 Audio Support

// ⚠️ CONFIGURATION: YOUR IP ADDRESS
const String SERVER_URL = "http://10.200.97.43:5000";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()..loadLanguage()),
      ],
      child: const ToxicPlantApp(),
    ),
  );
}

// ============================================================================
// 1. LANGUAGE PROVIDER
// ============================================================================
class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('en');
  Map<String, String> _localizedStrings = {};
  List<Map<String, dynamic>> _availableLanguages = [];
  List<String> _installedLanguages = ['en'];

  Locale get currentLocale => _currentLocale;
  List<Map<String, dynamic>> get availableLanguages => _availableLanguages;
  List<String> get installedLanguages => _installedLanguages;

  String getText(String key) {
    return _localizedStrings[key] ?? key;
  }

  Future<void> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedInstalled = prefs.getStringList('installed_languages');
    if (savedInstalled != null) _installedLanguages = savedInstalled;

    String langCode = prefs.getString('language_code') ?? 'en';
    await switchLanguage(langCode);
    fetchAvailableLanguages();
  }

  Future<void> fetchAvailableLanguages() async {
    try {
      final response = await http.get(Uri.parse('$SERVER_URL/languages'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        _availableLanguages = List<Map<String, dynamic>>.from(data);
        notifyListeners();
      }
    } catch (e) {
      print("Error fetching languages: $e");
    }
  }

  Future<bool> downloadLanguage(String code) async {
    try {
      final response = await http.get(Uri.parse('$SERVER_URL/languages/$code'));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$code.json');
        await file.writeAsString(response.body);

        if (!_installedLanguages.contains(code)) {
          _installedLanguages.add(code);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('installed_languages', _installedLanguages);
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Download error: $e");
      return false;
    }
  }

  Future<void> switchLanguage(String code) async {
    Map<String, dynamic> jsonMap = {};

    if (code == 'en') {
       // Default English Fallback
       jsonMap = {
          "app_title": "FloraGuard",
          "scan_plant": "Scan a Plant",
          "camera": "Camera",
          "gallery": "Gallery",
          "toxic": "TOXIC PLANT",
          "safe": "LIKELY SAFE",
          "confidence": "Confidence",
          "symptoms": "SYMPTOMS",
          "action": "CAUSE", 
          "loading": "Analyzing...",
          "settings": "Language Settings",
          "about_title": "About FloraGuard",
          "download": "Download",
          "installed": "Installed",
          "active": "Active",
          "switch": "Switch",
          "unknown": "Unknown Plant",
          "safe_title": "No Toxic Plant Detected",
          "safe_body_text": "The image does not match any known toxic plants.",
          "safe_action_text": "Likely safe. However, never ingest unknown plants.",
          "source_label": "Source",
          "safe_body_plantnet": "Identified as likely safe or non-toxic by visual analysis."
       };
    } else {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$code.json');
        if (await file.exists()) {
          String content = await file.readAsString();
          Map<String, dynamic> rawJson = json.decode(content);

          if (rawJson.containsKey('data') && rawJson['data'] is Map) {
            jsonMap = Map<String, dynamic>.from(rawJson['data']);
          } else {
            jsonMap = rawJson;
          }
        } else {
          bool success = await downloadLanguage(code);
          if (success) return switchLanguage(code);
          return;
        }
      } catch (e) {
        print("Error loading language file: $e");
        return;
      }
    }

    // 🟢 FIX: Extract the base language (e.g., 'es-MX' -> 'es')
    // This ensures we match the translation even if there is a region code.
    String baseLang = code.split('_')[0].split('-')[0].toLowerCase();

    // 🟢 1. FORCE "CAUSE" TRANSLATION using baseLang
    Map<String, String> causeTranslations = {
      'en': 'Cause', 'es': 'Causa', 'fr': 'Cause', 'de': 'Ursache', 'it': 'Causa',
      'pt': 'Causa', 'nl': 'Oorzaak', 'ru': 'Причина', 'zh': '原因', 'ja': '原因',
      'ko': '원인', 'hi': 'कारण', 'ar': 'السبب', 'tr': 'Sebep', 'id': 'Penyebab',
      'pl': 'Przyczyna', 'vi': 'Nguyên nhân', 'th': 'สาเหตุ', 'ms': 'Punca',
    };
    jsonMap['action'] = causeTranslations[baseLang] ?? "Cause";

    // 🟢 2. INJECT ABOUT PAGE TRANSLATIONS using baseLang
    Map<String, String> aboutText = _getAboutTranslations(baseLang);
    jsonMap.addAll(aboutText);

    _localizedStrings = jsonMap.map((key, value) => MapEntry(key, value.toString()));
    _currentLocale = Locale(code);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    notifyListeners();
  }

  // 🆕 HELPER: Translations for the About Page
  // Uses 'baseLang' to ensure broader compatibility
  Map<String, String> _getAboutTranslations(String baseCode) {
    // Default English
    Map<String, String> texts = {
      "about_title": "About FloraGuard",
      "about_desc": "FloraGuard Pro is an AI-powered application designed to identify toxic plants instantly. It helps users ensure safety by analyzing plant images and providing immediate toxicity assessments.",
      "soft_label": "Software Used",
      "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI Model).",
      "hard_label": "Hardware",
      "hard_val": "Developed using high-performance GPUs for training, optimized for mobile.",
      "tech_label": "Key Techniques",
      "tech_val": "Convolutional Neural Networks (CNN), Transfer Learning (MobileNetV2), Real-time API Integration."
    };

    switch (baseCode) {
      case 'es': // Spanish
        texts = {
          "about_title": "Sobre FloraGuard",
          "about_desc": "FloraGuard Pro es una app con IA para identificar plantas tóxicas al instante. Ayuda a garantizar la seguridad analizando imágenes y evaluando toxicidad.",
          "soft_label": "Software Utilizado",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (IA).",
          "hard_label": "Hardware",
          "hard_val": "GPUs de alto rendimiento para entrenamiento, optimizado para móviles.",
          "tech_label": "Técnicas Clave",
          "tech_val": "Redes Neuronales Convolucionales (CNN), Transfer Learning, API en tiempo real."
        };
        break;
      case 'fr': // French
        texts = {
          "about_title": "À propos de FloraGuard",
          "about_desc": "FloraGuard Pro est une application IA pour identifier les plantes toxiques instantanément. Elle analyse les images pour fournir une évaluation immédiate de la toxicité.",
          "soft_label": "Logiciels Utilisés",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (IA).",
          "hard_label": "Matériel",
          "hard_val": "Développé avec des GPU haute performance, optimisé pour mobile.",
          "tech_label": "Techniques Clés",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), API temps réel."
        };
        break;
      case 'de': // German
        texts = {
          "about_title": "Über FloraGuard",
          "about_desc": "FloraGuard Pro ist eine KI-App zur sofortigen Identifizierung giftiger Pflanzen. Sie analysiert Bilder und bietet sofortige Toxizitätsbewertungen.",
          "soft_label": "Software",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (KI).",
          "hard_label": "Hardware",
          "hard_val": "Hochleistungs-GPUs für Training, optimiert für Mobilgeräte.",
          "tech_label": "Schlüsseltechniken",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Echtzeit-API."
        };
        break;
      case 'it': // Italian
        texts = {
          "about_title": "Info su FloraGuard",
          "about_desc": "FloraGuard Pro è un'app basata sull'IA per identificare istantaneamente le piante tossiche. Aiuta a garantire la sicurezza analizzando le immagini.",
          "soft_label": "Software Utilizzato",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (IA).",
          "hard_label": "Hardware",
          "hard_val": "Sviluppato con GPU ad alte prestazioni, ottimizzato per dispositivi mobili.",
          "tech_label": "Tecniche Chiave",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Integrazione API in tempo reale."
        };
        break;
      case 'pt': // Portuguese
        texts = {
          "about_title": "Sobre FloraGuard",
          "about_desc": "FloraGuard Pro é um aplicativo de IA projetado para identificar plantas tóxicas instantaneamente. Ele analisa imagens para fornecer avaliações de segurança.",
          "soft_label": "Software Utilizado",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (IA).",
          "hard_label": "Hardware",
          "hard_val": "Desenvolvido com GPUs de alto desempenho, otimizado para celular.",
          "tech_label": "Técnicas Chave",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), API em tempo real."
        };
        break;
      case 'nl': // Dutch
        texts = {
          "about_title": "Over FloraGuard",
          "about_desc": "FloraGuard Pro is een AI-app om giftige planten direct te identificeren. Het analyseert afbeeldingen voor directe veiligheidsbeoordelingen.",
          "soft_label": "Gebruikte Software",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Hardware",
          "hard_val": "Ontwikkeld met krachtige GPU's, geoptimaliseerd voor mobiel.",
          "tech_label": "Belangrijkste Technieken",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Real-time API."
        };
        break;
      case 'ru': // Russian
        texts = {
          "about_title": "О FloraGuard",
          "about_desc": "FloraGuard Pro - это приложение на базе ИИ для мгновенного определения ядовитых растений. Анализирует изображения для оценки безопасности.",
          "soft_label": "Используемое ПО",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Оборудование",
          "hard_val": "Разработано на мощных GPU, оптимизировано для мобильных устройств.",
          "tech_label": "Ключевые технологии",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), API в реальном времени."
        };
        break;
      case 'zh': // Chinese
        texts = {
          "about_title": "关于 FloraGuard",
          "about_desc": "FloraGuard Pro 是一款 AI 应用程序，旨在立即识别有毒植物。它通过分析图像提供即时安全评估。",
          "soft_label": "使用的软件",
          "soft_val": "Flutter (App), Python Flask (后端), TensorFlow/Keras (AI).",
          "hard_label": "硬件",
          "hard_val": "使用高性能 GPU 开发，针对移动设备进行了优化。",
          "tech_label": "关键技术",
          "tech_val": "CNN, 迁移学习 (MobileNetV2), 实时 API 集成。"
        };
        break;
      case 'ja': // Japanese
        texts = {
          "about_title": "FloraGuard について",
          "about_desc": "FloraGuard Pro は、有毒植物を即座に特定するために設計された AI アプリです。画像を分析し、安全性を評価します。",
          "soft_label": "使用ソフトウェア",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "ハードウェア",
          "hard_val": "高性能 GPU で開発、モバイル向けに最適化。",
          "tech_label": "主要技術",
          "tech_val": "CNN, 転移学習 (MobileNetV2), リアルタイム API 統合。"
        };
        break;
      case 'ko': // Korean
        texts = {
          "about_title": "FloraGuard 소개",
          "about_desc": "FloraGuard Pro는 독성 식물을 즉시 식별하는 AI 앱입니다. 이미지를 분석하여 즉각적인 안전 평가를 제공합니다.",
          "soft_label": "사용된 소프트웨어",
          "soft_val": "Flutter (앱), Python Flask (백엔드), TensorFlow/Keras (AI).",
          "hard_label": "하드웨어",
          "hard_val": "고성능 GPU로 개발, 모바일에 최적화됨.",
          "tech_label": "핵심 기술",
          "tech_val": "CNN, 전이 학습 (MobileNetV2), 실시간 API 통합."
        };
        break;
      case 'hi': // Hindi
        texts = {
          "about_title": "FloraGuard के बारे में",
          "about_desc": "FloraGuard Pro एक AI ऐप है जिसे जहरीले पौधों की तुरंत पहचान करने के लिए डिज़ाइन किया गया है।",
          "soft_label": "सॉफ्टवेयर",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "हार्डवेयर",
          "hard_val": "उच्च प्रदर्शन वाले GPU का उपयोग करके विकसित, मोबाइल के लिए अनुकूलित।",
          "tech_label": "प्रमुख तकनीकें",
          "tech_val": "CNN, ट्रांसफर लर्निंग (MobileNetV2), रीयल-टाइम API।"
        };
        break;
      case 'ar': // Arabic
        texts = {
          "about_title": "حول FloraGuard",
          "about_desc": "FloraGuard Pro هو تطبيق يعمل بالذكاء الاصطناعي لتحديد النباتات السامة على الفور. يحلل الصور لضمان السلامة.",
          "soft_label": "البرمجيات المستخدمة",
          "soft_val": "Flutter (تطبيق), Python Flask (الخلفية), TensorFlow/Keras (AI).",
          "hard_label": "المعدات",
          "hard_val": "تم تطويره باستخدام وحدات معالجة رسومات عالية الأداء.",
          "tech_label": "التقنيات الرئيسية",
          "tech_val": "CNN, التعلم النقلي (MobileNetV2), تكامل API في الوقت الفعلي."
        };
        break;
      case 'tr': // Turkish
        texts = {
          "about_title": "FloraGuard Hakkında",
          "about_desc": "FloraGuard Pro, zehirli bitkileri anında tanımlamak için tasarlanmış yapay zeka destekli bir uygulamadır.",
          "soft_label": "Kullanılan Yazılım",
          "soft_val": "Flutter (Uygulama), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Donanım",
          "hard_val": "Yüksek performanslı GPU'lar ile geliştirildi, mobil için optimize edildi.",
          "tech_label": "Temel Teknikler",
          "tech_val": "CNN, Transfer Öğrenme (MobileNetV2), Gerçek Zamanlı API."
        };
        break;
      case 'id': // Indonesian
        texts = {
          "about_title": "Tentang FloraGuard",
          "about_desc": "FloraGuard Pro adalah aplikasi AI untuk mengidentifikasi tanaman beracun secara instan. Ini menganalisis gambar untuk penilaian keamanan.",
          "soft_label": "Perangkat Lunak",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Perangkat Keras",
          "hard_val": "Dikembangkan menggunakan GPU kinerja tinggi, dioptimalkan untuk seluler.",
          "tech_label": "Teknik Utama",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Integrasi API Real-time."
        };
        break;
      case 'pl': // Polish
        texts = {
          "about_title": "O FloraGuard",
          "about_desc": "FloraGuard Pro to aplikacja AI do natychmiastowej identyfikacji trujących roślin. Analizuje obrazy, zapewniając bezpieczeństwo.",
          "soft_label": "Użyte Oprogramowanie",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Sprzęt",
          "hard_val": "Opracowany na wydajnych GPU, zoptymalizowany pod kątem urządzeń mobilnych.",
          "tech_label": "Kluczowe Techniki",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), API czasu rzeczywistego."
        };
        break;
      case 'vi': // Vietnamese
        texts = {
          "about_title": "Về FloraGuard",
          "about_desc": "FloraGuard Pro là ứng dụng AI giúp nhận diện cây độc ngay lập tức. Phân tích hình ảnh để đánh giá an toàn.",
          "soft_label": "Phần mềm sử dụng",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Phần cứng",
          "hard_val": "Phát triển trên GPU hiệu năng cao, tối ưu cho di động.",
          "tech_label": "Kỹ thuật chính",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Tích hợp API thời gian thực."
        };
        break;
      case 'th': // Thai
        texts = {
          "about_title": "เกี่ยวกับ FloraGuard",
          "about_desc": "FloraGuard Pro เป็นแอป AI ที่ออกแบบมาเพื่อระบุพืชมีพิษทันที วิเคราะห์ภาพเพื่อความปลอดภัย",
          "soft_label": "ซอฟต์แวร์ที่ใช้",
          "soft_val": "Flutter (แอป), Python Flask (Backend), TensorFlow/Keras (AI)",
          "hard_label": "ฮาร์ดแวร์",
          "hard_val": "พัฒนาโดยใช้ GPU ประสิทธิภาพสูง ปรับให้เหมาะสมสำหรับมือถือ",
          "tech_label": "เทคนิคสำคัญ",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Real-time API"
        };
        break;
      case 'ms': // Malay
        texts = {
          "about_title": "Mengenai FloraGuard",
          "about_desc": "FloraGuard Pro adalah aplikasi AI untuk mengenal pasti tumbuhan beracun serta-merta. Ia menganalisis imej untuk keselamatan.",
          "soft_label": "Perisian Digunakan",
          "soft_val": "Flutter (App), Python Flask (Backend), TensorFlow/Keras (AI).",
          "hard_label": "Perkakasan",
          "hard_val": "Dibangunkan menggunakan GPU berprestasi tinggi, dioptimumkan untuk mudah alih.",
          "tech_label": "Teknik Utama",
          "tech_val": "CNN, Transfer Learning (MobileNetV2), Integrasi API Masa Nyata."
        };
        break;
    }
    return texts;
  }
}

// ============================================================================
// 2. MAIN APP WIDGET
// ============================================================================
class ToxicPlantApp extends StatelessWidget {
  const ToxicPlantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 🟢 FIX: This enables mouse dragging for the information tab on Desktop
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      debugShowCheckedModeBanner: false,
      title: 'FloraGuard Pro',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto', 
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const ProHomePage(),
    );
  }
}

// ============================================================================
// 3. HOME SCREEN
// ============================================================================
class ProHomePage extends StatefulWidget {
  const ProHomePage({super.key});

  @override
  State<ProHomePage> createState() => _ProHomePageState();
}

class _ProHomePageState extends State<ProHomePage> {
  File? _image;
  Map<String, dynamic>? _result;
  bool _loading = false;
  final ImagePicker _picker = ImagePicker();
  
  // 🔔 AUDIO PLAYER INSTANCE
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _getImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 224,
      maxHeight: 224,
      imageQuality: 90,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = null; 
      });
      _uploadImage(_image!);
    }
  }

  // 🔔 HELPER TO PLAY SOUND
  Future<void> _playSound(bool isToxic) async {
    try {
      await _audioPlayer.stop(); // Stop previous sound
      
      // Select file from assets
      String fileToPlay = isToxic ? 'toxic.wav' : 'non_toxic.wav';
      
      print("🔊 App Playing: $fileToPlay");
      await _audioPlayer.play(AssetSource(fileToPlay));
      
    } catch (e) {
      print("❌ Audio Playback Error: $e");
    }
  }

  Future<void> _uploadImage(File image) async {
    setState(() => _loading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$SERVER_URL/predict"));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      
      // Send user's selected language to server
      var lang = Provider.of<LanguageProvider>(context, listen: false);
      request.fields['lang'] = lang.currentLocale.languageCode;

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw Exception("Server Timeout. Try again.");
        },
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Decode response properly with UTF-8 support
        var data = json.decode(utf8.decode(response.bodyBytes));
        setState(() => _result = data);
        
        // 🔔 TRIGGER AUDIO
        bool isToxic = data['is_toxic'] == true;
        _playSound(isToxic);

      } else {
        // 🛑 HANDLE ERRORS
        try {
          var errorData = json.decode(response.body);
          if (errorData.containsKey('error')) {
            _showSnack(errorData['error']); 
          } else {
            _showSnack("Server Error: ${response.statusCode}");
          }
        } catch (_) {
          _showSnack("Server Error: ${response.statusCode}");
        }
      }
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg), 
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent, 
        )
    );
  }
  
  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    bool isToxic = _result?['is_toxic'] == true;
    Color statusColor = isToxic ? Colors.redAccent : Colors.green;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. BACKGROUND IMAGE
          _image == null
              ? _buildPlaceholder(lang)
              : Image.file(_image!, fit: BoxFit.cover),

          // 2. GRADIENT
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),

          // 3. LOADING INDICATOR
          if (_loading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 10),
                  Text(lang.getText('loading'), style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),

          // 4. TOP RIGHT BUTTONS (SETTINGS & ABOUT)
          Positioned(
            top: 50,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ℹ️ ABOUT ICON
                _buildGlassIconButton(
                  Icons.info_outline, 
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AboutScreen()),
                    );
                  }
                ),
                const SizedBox(width: 15),
                // ⚙️ SETTINGS ICON
                _buildGlassIconButton(
                  Icons.settings, 
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LanguageScreen()),
                    );
                  }
                ),
              ],
            ),
          ),

          // 5. CAMERA BUTTONS
          Positioned(
            top: 110, 
            right: 20,
            child: Column(
              children: [
                _buildGlassIconButton(Icons.camera_alt, () => _getImage(ImageSource.camera)),
                const SizedBox(height: 15),
                _buildGlassIconButton(Icons.photo_library, () => _getImage(ImageSource.gallery)),
              ],
            ),
          ),

          // 6. APP TITLE
          if (_result == null)
             Positioned(
              top: 60,
              left: 20,
              child: Text(
                lang.getText('app_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),

          // 7. RESULTS SHEET
          if (_result != null && !_loading)
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.25,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, -5))
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    // 🟢 FIX: Ensures dragging works on Desktop with mouse
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Plant Name
                      Text(
                        _result!['common_name'] ?? lang.getText('unknown'),
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _result!['scientific_name'] ?? "",
                        style: TextStyle(
                            fontSize: 18, fontStyle: FontStyle.italic, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 20),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: statusColor.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                isToxic ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                                color: statusColor, size: 30),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isToxic ? lang.getText('toxic') : lang.getText('safe'),
                                    style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  // CONFIDENCE
                                  Text(
                                    "${lang.getText('confidence')}: ${(_result!['confidence'] * 100).toStringAsFixed(1)}%",
                                    style: TextStyle(
                                        color: statusColor.withOpacity(0.8), fontSize: 12),
                                  ),
                                  // 🔔 SOURCE DISPLAY
                                  if (_result!.containsKey('source'))
                                    Text(
                                      "${lang.getText('source_label')}: ${_result!['source']}",
                                      style: TextStyle(
                                          color: Colors.grey[600], fontSize: 10, fontStyle: FontStyle.italic),
                                    ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Info Sections
                      _buildInfoSection(lang.getText('symptoms'), _result!['symptoms']),
                      const Divider(height: 40),
                      _buildInfoSection(lang.getText('action'), _result!['poisoning_action']),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(LanguageProvider lang) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF000000)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.energy_savings_leaf_outlined,
              size: 100, color: Colors.white.withOpacity(0.5)),
          const SizedBox(height: 20),
          Text(
            lang.getText('scan_plant'),
            style: const TextStyle(color: Colors.white54, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton(IconData icon, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.white.withOpacity(0.2),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            iconSize: 30,
            padding: const EdgeInsets.all(12),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, String? content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Text(content ?? "No information available.",
            style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87)),
      ],
    );
  }
}

// ============================================================================
// 4. LANGUAGE SETTINGS SCREEN
// ============================================================================
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getText('settings')),
        backgroundColor: Colors.white,
      ),
      body: lang.availableLanguages.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("No languages found or connection failed.", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Trigger refresh manually
                      lang.fetchAvailableLanguages();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry Connection"),
                  )
                ],
              ),
            ) 
          : ListView.builder(
              itemCount: lang.availableLanguages.length,
              itemBuilder: (context, index) {
                final item = lang.availableLanguages[index];
                final code = item['code'];
                final name = item['name'];
                final native = item['nativeName'];
                
                final isInstalled = lang.installedLanguages.contains(code);
                final isActive = lang.currentLocale.languageCode == code;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? Colors.green : Colors.grey[200],
                    child: Text(code.toUpperCase(), 
                      style: TextStyle(color: isActive ? Colors.white : Colors.black)
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(native),
                  trailing: isActive
                      ? Chip(label: Text(lang.getText('active')), backgroundColor: Colors.greenAccent)
                      : isInstalled
                          ? ElevatedButton(
                              onPressed: () => lang.switchLanguage(code),
                              child: Text(lang.getText('switch')),
                            )
                          : IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => lang.downloadLanguage(code),
                            ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// 5. 🆕 ABOUT SCREEN
// ============================================================================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getText('about_title')),
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Image or Icon
            Center(
              child: Icon(Icons.energy_savings_leaf, size: 80, color: Colors.green[700]),
            ),
            const SizedBox(height: 20),
            
            // Description
            Text(
              lang.getText('about_desc'),
              style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 30),

            _buildDetailRow(Icons.code, lang.getText('soft_label'), lang.getText('soft_val')),
            _buildDetailRow(Icons.memory, lang.getText('hard_label'), lang.getText('hard_val')),
            _buildDetailRow(Icons.psychology, lang.getText('tech_label'), lang.getText('tech_val')),
            
            const SizedBox(height: 30),
            Center(
              child: Text(
                "v1.0.0",
                style: TextStyle(color: Colors.grey[500]),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green, size: 28),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(fontSize: 15, color: Colors.grey[800]),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}