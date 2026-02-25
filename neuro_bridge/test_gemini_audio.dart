import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-native-audio-preview-12-2025:generateContent?key=AIzaSyBcmu3iji8exJPuOBgpqJMcldDPMUW7310');
  
  final requestBody = {
    "contents": [
      {
        "role": "user",
        "parts": [{"text": "Hello, my name is Danil"}]
      }
    ],
    "generationConfig": {
      "responseModalities": ["AUDIO"]
    }
  };

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(requestBody)
  );

  if (response.statusCode == 200) {
    try {
      final json = jsonDecode(response.body);
      final parts = json['candidates'][0]['content']['parts'];
      for (var part in parts) {
        if (part.containsKey('inlineData')) {
          print("mimeType: ${part['inlineData']['mimeType']}");
          print("data length: ${part['inlineData']['data'].length}");
        } else if (part.containsKey('text')) {
          print("Text part: ${part['text']}");
        }
      }
    } catch (e) {
      print("Error parsing response: $e \n${response.body}");
    }
  } else {
    print("API Error: ${response.statusCode} - ${response.body}");
  }
}
