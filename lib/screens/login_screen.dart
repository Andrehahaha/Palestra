import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLogin = true; // true = Login, false = Registrazione
  bool _isLoading = false;
  
  // Ruolo predefinito per i nuovi registrati
  String _ruoloScelto = 'atleta'; 

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    _formKey.currentState!.save();
    
    setState(() { _isLoading = true; });

    try {
      if (_isLogin) {
        // --- LOGICA DI LOGIN ---
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.trim(),
          password: _password.trim(),
        );
        // NOTA: Non serve usare Navigator.push() qui! 
        // Il "Vigile Urbano" (AuthWrapper) nel main.dart se ne accorgerà da solo e cambierà schermata!
      } else {
        // --- LOGICA DI REGISTRAZIONE ---
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.trim(),
          password: _password.trim(),
        );

        // Salviamo il ruolo e il profilo sul database Firestore
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'email': _email.trim(),
          'ruolo': _ruoloScelto,
          'nome': 'Nuovo Utente',
          'dataCreazione': FieldValue.serverTimestamp(),
          'coachId': _ruoloScelto == 'atleta' ? '' : null, // Se è atleta, inizialmente non ha un coach
        });
      }
    } on FirebaseAuthException catch (e) {
      String messaggioErrore = 'Si è verificato un errore.';
      if (e.code == 'user-not-found') {
        messaggioErrore = 'Nessun utente trovato con questa email.';
      } else if (e.code == 'wrong-password') {
        messaggioErrore = 'Password errata.';
      } else if (e.code == 'email-already-in-use') {
        messaggioErrore = 'Questa email è già registrata.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(messaggioErrore), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo o Icona
              const Icon(Icons.fitness_center, size: 80, color: Colors.deepOrange),
              const SizedBox(height: 16),
              const Text('Tiger', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text(_isLogin ? 'Bentornato! Accedi al tuo account.' : 'Crea un nuovo account.', 
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 32),

              // Form
              Card(
                elevation: 4,
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Se è in modalità Registrazione, mostra la scelta del ruolo
                        if (!_isLogin) ...[
                          const Text('Scegli il tuo ruolo:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Atleta 🏃‍♂️', style: TextStyle(fontSize: 14)),
                                  value: 'atleta',
                                  groupValue: _ruoloScelto,
                                  activeColor: Colors.deepOrange,
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (val) { setState(() { _ruoloScelto = val!; }); },
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Coach 🏋️‍♂️', style: TextStyle(fontSize: 14)),
                                  value: 'coach',
                                  groupValue: _ruoloScelto,
                                  activeColor: Colors.deepOrange,
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (val) { setState(() { _ruoloScelto = val!; }); },
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.grey),
                          const SizedBox(height: 8),
                        ],

                        TextFormField(
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) => value!.isEmpty || !value.contains('@') ? 'Inserisci un\'email valida' : null,
                          onSaved: (value) => _email = value!,
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                          obscureText: true,
                          validator: (value) => value!.length < 6 ? 'La password deve avere almeno 6 caratteri' : null,
                          onSaved: (value) => _password = value!,
                        ),
                        const SizedBox(height: 24),

                        _isLoading
                          ? const CircularProgressIndicator(color: Colors.deepOrange)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _submit,
                              child: Text(_isLogin ? 'ACCEDI' : 'REGISTRATI', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              
              // Pulsante per cambiare tra Login e Registrazione
              TextButton(
                onPressed: () {
                  setState(() { _isLogin = !_isLogin; });
                },
                child: Text(
                  _isLogin ? 'Non hai un account? Registrati' : 'Hai già un account? Accedi',
                  style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}