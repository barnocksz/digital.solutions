import 'package:flutter_test/flutter_test.dart';
import 'package:barnock/models/catalog_item.dart';

void main() {
  test('CatalogItem serialization sanity test', () {
    final item = CatalogItem(
      id: '1',
      title: 'ESP32 Controller',
      description: 'Programmable MCU unit',
      basePrice: 49.99,
      type: CatalogType.hardware,
    );
    final map = item.toFirestore();
    expect(map['title'], 'ESP32 Controller');
    expect(map['basePrice'], 49.99);
  });
}
