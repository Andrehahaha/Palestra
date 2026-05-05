import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const _orange = Color(0xFFFF6B1A);
  static const _red    = Color(0xFFCC1A1A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.trim(),
          password: _password.trim(),
        );
      } else {
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.trim(),
          password: _password.trim(),
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': _email.trim(),
          'ruolo': 'atleta',
          'nome': 'Nuovo Utente',
          'dataCreazione': FieldValue.serverTimestamp(),
          'coachId': '',
        });
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Si è verificato un errore.';
      if (e.code == 'user-not-found')      msg = 'Nessun utente trovato con questa email.';
      else if (e.code == 'wrong-password') msg = 'Password errata.';
      else if (e.code == 'email-already-in-use') msg = 'Email già registrata.';
      if (mounted) _showError(msg);
    } catch (e) {
      if (mounted) _showError('Errore: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _toggleMode() {
    _animController.reset();
    setState(() => _isLogin = !_isLogin);
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Glow decorativo in alto
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _red.withValues(alpha: 0.18),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _orange.withValues(alpha: 0.14),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      // Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_red, _orange],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _orange.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.bolt_rounded, size: 44, color: Colors.white),
                      ),
                      const SizedBox(height: 20),

                      // Titolo
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [_orange, _red],
                        ).createShader(b),
                        child: const Text(
                          'TIGER',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isLogin ? 'Bentornato atleta' : 'Inizia il tuo percorso',
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Form card
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_isLogin) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _orange.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _orange.withValues(alpha: 0.2)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Color(0xFFFF6B1A), size: 16),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Registrazione crea un account atleta. I coach vengono abilitati dall\'amministratore.',
                                          style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              _buildLabel('EMAIL'),
                              const SizedBox(height: 8),
                              TextFormField(
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.emailAddress,
                                decoration: _inputDecoration(
                                  hint: 'tuaemail@esempio.com',
                                  icon: Icons.mail_outline_rounded,
                                ),
                                validator: (v) => v!.isEmpty || !v.contains('@') ? 'Email non valida' : null,
                                onSaved: (v) => _email = v!,
                              ),
                              const SizedBox(height: 20),

                              _buildLabel('PASSWORD'),
                              const SizedBox(height: 8),
                              TextFormField(
                                style: const TextStyle(color: Colors.white),
                                obscureText: _obscurePassword,
                                decoration: _inputDecoration(
                                  hint: '••••••••',
                                  icon: Icons.lock_outline_rounded,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: const Color(0xFF666666),
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) => v!.length < 6 ? 'Minimo 6 caratteri' : null,
                                onSaved: (v) => _password = v!,
                              ),
                              const SizedBox(height: 28),

                              // CTA Button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: _isLoading
                                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B1A), strokeWidth: 2.5))
                                    : DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [_red, _orange],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _orange.withValues(alpha: 0.3),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _submit,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: Text(
                                            _isLogin ? 'ACCEDI' : 'REGISTRATI',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                              letterSpacing: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _toggleMode,
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14),
                            children: [
                              TextSpan(
                                text: _isLogin ? 'Non hai un account? ' : 'Hai già un account? ',
                                style: const TextStyle(color: Color(0xFF666666)),
                              ),
                              TextSpan(
                                text: _isLogin ? 'Registrati' : 'Accedi',
                                style: const TextStyle(
                                  color: _orange,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF666666),
        letterSpacing: 1.5,
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF444444)),
      prefixIcon: Icon(icon, color: const Color(0xFF555555), size: 20),
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF6B1A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCC1A1A)),
      ),
    );
  }
}
