
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart'; // para REST/GraphQL
import 'amplifyconfiguration.dart';

class AmplifyInit {
  static bool _configured = false;

  static Future<void> ensureConfigured() async {
    if (_configured) return;

    // Registra plugins (auth + api)
    final auth = AmplifyAuthCognito();
    final api = AmplifyAPI(); // si usarás REST/GraphQL

    await Amplify.addPlugins([auth, api]);

    // Aplica la configuración generada por 'amplify push'
    await Amplify.configure(amplifyconfig);

    _configured = true;
  }
}
