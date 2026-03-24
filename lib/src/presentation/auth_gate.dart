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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _seedToastShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider).initialize());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    final controller = ref.read(authControllerProvider);
    await controller.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (mounted && controller.errorMessage == null) {
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (_emailController.text.isEmpty && auth.registeredEmail != null) {
      _emailController.text = auth.registeredEmail!;
    }

    if (auth.seededUserThisLaunch && !_seedToastShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _seedToastShown) {
          return;
        }
        setState(() => _seedToastShown = true);
        ref.read(authControllerProvider).clearSeededUserNotice();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Default user created. Log in with ${auth.registeredEmail ?? 'admin@jarin.com'}.',
            ),
          ),
        );
      });
    }

    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.isAuthenticated) {
      return widget.child;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.security_outlined,
                        size: 34,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Log in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      auth.hasAccount
                          ? 'Sign in to continue to Jarin Pharmacy.'
                          : 'No account found in the app database yet. Restart once to auto-create the default user (admin@jarin.com / Jarin@2026).',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (auth.lockedUntil != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Locked until ${DateFormat('hh:mm a').format(auth.lockedUntil!)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(auth),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.password_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: auth.rememberMe,
                      onChanged: auth.hasAccount
                          ? (value) => ref
                                .read(authControllerProvider)
                                .setRememberMe(value ?? false)
                          : null,
                      title: const Text('Remember me'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        auth.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          auth.isBusy || auth.lockedUntil != null || !auth.hasAccount
                          ? null
                          : () => _submit(auth),
                      icon: const Icon(Icons.login_outlined),
                      label: const Text('Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
