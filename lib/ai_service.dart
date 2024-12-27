import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

enum AIServiceError {
  networkError,
  noData,
  decodingError,
  apiError,
  unknownError,
  imageDownloadError,
  rateLimitExceeded,
}

class IconGenerationResult {
  final Uint8List? image;
  final AIServiceError? error;

  IconGenerationResult.success(this.image) : error = null;
  IconGenerationResult.failure(this.error) : image = null;
}


const baseURL = 'https://api.openai.com/v1/';
const apiKey = '';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();


  final Duration minimumRequestInterval = const Duration(seconds: 12);
  DateTime lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  final Dio _dio = Dio();
  final headers = {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  Future<Uint8List> _resizeImage(File imageFile, int width, int height) async {
    final image = img.decodeImage(await imageFile.readAsBytes());
    final resizedImage = img.copyResize(image!, width: width, height: height);
    return Uint8List.fromList(img.encodeJpg(resizedImage));
  }

  Future<List<String>> extractAppNames(File image) async {
    const endpoint = '${baseURL}chat/completions';

    final optimizedImage = await _resizeImage(image, 800, 800);
    final base64String = base64Encode(optimizedImage);
    final messages = [
      {
        'role': 'system',
        'content': 'You are an AI assistant that extracts app names from home screen images.'
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'Please list all the app names you can see in these home screen images. Provide the names in a comma-separated list, without any additional text or explanation.'
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$base64String'}
          }
        ]
      }
    ];

    final body = jsonEncode({
      'model': 'gpt-4-turbo',
      'messages': messages,
      'max_tokens': 300,
    });

    try {
      final response = await _dio.post(endpoint, options: Options(headers: headers), data: body);

      if (response.statusCode != 200) {
        throw AIServiceError.apiError;
      }

      final jsonResult = response.data;
      if (jsonResult['error'] != null) {
        throw AIServiceError.apiError;
      }

      final choices = jsonResult['choices'] as List;
      final content = choices.first['message']['content'] as String;
      final appNames = content.split(',').map((e) => e.trim()).toList();

      return appNames;
    } catch (e) {
      throw AIServiceError.networkError;
    }
  }

  Future<IconGenerationResult> generateIcon(String appName, String theme) async {
    final currentTime = DateTime.now();
    final timeIntervalSinceLastRequest = currentTime.difference(lastRequestTime);

    if (timeIntervalSinceLastRequest < minimumRequestInterval) {
      await Future.delayed(minimumRequestInterval - timeIntervalSinceLastRequest);
    }

    lastRequestTime = DateTime.now();
    return await _generateSingleIcon(appName, theme);
  }

  Future<IconGenerationResult> _generateSingleIcon(String appName, String theme) async {
    const endpoint = '${baseURL}images/generations';

    final prompt = "Create a $theme style app icon for '$appName'. The icon should be simple, clear, and suitable for an iOS app. Do not include any text in the icon.";
    final body = {
      'model': 'dall-e-3',
      'prompt': prompt,
      'n': 1,
      'size': '1024x1024',
      'quality': 'standard',
    };

    try {
      final response = await _dio.post(
        endpoint,
        options: Options(headers: headers),
        data: jsonEncode(body),
      );

      lastRequestTime = DateTime.now();

      if (response.statusCode != 200) {
        throw AIServiceError.apiError;
      }

      final json = response.data;
      if (json['error'] != null) {
          throw AIServiceError.apiError;
      }

      final imageData = json['data'] as List;
      if (imageData.isNotEmpty) {
        final imageURLString = imageData.first['url'];
        final imageURL = Uri.parse(imageURLString);
        final imageResult = await _downloadImage(imageURL);
         return IconGenerationResult.success(imageResult);
      } else {
        throw AIServiceError.apiError;
      }
    } catch (e) {
      throw AIServiceError.networkError;
    }
  }


  Future<Uint8List> _downloadImage(Uri url) async {
    try {
      final response = await _dio.get(url.toString(), options: Options(responseType: ResponseType.bytes));
      if (response.statusCode != 200) {
        throw AIServiceError.imageDownloadError;
      }
      return response.data;
    } catch (e) {
      throw AIServiceError.networkError;
    }
  }
}

