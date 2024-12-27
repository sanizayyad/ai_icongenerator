import 'dart:io';
import 'dart:typed_data';
import 'package:ai_icongenerator/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const IconGeneratorApp());

class IconGeneratorApp extends StatelessWidget {
  const IconGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Icon Generator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const IconGeneratorScreen(),
    );
  }
}

class IconGeneratorScreen extends StatefulWidget {
  const IconGeneratorScreen({super.key});

  @override
  _IconGeneratorScreenState createState() => _IconGeneratorScreenState();
}

class _IconGeneratorScreenState extends State<IconGeneratorScreen> {
  final TextEditingController _themeController = TextEditingController();
  String? theme;
  final ImagePicker _picker = ImagePicker();
  File? uploadedScreenshot;
  List<String> appNames = [];
  Map<String, Uint8List> generatedIcons = {};
  bool isLoading = false;
  int currentAppIndex = 0;
  int currentStep = 0;

  @override
  void initState() {
    _themeController.addListener(() {
      theme = _themeController.text;
    });
    super.initState();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> pickScreenshot() async {
    debugPrint("Picking a screenshot...");
    try {
      final XFile? pickedFile =
      await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          uploadedScreenshot = File(pickedFile.path);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screenshot uploaded successfully!')),
        );
        await extractAppNamesFromScreenshot(uploadedScreenshot!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> extractAppNamesFromScreenshot(File image) async {
    debugPrint("Starting app name extraction...");
    setState(() {
      isLoading = true;
    });

    try {
      final names = await AIService().extractAppNames(image);
      debugPrint("Successfully extracted app names: $names");
      setState(() {
        appNames = names;
        isLoading = true;
      });
    } catch (error) {
      debugPrint("Failed to extract app names: $error");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void startIconGeneration() async{
    debugPrint("Generating...");
    setState(() {
      isLoading = true;
    });
    currentAppIndex = 0;
    await generateNextIcon();
    setState(() {
      isLoading = false;
    });
  }

  Future<void> generateNextIcon() async {
    if (currentAppIndex >= appNames.length) {
      return;
    }

    final appName = appNames[currentAppIndex];
    try {
      final result = await AIService().generateIcon(appName, theme!);
      setState(() {
        generatedIcons[appName] = result.image!;
        currentAppIndex++;
      });
      generateNextIcon();
    } catch (error) {
      if (error == AIServiceError.rateLimitExceeded) {
        Future.delayed(const Duration(seconds: 12), generateNextIcon);
      } else if(error is AIServiceError){
        handleError(error);
      }else{
        print(error);
      }
    }
  }

  void handleError(AIServiceError error) {
    String detailedErrorMessage;
    switch (error) {
      case AIServiceError.networkError:
        detailedErrorMessage = "Network error: ${error.toString()}";
        break;
      case AIServiceError.noData:
        detailedErrorMessage = "No data received from the server.";
        break;
      case AIServiceError.decodingError:
        detailedErrorMessage = "Error decoding response: ${error.toString()}";
        break;
      case AIServiceError.apiError:
        detailedErrorMessage = "API error: ${error.toString()}";
        break;
      case AIServiceError.unknownError:
        detailedErrorMessage = "An unknown error occurred.";
        break;
      case AIServiceError.imageDownloadError:
        detailedErrorMessage = "Error downloading generated images.";
        break;
      case AIServiceError.rateLimitExceeded:
        detailedErrorMessage = "Rate limit exceeded. Please try again later.";
        break;
    }
    debugPrint("Error occurred: $detailedErrorMessage");
  }

  Future<void> saveIconsLocally() async {
    debugPrint("Saving icons...");
    if (await Permission.storage.request().isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied!')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${appDir.path}/GeneratedIcons');
      if (!saveDir.existsSync()) {
        saveDir.createSync();
      }

      for (var entry in generatedIcons.entries) {
        final appName = entry.key;
        final iconData = entry.value;
        final filePath = '${saveDir.path}/$appName.png';
        final file = File(filePath);
        await file.writeAsBytes(iconData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Icons saved to ${saveDir.path}')),
      );
      debugPrint("Icons saved successfully...");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving icons: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Icon Generator')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const Text(
                    'Upload Screenshot',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: pickScreenshot,
                    icon: const Icon(Icons.image),
                    label: const Text('Select Screenshot'),
                  ),
                  const SizedBox(height: 16),
                  uploadedScreenshot != null
                      ? Image.file(
                    uploadedScreenshot!,
                    height: 150,
                    fit: BoxFit.cover,
                  )
                      : const Text('No screenshot uploaded yet'),
                  const SizedBox(height: 16),
                  appNames.isNotEmpty && (theme?.isNotEmpty ?? false)
                      ? Column(
                    children: [
                      const Text('Extracted App Names:'),
                      ...appNames.map((name) => Text(name)).toList(),
                    ],
                  )
                      : const Text('No app names extracted yet'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _themeController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Theme',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: appNames.isNotEmpty ? startIconGeneration : null,
                    icon: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(Icons.auto_awesome),
                    label: const Text('Generate Icons'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: generatedIcons.isEmpty ? null : saveIconsLocally,
                    icon: const Icon(Icons.save),
                    label: const Text('Save All'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 400, // Adjust the height as needed
                    child: GridView.builder(
                      itemCount: generatedIcons.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                      ),
                      itemBuilder: (context, index) {
                        final iconData = generatedIcons.values.elementAt(index);
                        return Image.memory(
                          iconData,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
