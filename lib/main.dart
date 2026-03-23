import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';

// 👇 Import delle tue nuove schermate belle in ordine!
import 'screens/login_screen.dart';
import 'screens/coach_dashboard.dart';
import 'screens/home_screen.dart';
import 'screens/workouts_screen.dart';
import 'screens/profilo_screen.dart';
import 'screens/dolore_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔐 Apri la cassaforte PRIMA di chiamare Firebase
  await dotenv.load(fileName: ".env");

  // 🔥 Ora Firebase parte e va a leggere le chiavi in modo sicuro
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepOrange,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  @override
  Widget build(BuildContext context) {
    // IL SEGRETO PER AGGIORNARE TUTTO ISTANTANEAMENTE QUANDO CAMBI SCHERMATA
    final List<Widget> screens = [
      HomeScreen(key: UniqueKey()),
      WorkoutsScreen(key: UniqueKey()),
      DoloreScreen(key: UniqueKey()),
      ProfiloScreen(key: UniqueKey()),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
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
