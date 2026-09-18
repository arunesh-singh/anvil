import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('csv-to-json is registered with expected metadata', () {
    final registry = ToolRegistry(buildTools());
    final tool = registry.byId('csv-to-json');
    expect(tool, isNotNull);
    expect(tool!.engine, EngineKind.dartlib);
    expect(tool.meta.acceptedExtensions, ['csv']);
    expect(tool.meta.category, ToolCategory.converter);
  });

  test('all 11 converters registered, unique ids, dartlib engine', () {
    final registry = ToolRegistry(buildTools());
    const expected = {
      'csv-to-json', 'csv-to-xml', 'csv-to-excel',
      'xml-to-csv', 'xml-to-excel', 'xml-to-json', 'json-to-xml',
      'excel-to-csv', 'excel-to-xml', 'split-csv', 'split-excel',
    };
    final converters = registry.byCategory(ToolCategory.converter);
    final ids = converters.map((t) => t.meta.id).toSet();
    expect(ids, expected);
    expect(converters, hasLength(expected.length));
    expect(converters.every((t) => t.engine == EngineKind.dartlib), isTrue);
  });

  test('all 34 pdf slugs registered; 32 on the pdf engine, 2 on the llm engine',
      () {
    final registry = ToolRegistry(buildTools());
    const expected = {
      'add-images', 'add-pages', 'add-text', 'compress', 'create',
      'crop', 'delete', 'edit', 'extract-img', 'extract-text', 'from-gif',
      'from-heic', 'from-jpg', 'from-png', 'from-tiff', 'from-url',
      'from-webp', 'merge', 'protect', 'rearrange', 'remove-watermark',
      'photo-caption',
      'rotate', 'sign', 'split', 'summarizer', 'to-csv', 'to-jpg', 'to-png',
      'to-text', 'to-tiff', 'translate', 'unlock', 'watermark',
    };
    final pdf = registry.byCategory(ToolCategory.pdf);
    final ids = pdf.map((t) => t.meta.id).toSet();
    expect(ids, expected);
    expect(pdf, hasLength(expected.length));
    expect(pdf.where((t) => t.engine == EngineKind.pdf), hasLength(32));
    expect(
      pdf.where((t) => t.engine == EngineKind.llm).map((t) => t.meta.id).toSet(),
      {'summarizer', 'translate'},
    );
    // tinywowSlug mirrors the id for every PDF tool.
    expect(pdf.every((t) => t.meta.tinywowSlug == t.meta.id), isTrue);
  });

  test('registry carries all 220 on-device tools with unique qualified ids', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byCategory(ToolCategory.converter), hasLength(11));
    expect(registry.byCategory(ToolCategory.pdf), hasLength(34));
    // 50 deterministic + 19 ML image tools.
    expect(registry.byCategory(ToolCategory.image), hasLength(69));
    // 47 deterministic + 5 ML video tools.
    expect(registry.byCategory(ToolCategory.video), hasLength(52));
    expect(registry.byCategory(ToolCategory.write), hasLength(54));
    expect(registry.all, hasLength(220));
    final qualified = registry.all.map((t) => t.meta.qualifiedId).toSet();
    expect(qualified, hasLength(220), reason: 'qualified ids must be unique');
  });

  test('write block runs on the llm engine except the deterministic counter',
      () {
    final registry = ToolRegistry(buildTools());
    final write = registry.byCategory(ToolCategory.write);
    final llm = write.where((t) => t.meta.id != 'word-counter');
    expect(llm, hasLength(53));
    expect(llm.every((t) => t.engine == EngineKind.llm), isTrue);
    expect(llm.every((t) => t.model?.taskId == 'agent.llm'), isTrue);
    final counter = registry.byId('write/word-counter')!;
    expect(counter.engine, EngineKind.dartlib);
    expect(counter.model, isNull);
  });

  test('merge and from-jpg accept multiple files; single-input tools do not', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byId('pdf/merge')!.meta.acceptsMultiple, isTrue);
    expect(registry.byId('pdf/from-jpg')!.meta.acceptsMultiple, isTrue);
    expect(registry.byId('pdf/split')!.meta.acceptsMultiple, isFalse);
    expect(registry.byId('pdf/extract-text')!.meta.acceptsMultiple, isFalse);
  });

  test('qualified byId disambiguates cross-category slug collisions', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byId('pdf/compress')!.meta.category, ToolCategory.pdf);
    expect(registry.byId('image/compress')!.meta.category, ToolCategory.image);
    expect(registry.byId('video/compress')!.meta.category, ToolCategory.video);
    expect(registry.byId('video/nope'), isNull);
  });

  test('pdf tools expose their params and accepted extensions', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byId('pdf/rotate')!.meta.params.single.key, 'degrees');
    expect(registry.byId('pdf/split')!.meta.params.single.key, 'every');
    expect(
        registry.byId('pdf/compress')!.meta.params.map((p) => p.key).toSet(),
        {'method', 'quality', 'dpi'});
    expect(registry.byId('pdf/extract-text')!.meta.acceptedExtensions, ['pdf']);
    expect(registry.byId('pdf/unlock')!.meta.params.single.type,
        ToolParamType.text);
    // Zero-input tools are flagged so the UI can enable Run without a file.
    expect(registry.byId('pdf/create')!.meta.requiresInput, isFalse);
    expect(registry.byId('pdf/from-url')!.meta.requiresInput, isFalse);
  });

  test('split tools declare a rowsPerFile param; others have none', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byId('split-csv')!.meta.params.single.key, 'rowsPerFile');
    expect(registry.byId('csv-to-json')!.meta.params, isEmpty);
  });

  test('byId returns null for unknown id', () {
    expect(ToolRegistry(buildTools()).byId('nope'), isNull);
  });

  test('byCategory filters', () {
    final registry = ToolRegistry(buildTools());
    expect(registry.byCategory(ToolCategory.converter), isNotEmpty);
    expect(registry.byCategory(ToolCategory.pdf), isNotEmpty);
  });
}
