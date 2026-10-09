import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/signature_store.dart';

void main() {
  late Directory temp;
  late SignatureStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anvil_sig');
    store = SignatureStore(Directory(p.join(temp.path, 'signatures')));
  });

  tearDown(() => temp.delete(recursive: true));

  test('list is empty before anything was saved', () async {
    expect(await store.list(), isEmpty);
  });

  test('saves list newest first and delete removes one', () async {
    final first = await store.save(Uint8List.fromList([1]));
    final second = await store.save(Uint8List.fromList([2]));
    final listed = await store.list();
    expect([for (final f in listed) f.path], [second.path, first.path]);
    await store.delete(second);
    await store.delete(second); // already gone: no throw
    expect([for (final f in await store.list()) f.path], [first.path]);
  });
}
