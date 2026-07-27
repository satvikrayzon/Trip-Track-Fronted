import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/svg.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/utils/asset_utils.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/animated_background.dart';
import '../../../../core/widgets/custom_action_button.dart';
import '../../../../core/widgets/fade_slide_transition.dart';
import '../controllers/app_auth_controller.dart';

/// Login Screen with Beautiful Animated Background
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final AppAuthController _authController;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _isPasswordObscured = ValueNotifier<bool>(true);
  final _isLoading = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _initAuthController();
  }

  void _initAuthController() {
    _authController = ServiceLocator.I.get<AppAuthController>();
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _isPasswordObscured.dispose();
    _isLoading.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value);
  }

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF022E3A),
                    Color(0xFF095763),
                    Color(0xFF073A48),
                  ],
                ),
              ),
            ),
          ),

          // Background shapes
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                  painter: BackgroundShapesPainter(_controller.value)),
            ),
          ),

          // Logo
          Positioned(
            top: size.height * 0.14,
            left: 0,
            right: 0,
            child: FadeSlideTransition(
              milliseconds: 800,
              direction: AnimationDirection.down,
              curve: Curves.easeOutCubic,
              child: Image.asset(
                AssetUtilities.whiteLogo,
                height: 50.scp(context),
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 50.scp(context),
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Center(
                      child: Text(
                        'RAYZON SOLAR',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Sun animation
          Center(
            child: SizedBox(
              height: size.height * 0.35,
              width: size.height * 0.35,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: size.height * 0.18,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => CustomPaint(
                        painter: SunRingsPainterV3(_controller.value),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Glass form
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24.scp(context)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.scp(context)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(24.scp(context)),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24.scp(context)),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Welcome Text
                          FadeSlideTransition(
                            milliseconds: 900,
                            direction: AnimationDirection.up,
                            curve: Curves.easeOutBack,
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Colors.tealAccent, Colors.cyanAccent],
                              ).createShader(bounds),
                              child: Text(
                                'Welcome to Rayzon',
                                style: FontUtilities.style(
                                  fontSize: 26.scp(context),
                                  fontWeight: FWT.bold,
                                  fontColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 20.scp(context)),

                          // Email Field
                          FadeSlideTransition(
                            milliseconds: 1000,
                            direction: AnimationDirection.left,
                            curve: Curves.easeOutCubic,
                            child: TextFormField(
                              style: FontUtilities.style(
                                fontColor: Colors.white,
                                fontSize: 14.scp(context),
                              ),
                              controller: _emailController,
                              autofocus: false,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email or mobile';
                                }
                                if (!_isValidEmail(value) &&
                                    !_isValidPhone(value)) {
                                  return 'Please enter a valid email or mobile number';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                hintText: 'Email',
                                hintStyle: FontUtilities.style(
                                  fontColor: Colors.white54,
                                  fontSize: 14.scp(context),
                                  fontWeight: FWT.semiBold,
                                ),
                                prefixIcon: Icon(
                                  Icons.email_rounded,
                                  color: Colors.white54,
                                  size: 20.scp(context),
                                ),
                                filled: true,
                                isDense: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(15.scp(context)),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(15.scp(context)),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(15.scp(context)),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: 12.scp(context)),

                          // Password Field
                          FadeSlideTransition(
                            milliseconds: 1100,
                            direction: AnimationDirection.right,
                            curve: Curves.easeOutCubic,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _isPasswordObscured,
                              builder: (context, isObscured, _) =>
                                  TextFormField(
                                style: FontUtilities.style(
                                  fontColor: Colors.white,
                                  fontSize: 14.scp(context),
                                ),
                                controller: _passwordController,
                                obscureText: isObscured,
                                keyboardType: TextInputType.visiblePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                decoration: InputDecoration(
                                  hintStyle: FontUtilities.style(
                                    fontColor: Colors.white54,
                                    fontSize: 14.scp(context),
                                    fontWeight: FWT.semiBold,
                                  ),
                                  hintText: "Enter your Password",
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12.scp(context)),
                                    child: Icon(
                                      Icons.lock_rounded,
                                      size: 20.scp(context),
                                      color: Colors.white54,
                                    ),
                                  ),
                                  filled: true,
                                  isDense: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(15.scp(context)),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          15.scp(context)),
                                      borderSide: BorderSide.none),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(15.scp(context)),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIconConstraints: BoxConstraints(
                                      maxHeight: 24.scp(context)),
                                  suffixIcon: Padding(
                                    padding:
                                        EdgeInsets.only(right: 12.scp(context)),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        radius: 0,
                                        onTap: () {
                                          _isPasswordObscured.value =
                                              !isObscured;
                                        },
                                        child: SvgPicture.asset(
                                          isObscured
                                              ? AssetUtilities.visibility
                                              : AssetUtilities.visibilityOff,
                                          height: 24.scp(context),
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return "Please enter your password";
                                  }
                                  if (value.length < 6) {
                                    return "Password must be at least 6 characters";
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),

                          SizedBox(height: 8.scp(context)),

                          // Forgot password link
                          FadeSlideTransition(
                            milliseconds: 1200,
                            direction: AnimationDirection.left,
                            curve: Curves.easeOut,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  onTap: () => AppNavigation.to(
                                      AppRoutes.forgotPassword),
                                  child: Text(
                                    'Forgot Password?',
                                    style: FontUtilities.style(
                                      fontSize: 14,
                                      fontWeight: FWT.regular,
                                      fontColor: Colors.white60,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 20.scp(context)),

                          // Privacy policy link
                          FadeSlideTransition(
                            milliseconds: 1300,
                            direction: AnimationDirection.right,
                            curve: Curves.easeOut,
                            child: GestureDetector(
                              onTap: () async {
                                final url = AppConstants.privacyPolicyUrl;
                                final uri = Uri.tryParse(url);
                                if (uri == null) {
                                  showAppSnackBar(
                                    title: 'Privacy Policy',
                                    message:
                                        'Invalid privacy policy URL. Please contact support.',
                                    backgroundColor:
                                        Colors.red.withOpacity(0.15),
                                    textColor: Colors.red,
                                  );
                                  return;
                                }

                                final ok = await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );

                                if (!ok) {
                                  showAppSnackBar(
                                    title: 'Privacy Policy',
                                    message:
                                        'Could not open privacy policy in browser.',
                                    backgroundColor:
                                        Colors.white.withOpacity(0.1),
                                    textColor: Colors.white,
                                  );
                                }
                              },
                              child: Text(
                                'Privacy & Policy',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  color: Colors.tealAccent.withOpacity(
                                    0.6 + 0.4 * sin(_controller.value * pi),
                                  ),
                                ).copyWith(
                                  decorationColor:
                                      Colors.tealAccent.withOpacity(
                                    0.6 + 0.4 * sin(_controller.value * pi),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: 20.scp(context)),

                          // Login button
                          FadeSlideTransition(
                            milliseconds: 1400,
                            direction: AnimationDirection.up,
                            curve: Curves.bounceOut,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _isLoading,
                              builder: (context, isLoading, _) =>
                                  CustomActionButton(
                                text: 'LOGIN',
                                onTap: _handleLogin,
                                isLoading: isLoading,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      _isLoading.value = true;
      await _authController.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      final error = _authController.errorMessage.value;
      if (error.isNotEmpty) {
        showAppSnackBar(
          title: 'Login Failed',
          message: error,
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      showAppSnackBar(
        title: 'Login Failed',
        message: e.toString(),
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        textColor: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }
}
