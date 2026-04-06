import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../core/backup/backup_service.dart';
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

  /// Allows the user to pick a backup file on the register/first-run screen
  /// and fully restore it — including credentials — so they can log in with
  /// their original email and password without creating a new account.
  Future<void> _restoreFromBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      dialogTitle: 'Select Backup File',
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;

    // Validate integrity first.
    final validation = await BackupService().validateBackup(bytes);
    if (!mounted) return;
    if (!validation.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation.error ?? 'Invalid backup file.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Confirm with the user.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: Text(
          'This will restore your account and all pharmacy data from the backup.\n\n'
          'Backup date: ${validation.meta?.exportedAt ?? 'unknown'}\n\n'
          'After restore you will be asked to log in with your original email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Show progress.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restoring backup…'),
        duration: Duration(seconds: 60),
      ),
    );

    final result = await BackupService().restoreBackup(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Restore failed.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Re-detect the restored account so the gate switches to the login form.
    await ref.read(authControllerProvider).forceReinitialize();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Backup restored. Please log in with your original credentials.',
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );
  }

  List<Widget> _featureBullets() {
    const features = [
      (Icons.point_of_sale_outlined, 'Fast point-of-sale billing'),
      (Icons.inventory_2_outlined, 'Real-time stock management'),
      (Icons.account_balance_wallet_outlined, 'bKash cash-in/out tracking'),
      (Icons.query_stats_outlined, 'Detailed business reports'),
      (Icons.people_outline, 'Customer profiles & dues'),
    ];
    return features
        .map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(f.$1, color: Colors.white, size: 15),
                ),
                const SizedBox(width: 12),
                Text(
                  f.$2,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
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

    Widget formWidget;
    if (!auth.hasAccount) {
      formWidget = _buildRegisterCard(context, auth, scheme);
    } else {
      if (_emailController.text.isEmpty && auth.registeredEmail != null) {
        _emailController.text = auth.registeredEmail!;
      }
      formWidget = _buildLoginCard(context, auth, scheme);
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;

          if (isWide) {
            return Row(
              children: [
                // ── Left branding panel ──
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1D4ED8),
                          Color(0xFF2563EB),
                          Color(0xFF0EA5E9),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 40,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 1.5,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  '+',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 34,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Jarin Pharmacy',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 30,
                                letterSpacing: -0.6,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Smart Pharmacy Management System',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 36),
                            ..._featureBullets(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Right form panel ──
                Expanded(
                  flex: 4,
                  child: Container(
                    color: scheme.surface,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: formWidget,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Mobile (centered card) ──
          return Container(
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
                  child: formWidget,
                ),
              ),
            ),
          );
        },
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
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed:
                  auth.isBusy ? null : () => _restoreFromBackup(),
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore from Backup'),
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
