import 'dart:async'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tour/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _isSuccess = false;
  bool _isSubmitting = false;
  
  Timer? _statusTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  // --- LOGIC SECTION ---

  void _handleNavigation() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    });
  }

  void _showStatus(String message, {bool isSuccess = false}) {
    _statusTimer?.cancel();
    
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _isSuccess = isSuccess;
        _isSubmitting = false; 
      });
    }

    _statusTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _statusMessage = null;
      _isSubmitting = true;
    });

    try {
      await Provider.of<AuthService>(context, listen: false).signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = FirebaseAuth.instance.currentUser;
      
      // ✅ CHECK IF VERIFIED
      if (user != null && !user.emailVerified) {
        await FirebaseAuth.instance.signOut(); // Log them out immediately
        
        _showStatus("Email not verified. Check your inbox.");

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Need a new verification link?"),
              backgroundColor: Colors.black87,
              // 👇 THIS IS THE FIX (3 Seconds)
              duration: const Duration(seconds: 3), 
              action: SnackBarAction(
                label: "RESEND",
                textColor: Colors.blueAccent,
                onPressed: _resendVerificationEmail,
              ),
            ),
          );
        }
        return; 
      }
      
      _showStatus("Login Successful!", isSuccess: true);
      _handleNavigation();

    } catch (e) {
      String errorMsg = e.toString().replaceAll('Exception:', '').trim();
      _showStatus(errorMsg);
    }
  }

  Future<void> _resendVerificationEmail() async {
    try {
      UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      await cred.user!.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("New link sent! Please check your email."),
            duration: Duration(seconds: 3), 
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      if(mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to resend link. Try again later."))
        );
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _statusMessage = null;
      _isSubmitting = true;
    });

    try {
      await Provider.of<AuthService>(context, listen: false).signInWithGoogle();
      _showStatus("Google Sign-In Successful!", isSuccess: true);
      _handleNavigation();
    } catch (e) {
      _showStatus("Google Sign-In failed.");
    }
  }

  // --- UI SECTION ---

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 150,
        leading: TextButton.icon(
          onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.black),
          label: const Text("Guest User", style: TextStyle(color: Colors.black)),
        ),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isTablet ? 450 : double.infinity),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    "Welcome",
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const Text("Sign in to continue", style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 40),

                  AnimatedOpacity(
                    opacity: _statusMessage != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: _statusMessage != null 
                        ? _buildStatusBanner() 
                        : const SizedBox(height: 0),
                  ),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildTextField(_emailController, "Email", Icons.email_outlined),
                        const SizedBox(height: 15),
                        _buildTextField(_passwordController, "Password", Icons.lock_outline, obscure: _obscurePassword),
                        _buildForgotPassword(),
                        const SizedBox(height: 20),
                        _buildLoginButton(),
                        const SizedBox(height: 20),
                        _buildDivider(),
                        const SizedBox(height: 20),
                        _buildGoogleButton(),
                        const SizedBox(height: 30),
                        _buildRegisterRedirect(),
                        const SizedBox(height: 20),
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

  // --- HELPERS ---

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _isSuccess ? Colors.black : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isSuccess ? Colors.black : Colors.red.shade200),
      ),
      child: Text(
        _statusMessage ?? "",
        style: TextStyle(color: _isSuccess ? Colors.white : Colors.red.shade800, fontWeight: FontWeight.w500),
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
        filled: true,
        fillColor: Colors.grey.shade100,
        prefixIcon: Icon(icon, color: Colors.black54),
        suffixIcon: hint == "Password" ? IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (val) => (val == null || val.isEmpty) ? "Required field" : null,
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {}, 
        child: const Text("Forgot Password?", style: TextStyle(color: Colors.black54)),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("Sign In", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OR", style: TextStyle(color: Colors.grey))),
        Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: OutlinedButton.icon(
        onPressed: _isSubmitting ? null : _loginWithGoogle,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 30),
        label: const Text("Continue with Google", style: TextStyle(color: Colors.black, fontSize: 16)),
      ),
    );
  }

  Widget _buildRegisterRedirect() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("New here?"),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/register'),
          child: const Text("Create Account", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}