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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION (UPDATED) ---

  void _handleNavigation() {
    Navigator.pushReplacementNamed(context, '/');
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _statusMessage = null;
      _isSubmitting = true;
    });

    try {
      // 1. Sign in the user
      await Provider.of<AuthService>(context, listen: false).signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Get the current user instance
      User? user = FirebaseAuth.instance.currentUser;
      
      if (user != null && !user.emailVerified) {
        // --- THE "NEW EMAIL" LOGIC ---
        
        // We sign them out because they aren't verified
        await FirebaseAuth.instance.signOut();
        
        if (mounted) {
          setState(() {
            _isSuccess = false;
            _isSubmitting = false;
            _statusMessage = "Email not verified. Please check your inbox.";
          });

          // Show a SnackBar with a "Resend" button
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Need a new verification link?"),
              backgroundColor: Colors.black,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: "RESEND",
                textColor: Colors.deepPurpleAccent,
                onPressed: () async {
                  // To resend, we briefly sign in again just to trigger the email
                  try {
                    UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
                      email: _emailController.text.trim(),
                      password: _passwordController.text.trim(),
                    );
                    await cred.user!.sendEmailVerification();
                    await FirebaseAuth.instance.signOut(); // Sign back out
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("New link sent! Please check your email."))
                      );
                    }
                  } catch (e) {
                    debugPrint("Resend failed: $e");
                  }
                },
              ),
            ),
          );
        }
        return; 
      }
      
      // ✅ If verified, proceed to Home
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _statusMessage = "Login Successful!";
        });
        _handleNavigation();
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

  Future<void> _loginWithGoogle() async {
    setState(() {
      _statusMessage = null;
      _isSubmitting = true;
    });

    try {
      await Provider.of<AuthService>(context, listen: false).signInWithGoogle();
      
      // Google accounts are auto-verified, so we don't strictly need to check, 
      // but you can add the same check here if you want to be safe.
      
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _statusMessage = "Google Sign-In Successful!";
        });
        _handleNavigation();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSuccess = false;
          _statusMessage = "Google Sign-In failed: ${e.toString()}";
          _isSubmitting = false;
        });
      }
    }
  }

  // --- UI SECTION (SAME AS BEFORE) ---

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

                  if (_statusMessage != null) _buildStatusBanner(),

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
        _statusMessage!,
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