import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tour/services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _isSuccess = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _isSuccess = false;
        _statusMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _statusMessage = null;
      _isSubmitting = true;
    });

    try {
      // 1. Create the account (Firebase auto-signs them in here)
      try {
        await Provider.of<AuthService>(context, listen: false).signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // If already exists, we still try to send verification below
        } else {
          rethrow;
        }
      }

      // 2. Send Verification Email
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (e) {
          debugPrint("Rate limit on email: $e");
        }

        // 3. CRITICAL: Sign Out immediately!
        // This prevents the user from being redirected to the Home page ('/')
        await FirebaseAuth.instance.signOut();
      }

      // 4. Update UI and Redirect to Login
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _statusMessage = 'Account created! Please verify your email before logging in.';
        });

        // Give them 3 seconds to read the message
        await Future.delayed(const Duration(seconds: 3));
        
        if (mounted) {
          // Redirect to Login, NOT the Home page
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSuccess = false;
          _statusMessage = e.toString().replaceAll('Exception:', '');
          _isSubmitting = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    // Determine screen width for responsiveness
    double screenWidth = MediaQuery.of(context).size.width;
    bool isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center( // Centers the form on tablets
        child: Container(
          // Constrains width on tablets to 500px, full width on phones
          constraints: BoxConstraints(maxWidth: isTablet ? 500 : double.infinity),
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create Account",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const Text("Join the journey with us", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 30),

                  if (_statusMessage != null)
                    _buildStatusBanner(),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildTextField(_nameController, "Full Name", Icons.person_outline),
                        const SizedBox(height: 15),
                        _buildTextField(_emailController, "Email", Icons.email_outlined),
                        const SizedBox(height: 15),
                        _buildTextField(_passwordController, "Password", Icons.lock_outline, obscure: _obscurePassword),
                        const SizedBox(height: 15),
                        _buildTextField(_confirmPasswordController, "Confirm Password", Icons.lock_reset, obscure: _obscurePassword),
                        const SizedBox(height: 30),
                        
                        _buildSignUpButton(),
                        
                        const SizedBox(height: 20),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OR")),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildGoogleButton(),
                        const SizedBox(height: 20),
                        _buildLoginRedirect(),
                      ],
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

  // --- UI Helper Widgets ---

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _isSuccess ? Colors.black : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusMessage!,
        style: TextStyle(color: _isSuccess ? Colors.white : Colors.red.shade800),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool obscure = false}) {
    return TextFormField(
      controller: controller,
      enabled: !_isSubmitting,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.black54),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (val) => (val == null || val.isEmpty) ? "Required" : null,
    );
  }

  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _register,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("Sign Up", style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: OutlinedButton.icon(
        onPressed: _isSubmitting ? null : () => Provider.of<AuthService>(context, listen: false).signInWithGoogle(),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 30),
        label: const Text("Sign up with Google", style: TextStyle(color: Colors.black)),
      ),
    );
  }

  Widget _buildLoginRedirect() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Already have an account?"),
        TextButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          child: const Text("Login", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}