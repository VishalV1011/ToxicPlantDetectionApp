import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ToxicPlantApp());
}

class ToxicPlantApp extends StatelessWidget {
  const ToxicPlantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FloraGuard Pro',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto', // Or your preferred font
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const ProHomePage(),
    );
  }
}

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

  // ✅ CORRECT: Base URL + /predict
  final String apiUrl = "https://toxicplantdetectionapp.onrender.com/predict";

  Future<void> _getImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = null; // Clear previous results
      });
      _uploadImage(_image!);
    }
  }

  // ⚠️ UPDATED FUNCTION: Increases wait time to 90 seconds
  Future<void> _uploadImage(File image) async {
    setState(() => _loading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      // NEW: Explicit 90-second timeout to handle cold starts
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw Exception("Server sleeping. Please try again (Timeout).");
        },
      );
      
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() => _result = json.decode(response.body));
      } else {
        _showSnack("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      // Shows the actual error (like Timeout) instead of generic "Check IP"
      _showSnack("Error: ${e.toString()}");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    // Determine status color based on toxicity
    bool isToxic = _result?['is_toxic'] == true;
    Color statusColor = isToxic ? Colors.redAccent : Colors.green;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. BACKGROUND IMAGE LAYER
          _image == null
              ? _buildPlaceholder()
              : Image.file(_image!, fit: BoxFit.cover),

          // 2. GRADIENT OVERLAY (For text readability)
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
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // 4. FLOATING BUTTONS (Top Right)
          Positioned(
            top: 50,
            right: 20,
            child: Column(
              children: [
                _buildGlassIconButton(Icons.camera_alt, () => _getImage(ImageSource.camera)),
                const SizedBox(height: 15),
                _buildGlassIconButton(Icons.photo_library, () => _getImage(ImageSource.gallery)),
              ],
            ),
          ),

          // 5. APP TITLE (Top Left)
          if (_result == null)
            const Positioned(
              top: 60,
              left: 20,
              child: Text(
                "FloraGuard",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),

          // 6. BOTTOM SHEET (RESULTS)
          if (_result != null && !_loading)
            DraggableScrollableSheet(
              initialChildSize: 0.4,
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
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Handle Bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Plant Name
                      Text(
                        _result!['common_name'] ?? "Unknown",
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _result!['scientific_name'] ?? "",
                        style: TextStyle(
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600]),
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
                                isToxic
                                    ? Icons.warning_amber_rounded
                                    : Icons.verified_user_rounded,
                                color: statusColor,
                                size: 30),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isToxic ? "TOXIC PLANT" : "LIKELY SAFE",
                                    style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    "Confidence: ${(_result!['confidence'] * 100).toStringAsFixed(1)}%",
                                    style: TextStyle(
                                        color: statusColor.withOpacity(0.8),
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Info Sections
                      _buildInfoSection("Symptoms", _result!['symptoms']),
                      const Divider(height: 40),
                      _buildInfoSection("First Aid / Action", _result!['poisoning_action']),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
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
          const Text(
            "Scan a Plant",
            style: TextStyle(color: Colors.white54, fontSize: 18),
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