import 'package:flutter_test/flutter_test.dart';
import 'package:mahdvpn_client/app.dart';
void main(){testWidgets('client renders app shell', (tester) async {await tester.pumpWidget(const MahdiClientApp());expect(find.text('MahdiVPN'),findsOneWidget);});}
