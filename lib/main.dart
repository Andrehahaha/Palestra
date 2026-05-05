import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// 👇 Import delle tue nuove schermate belle in ordine!
import 'screens/auth/login_screen.dart';
import 'screens/coach/coach_dashboard.dart';
import 'screens/home/home_screen.dart';
import 'screens/training/workouts_screen.dart';
import 'screens/profile/profilo_screen.dart';
import 'screens/wellness/dolore_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Delete the corrupt Firestore SQLite directory BEFORE Firebase initializes.
  // getApplicationSupportDirectory() on Android returns {filesDir}/flutter/ — Firestore
  // lives one level up at {filesDir}/firestore/, so we check both paths.
  final prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('firestore_db_deleted_v2')) {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      for (final base in [appSupportDir.path, appSupportDir.parent.path]) {
        final firestoreDir = Directory('$base/firestore');
        if (await firestoreDir.exists()) {
          await firestoreDir.delete(recursive: true);
        }
      }
      await prefs.setBool('firestore_db_deleted_v2', true);
    } catch (e) {
      debugPrint('Pulizia Firestore locale fallita: $e');
    }
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Disable local SQLite persistence permanently to prevent future accumulation.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const tigerOrange = Color(0xFFFF6B1A);
    const tigerRed    = Color(0xFFCC1A1A);
    const tigerAmber  = Color(0xFFFFB347);
    const appBg       = Color(0xFF0A0A0A);
    const appSurface  = Color(0xFF141414);
    const appSurfaceAlt = Color(0xFF1E1E1E);

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: tigerOrange,
      onPrimary: Colors.white,
      secondary: tigerRed,
      onSecondary: Colors.white,
      tertiary: tigerAmber,
      onTertiary: Colors.black,
      error: const Color(0xFFCF6679),
      onError: Colors.black,
      surface: appSurface,
      onSurface: Colors.white,
      surfaceContainerHighest: appSurfaceAlt,
      onSurfaceVariant: const Color(0xFFAAAAAA),
      outline: const Color(0xFF333333),
    );

    return MaterialApp(
      title: 'Tiger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: appBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: appBg,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: appSurface,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: appSurfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: tigerOrange, width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          hintStyle: const TextStyle(color: Color(0xFF666666)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: tigerOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.08),
          space: 1,
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: appSurfaceAlt,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: appSurfaceAlt,
          selectedColor: tigerOrange.withValues(alpha: 0.22),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        textTheme: const TextTheme(
          titleLarge:  TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          titleSmall:  TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFAAAAAA)),
          bodyLarge:   TextStyle(height: 1.4),
          bodyMedium:  TextStyle(height: 1.4, color: Color(0xFFDDDDDD)),
          bodySmall:   TextStyle(color: Color(0xFF888888)),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
          );
        }
        if (snapshot.hasData) {
          return const RoleController();
        }
        return const LoginScreen();
      },
    );
  }
}

class RoleController extends StatelessWidget {
  const RoleController({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.deepOrange)));
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Errore: Profilo non trovato nel database.', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                    icon: const Icon(Icons.logout),
                    label: const Text('Esci e riprova'),
                    onPressed: () async { await FirebaseAuth.instance.signOut(); },
                  )
                ],
              ),
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final String ruolo = userData['ruolo'] ?? 'atleta';

        if (ruolo == 'coach') {
          return const CoachDashboardScreen(); 
        } else {
          return const MainNavigationScreen(); 
        }
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final List<Widget> screens;

  @override
  void initState() {
    super.initState();
    screens = const [
      HomeScreen(),
      WorkoutsScreen(),
      DoloreScreen(),
      ProfiloScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const navBg = Color(0xFF121822);
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFFFF8A3D),
        unselectedItemColor: Colors.white70,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        backgroundColor: navBg,
        onTap: (index) { setState(() { _currentIndex = index; }); },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Allenamenti'),
          BottomNavigationBarItem(icon: Icon(Icons.healing), label: 'Dolori'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profilo'),
        ],
      ),
    );
  }
}
