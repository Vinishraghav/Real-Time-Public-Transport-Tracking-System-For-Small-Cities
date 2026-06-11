import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _busNumberController = TextEditingController();

  @override
  void dispose() {
    _busNumberController.dispose();
    super.dispose();
  }

  Future<void> _loginAsDriver() async {
    final strings = context.l10n;
    final busNumber = _busNumberController.text.trim().toUpperCase();
    if (busNumber.isEmpty) {
      _showError(
        strings.isTamil
            ? 'சரியான பஸ் நம்பரை உள்ளிடவும்.'
            : 'Please enter a valid bus number.',
      );
      return;
    }

    final password = await _showDriverPasswordDialog(busNumber);
    if (!mounted || password == null || password.isEmpty) return;

    final success = await context.read<AuthProvider>().signInDriver(
      busNumber: busNumber,
      password: password,
    );
    if (!mounted) return;

    if (!success) {
      _showError(
        context.read<AuthProvider>().error ??
            (strings.isTamil
                ? 'டிரைவர் உள்நுழைவு தோல்வியடைந்தது.'
                : 'Driver login failed.'),
      );
      return;
    }

    await context.read<LocationProvider>().requestLocationPermission();
    if (mounted) context.go('/home');
  }

  Future<void> _openPassengerLogin() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _PassengerAuthDialog(),
    );

    if (!mounted || success != true) return;

    await context.read<LocationProvider>().requestLocationPermission();
    if (mounted) context.go('/home');
  }

  Future<String?> _showDriverPasswordDialog(String busNumber) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _DriverPasswordDialog(busNumber: busNumber),
    );
    return result;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.alertRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: AppTheme.textPrimary(context),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    strings.t('welcome_to'),
                    style: TextStyle(
                      fontSize: 28,
                      color: AppTheme.textSecondary(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CityBus Live',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.t('login_description'),
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 56),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.surface(context),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.shadow(context),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.t('bus_number'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _busNumberController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'e.g. TN38AB1234',
                            prefixIcon: Icon(
                              Icons.directions_bus_rounded,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: authProvider.isLoading
                                ? null
                                : _loginAsDriver,
                            child: authProvider.isLoading
                                ? const CircularProgressIndicator(
                                    color: AppTheme.surfaceWhite,
                                  )
                                : Text(strings.t('login_as_driver')),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(color: AppTheme.divider(context)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: AppTheme.textSecondary(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(color: AppTheme.divider(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: authProvider.isLoading
                                ? null
                                : _openPassengerLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.accentOrange,
                              side: const BorderSide(
                                color: AppTheme.accentOrange,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              strings.t('continue_as_passenger'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Center(
                    child: Text(
                      strings.isTamil
                          ? 'டிரைவர் கணக்குகள் Firestore drivers collection-ல் இருந்து பெறப்படுகின்றன.'
                          : 'Driver accounts are resolved from Firestore drivers collection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PassengerAuthDialog extends StatefulWidget {
  const _PassengerAuthDialog();

  @override
  State<_PassengerAuthDialog> createState() => _PassengerAuthDialogState();
}

class _DriverPasswordDialog extends StatefulWidget {
  const _DriverPasswordDialog({required this.busNumber});

  final String busNumber;

  @override
  State<_DriverPasswordDialog> createState() => _DriverPasswordDialogState();
}

class _DriverPasswordDialogState extends State<_DriverPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        strings.t('driver_login'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bus ${widget.busNumber}',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: strings.t('enter_password'),
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.t('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _passwordController.text.trim()),
          child: Text(strings.t('continue')),
        ),
      ],
    );
  }
}

class _PassengerAuthDialogState extends State<_PassengerAuthDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final authProvider = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final strings = context.l10n;

    if (email.isEmpty || password.isEmpty) return;

    final success = _isRegisterMode
        ? await authProvider.registerPassenger(
            email: email,
            password: password,
            displayName: name.isEmpty
                ? (strings.isTamil ? 'பயணி' : 'Passenger')
                : name,
          )
        : await authProvider.signInPassenger(email: email, password: password);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _signInWithGoogle() async {
    final success = await context.read<AuthProvider>().signInWithGoogle();
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        _isRegisterMode
            ? strings.t('create_passenger_account')
            : strings.t('passenger_login'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRegisterMode) ...[
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: strings.t('full_name'),
                      prefixIcon: const Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: strings.t('email_address'),
                    prefixIcon: const Icon(Icons.email_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: strings.t('password'),
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                ),
                if (authProvider.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    authProvider.error!,
                    style: const TextStyle(color: AppTheme.alertRed),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _submit,
                    child: authProvider.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.surfaceWhite,
                            ),
                          )
                        : Text(
                            _isRegisterMode
                                ? strings.t('create_account')
                                : strings.t('login'),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: authProvider.isLoading
                        ? null
                        : _signInWithGoogle,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(strings.t('continue_with_google')),
                  ),
                ),
                TextButton(
                  onPressed: authProvider.isLoading
                      ? null
                      : () {
                          authProvider.clearError();
                          setState(() => _isRegisterMode = !_isRegisterMode);
                        },
                  child: Text(
                    _isRegisterMode
                        ? strings.t('already_have_account')
                        : strings.t('need_account'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
