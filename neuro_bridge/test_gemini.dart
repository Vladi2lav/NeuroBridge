import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = 'AIzaSyBcmu3iji8exJPuOBgpqJMcldDPMUW7310';
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-native-audio-preview-12-2025:generateContent?key=$apiKey');
  
  Map<String, dynamic> requestBody = {
    "contents": [{"role": "user", "parts": [{"text": "Привет! Скажи 'тест'."}]}],
    "generationConfig": {
       "responseModalities": ["AUDIO"]
    }
  };

  final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody)
  );

  print('Status: ${response.statusCode}');
  if (response.statusCode == 200) {
     final json = jsonDecode(response.body);
     final parts = json['candidates'][0]['content']['parts'] as List;
     print('Parts size: ${parts.length}');
     for (var p in parts) {
       print(p.keys);
       if (p.containsKey('text')) {
          print('Text: ${p['text']}');
       }
     }
  } else {
     print(response.body);
  }
}
