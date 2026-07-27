import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart' hide Transition;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_messenger.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../modules/auth/presentation/bloc/auth_session_cubit.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';

class TripTrackApp extends ConsumerWidget {
  const TripTrackApp({super.key, required this.authCubit});

  final AuthSessionCubit authCubit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(_routerProvider);

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthSessionCubit>.value(value: authCubit),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        routerConfig: router,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final capped = mq.textScaler.clamp(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.35,
          );
          return MediaQuery(
            data: mq.copyWith(textScaler: capped),
            child: child ??
                const ColoredBox(
                  color: Color(0xFFFAFAFA),
                  child: Center(child: CircularProgressIndicator()),
                ),
          );
        },
      ),
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) => createAppRouter());
