import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import 'auth_controller.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  // ── Login form state ──
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureLogin = true;

  // ── Register form state ──
  final TextEditingController _regEmailController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmController = TextEditingController();
  bool _obscureReg = true;
  bool _obscureRegConfirm = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider).initialize());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin(AuthController auth) async {
    final controller = ref.read(authControllerProvider);
    await controller.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (mounted && controller.errorMessage == null) {
      _passwordController.clear();
    }
  }

  Future<void> _submitRegister(BuildContext context) async {
    final controller = ref.read(authControllerProvider);
    final email = _regEmailController.text.trim();
    final pw = _regPasswordController.text;
    final confirm = _regConfirmController.text;

    if (pw != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }
    await controller.createAccount(email: email, password: pw);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.isAuthenticated) {
      return widget.child;
    }

    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (!auth.hasAccount) {
      body = _buildRegisterCard(context, auth, scheme);
    } else {
      if (_emailController.text.isEmpty && auth.registeredEmail != null) {
        _emailController.text = auth.registeredEmail!;
      }
      body = _buildLoginCard(context, auth, scheme);
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.18),
              scheme.secondary.withValues(alpha: 0.12),
              scheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterCard(
    BuildContext context,
    AuthController auth,
    ColorScheme scheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                ),
                child: Icon(
                  Icons.person_add_outlined,
                  size: 34,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Set up your login to access Jarin Pharmacy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _regEmailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _regPasswordController,
              obscureText: _obscureReg,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureReg = !_obscureReg),
                  icon: Icon(
                    _obscureReg
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _regConfirmController,
              obscureText: _obscureRegConfirm,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitRegister(context),
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureRegConfirm = !_obscureRegConfirm),
                  icon: Icon(
                    _obscureRegConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                auth.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: auth.isBusy ? null : () => _submitRegister(context),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginCard(
    BuildContext context,
    AuthController auth,
    ColorScheme scheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                ),
                child: Icon(
                  Icons.security_outlined,
                  size: 34,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Log in',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to continue to Jarin Pharmacy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (auth.lockedUntil != null) ...[
              const SizedBox(height: 12),
              Text(
                'Locked until ${DateFormat('hh:mm a').format(auth.lockedUntil!)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscureLogin,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitLogin(auth),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.password_outlined),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureLogin = !_obscureLogin),
                  icon: Icon(
                    _obscureLogin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: auth.rememberMe,
              onChanged: (value) => ref
                  .read(authControllerProvider)
                  .setRememberMe(value ?? false),
              title: const Text('Remember me'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                auth.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: auth.isBusy || auth.lockedUntil != null
                  ? null
                  : () => _submitLogin(auth),
              icon: const Icon(Icons.login_outlined),
              label: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
