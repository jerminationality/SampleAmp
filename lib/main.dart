import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/main_sampler_screen.dart';
import 'providers/audio_provider.dart';
import 'providers/sample_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Skip audio session configuration for web
  // Audio session is not supported in web browsers
  
  runApp(const LiveAudioSamplerApp());
}

class LiveAudioSamplerApp extends StatelessWidget {
  const LiveAudioSamplerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioProvider()),
        ChangeNotifierProvider(create: (_) => SampleProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Live Audio Sampler',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: Colors.blue,
            secondary: Colors.orange,
            surface: const Color(0xFF1E1E1E),
            background: const Color(0xFF121212),
          ),
        ),
        home: const MainSamplerScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
} 