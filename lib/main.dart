import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'core/config/google_maps_config.dart';
import 'core/layout/adaptive_layout.dart';
import 'core/constants/app_constants.dart';
import 'core/database/hive_database.dart';
import 'core/di/app_services.dart';
import 'core/di/service_locator.dart';
import 'core/network/token_store.dart';
import 'core/presentation/app_bloc_observer.dart';
import 'core/services/sync_service.dart';
import 'core/utils/google_maps_web_loader.dart';
import 'features/offline/data/hive_offline_store.dart';
import 'modules/auth/presentation/bloc/auth_session_cubit.dart';
import 'core/services/notification_service.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await NotificationService.instance.initialize();
    } catch (e) {
    }

    try {
      await HiveDatabase.instance.initialize();
    } catch (e) {
    }

    try {
      await HiveOfflineStore.instance.initialize();
    } catch (e) {
    }

    registerAppServices();

    final authCubit = AuthSessionCubit(ServiceLocator.I.get<TokenStore>())
      ..hydrate();
    ServiceLocator.I.register<AuthSessionCubit>(authCubit);

    if (kAppRunsOnPhoneHardware) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    Bloc.observer = AppBlocObserver();

    if (kIsWeb && GoogleMapsConfig.isConfigured) {
      final mapsReady = await ensureGoogleMapsJsLoaded();
      if (!mapsReady) {
      }
    }

    runApp(
      ProviderScope(
        child: TripTrackApp(authCubit: authCubit),
      ),
    );

    // Defer background sync registration so first frame is not blocked.
    if (kAppRunsOnPhoneHardware) {
      unawaited(_registerBackgroundSync());
    }
  } catch (e) {
    runApp(const FallbackApp());
  }
}

Future<void> _registerBackgroundSync() async {
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      'sync_task',
      'background_sync',
      frequency: const Duration(minutes: 15),
    );
  } catch (e) {
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await HiveDatabase.instance.initialize();

      // Check if a trip is active and if tracking has stopped
      try {
        final activeTripId = HiveDatabase.instance.getActiveTripIdSync();
        if (activeTripId != null && activeTripId.isNotEmpty) {
          final allRequests = await HiveDatabase.instance.getAllOfflineTravelRequests();
          var isTravelling = false;
          for (final row in allRequests) {
            final map = Map<String, dynamic>.from(row);
            final rid = map['requestId']?.toString() ?? '';
            final mongo = map['_id']?.toString() ?? '';
            if (rid == activeTripId || mongo == activeTripId) {
              final status = map['status']?.toString();
              final trackingStatus = map['trackingStatus']?.toString();
              if ((status == 'Travelling' || status == 'Returning') && trackingStatus == 'tracking') {
                isTravelling = true;
              }
              break;
            }
          }

          if (isTravelling) {
            final lastPointTime = await HiveDatabase.instance.lastRoutePointTimestamp(activeTripId);
            final now = DateTime.now().toUtc();
            final shouldWarn = lastPointTime == null || now.difference(lastPointTime).inMinutes >= 5;
            if (shouldWarn) {
              await NotificationService.instance.initialize();
              await NotificationService.instance.showNotification(
                id: 999,
                title: 'Trip Tracking Stopped',
                body: 'Your trip is active but tracking has stopped. Please open the app to resume your travel log.',
              );
            }
          }
        }
      } catch (e) {
      }

      final sync = createBackgroundSyncService();
      await sync.performBackgroundSync();
      sync.dispose();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

class FallbackApp extends StatelessWidget {
  const FallbackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rayzon Solar Trip Track',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please restart the app or contact support.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: SystemNavigator.pop,
                child: const Text('Close App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
