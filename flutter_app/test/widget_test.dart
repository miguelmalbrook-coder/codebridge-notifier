import 'package:flutter_test/flutter_test.dart';
import 'package:codebridge_notifier/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const NotifierApp());
    expect(find.text('Codebridge Notifier'), findsOneWidget);
  });
}
