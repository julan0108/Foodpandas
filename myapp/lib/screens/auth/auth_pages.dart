import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/customer_profile_service.dart';

const _authInk = Color(0xFF30251E);
const _authMuted = Color(0xFF81766E);
const _authOrange = Color(0xFFF47B20);
const _authCream = Color(0xFFFFF9EF);

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authService,
    required this.onAuthenticated,
    required this.onForgotPassword,
  });

  final AuthService authService;
  final ValueChanged<AuthUser> onAuthenticated;
  final VoidCallback onForgotPassword;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('auth-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 42, 22, 52),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0E8DF)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    color: _authOrange,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _registering ? 'Join the neighborhood' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _authInk,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _registering
                        ? 'Create an account to place and follow your orders.'
                        : 'Sign in to continue to your order.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _authMuted),
                  ),
                  const SizedBox(height: 24),
                  if (_registering) ...[
                    TextFormField(
                      key: const Key('auth-name'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: _authDecoration(
                        'Full name',
                        Icons.person_outline_rounded,
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    key: const Key('auth-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: _authDecoration(
                      'Email address',
                      Icons.email_outlined,
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(email)
                          ? null
                          : 'Enter a valid email address';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('auth-password'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: _registering
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autofillHints: _registering
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration:
                        _authDecoration(
                          'Password',
                          Icons.lock_outline_rounded,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                    validator: (value) => (value?.length ?? 0) < 6
                        ? 'Use at least 6 characters'
                        : null,
                  ),
                  if (_registering) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('auth-confirm-password'),
                      controller: _confirmController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: _authDecoration(
                        'Confirm password',
                        Icons.lock_outline_rounded,
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                  ],
                  if (!_registering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : widget.onForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                  if (_error != null) ...[
                    _AuthMessage(text: _error!, error: true),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    key: const Key('auth-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _authOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_registering ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                          }),
                    child: Text(
                      _registering
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _registering
          ? await widget.authService.register(
              _emailController.text.trim(),
              _passwordController.text,
              _nameController.text.trim(),
            )
          : await widget.authService.signIn(
              _emailController.text.trim(),
              _passwordController.text,
            );
      if (mounted) widget.onAuthenticated(user);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.authService,
    required this.email,
    required this.onVerified,
    required this.onSignOut,
  });

  final AuthService authService;
  final String email;
  final VoidCallback onVerified;
  final VoidCallback onSignOut;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _sending = false;
  bool _checking = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _sendVerificationEmail(),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('verify-email-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 46, 22, 52),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0E8DF)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: _authOrange,
                  size: 44,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _authInk,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open the verification link sent to ${widget.email}, then return here and check your status.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _authMuted, height: 1.5),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _AuthMessage(text: _error!, error: true),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  _AuthMessage(text: _notice!, error: false),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('check-email-verified'),
                    onPressed: _checking ? null : _checkVerification,
                    style: FilledButton.styleFrom(
                      backgroundColor: _authOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("I've verified my email"),
                  ),
                ),
                TextButton(
                  onPressed: _sending ? null : _sendVerificationEmail,
                  child: Text(
                    _sending ? 'Sending email…' : 'Resend verification email',
                  ),
                ),
                TextButton(
                  onPressed: _checking || _sending ? null : widget.onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _sendVerificationEmail() async {
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.authService.sendVerificationEmail();
      if (mounted) {
        setState(() {
          _notice = 'A verification link was sent to your email.';
        });
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() {
      _checking = true;
      _error = null;
      _notice = null;
    });
    try {
      final user = await widget.authService.reloadCurrentUser();
      if (!mounted) return;
      if (user.emailVerified) {
        widget.onVerified();
      } else {
        setState(() {
          _notice = 'Email is not verified yet. Open the link in your inbox, then try again.';
        });
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    required this.authService,
    required this.onBack,
  });

  final AuthService authService;
  final VoidCallback onBack;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('forgot-password-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 46, 22, 52),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0E8DF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_reset_rounded,
                  color: _authOrange,
                  size: 44,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _authInk,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We’ll email you a secure password reset link.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _authMuted),
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('reset-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _authDecoration(
                    'Email address',
                    Icons.email_outlined,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _AuthMessage(text: _error!, error: true),
                ],
                if (_sent) ...[
                  const SizedBox(height: 12),
                  const _AuthMessage(
                    text: 'If an account exists for that address, a reset email is on the way.',
                    error: false,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _authOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send reset email'),
                ),
                TextButton(
                  onPressed: widget.onBack,
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _sent = false;
    });
    try {
      await widget.authService.sendPasswordResetEmail(email);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.authService,
    required this.customerProfileService,
    required this.user,
    required this.onUpdated,
    required this.onSignOut,
  });

  final AuthService authService;
  final CustomerProfileService customerProfileService;
  final AuthUser user;
  final ValueChanged<AuthUser> onUpdated;
  final VoidCallback onSignOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName);
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('profile-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 42, 22, 52),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0E8DF)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    color: _authOrange,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _authInk,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    key: const Key('profile-name'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 100,
                    decoration: _authDecoration(
                      'Full name',
                      Icons.person_outline_rounded,
                    ),
                    validator: (value) =>
                        (value?.trim().length ?? 0) < 2 ||
                            (value?.trim().length ?? 0) > 100
                        ? 'Enter a name between 2 and 100 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('profile-phone'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    decoration: _authDecoration(
                      'Mobile number',
                      Icons.phone_outlined,
                    ),
                    validator: (value) =>
                        value == null ||
                            (value.trim().isNotEmpty &&
                                (value.trim().length < 7 ||
                                    value.trim().length > 30))
                        ? 'Enter a valid mobile number'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('profile-address'),
                    controller: _addressController,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: _authDecoration(
                      'Delivery address',
                      Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: _authDecoration(
                      'Email address',
                      Icons.email_outlined,
                    ),
                    child: Text(
                      widget.user.email,
                      style: const TextStyle(color: _authInk),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        widget.user.emailVerified
                            ? Icons.verified_rounded
                            : Icons.error_outline_rounded,
                        color: widget.user.emailVerified
                            ? const Color(0xFF347A55)
                            : _authOrange,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        widget.user.emailVerified
                            ? 'Email verified'
                            : 'Email verification required before checkout',
                        style: const TextStyle(color: _authMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _AuthMessage(text: _error!, error: true),
                  ],
                  if (_saved) ...[
                    const SizedBox(height: 14),
                    const _AuthMessage(
                      text: 'Your profile has been updated.',
                      error: false,
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy || _loading ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _authOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save profile'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : widget.onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.customerProfileService.getProfile(
        widget.user.uid,
      );
      if (!mounted || profile == null) return;
      _nameController.text = profile.displayName.isEmpty
          ? widget.user.displayName
          : profile.displayName;
      _phoneController.text = profile.phone;
      _addressController.text = profile.deliveryAddress;
    } on CustomerProfileFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final user = await widget.authService.updateDisplayName(
        _nameController.text.trim(),
      );
      await widget.customerProfileService.saveProfile(
        user.uid,
        CustomerProfile(
          email: user.email,
          displayName: user.displayName,
          phone: _phoneController.text.trim(),
          deliveryAddress: _addressController.text.trim(),
        ),
      );
      if (mounted) {
        setState(() => _saved = true);
        widget.onUpdated(user);
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on CustomerProfileFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

InputDecoration _authDecoration(String label, IconData icon) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, size: 20),
  filled: true,
  fillColor: _authCream,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFECE4DA)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFECE4DA)),
  ),
);

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({required this.text, required this.error});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFEFED) : const Color(0xFFEAF5EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: error ? const Color(0xFF9C342B) : const Color(0xFF2D7046),
        fontSize: 13,
      ),
    ),
  );
}
