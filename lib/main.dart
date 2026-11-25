import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'views/app_launch_view.dart';
import 'services/auth_service.dart';
import 'services/currency_service.dart';
import 'services/cart_service.dart';
import 'views/admin_portal_view.dart';
import 'views/my_orders_view.dart';
import 'views/customer_storefront_view.dart';

const bool useFirebaseEmulator = bool.fromEnvironment(
  'USE_FIREBASE_EMULATOR',
  defaultValue: kDebugMode,
);

Future<void> _connectToFirebaseEmulators() async {
  final host = defaultTargetPlatform == TargetPlatform.android && !kIsWeb
      ? '10.0.2.2'
      : 'localhost';

  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8088);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (useFirebaseEmulator) {
    await _connectToFirebaseEmulators();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => CurrencyService()),
      ],
      child: const BarnockApp(),
    ),
  );
}

class BarnockApp extends StatelessWidget {
  const BarnockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barnock Digital Solutions',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFBFBFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF574325),
          primary: const Color(0xFF574325),
          secondary: const Color(0xFF8D8D8F),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF574325),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF574325),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AppLaunchView(),
        '/storefront': (context) => const CustomerStorefrontView(),
        '/orders': (context) => const MyOrdersView(),
        '/admin': (context) => const AdminPortalView(),
      },
    );
  }
}
