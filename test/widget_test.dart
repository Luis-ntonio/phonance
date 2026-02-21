import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:phonance/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // SQLite en tests (no usa Android/iOS real)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App loads', (tester) async {
    final db = await ExpensesDb.open();
    await tester.pumpWidget(MyApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('GPay/Wallet Expense Logger'), findsOneWidget);
  });
}
