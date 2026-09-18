/// LLM write tools (Phase 3): 54 write-category generators/rewriters plus the
/// two LLM PDF tools (summarizer, translate), all running on-device through
/// [LlmEngine] (Gemma via flutter_gemma; model delivered by [ModelManager] as
/// task `agent.llm`). `word-counter` is deterministic — no model.
/// The single registration list for this block lives in [buildWriteTools].
library;


import 'dart:typed_data';
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/llm_engine.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/models/model_manager.dart';

const llmModel = ModelSpec(taskId: 'agent.llm');

// ── Helpers ──────────────────────────────────────────────────────────────────

String _textParam(Map<String, dynamic> p, String key, String fallback) =>
    switch (p[key]) {
      final String v when v.trim().isNotEmpty => v.trim(),
      _ => fallback,
    };

String _outName(String base, String ext) {
  final dot = base.lastIndexOf('.');
  final stem = dot <= 0 ? base : base.substring(0, dot);
  return '$stem.$ext';
}

/// Loads the shared Gemma model through Phase-2 delivery, then generates.
Future<String> runLlm(String prompt) async {
  final model = await getIt<ModelManager>().ensureReady(llmModel);
  final engine = getIt<LlmEngine>();
  await engine.ensureLoaded(model.filePath);
  return engine.generate(prompt);
}

/// One LLM text tool: typed text (or an optional .txt/.md file) in, text out.
class _LlmTool extends BaseToolModule {
  _LlmTool(this.meta, this._prompt);
  @override
  final ToolMeta meta;

  /// (main input text, params) → full prompt.
  final String Function(String input, Map<String, dynamic> params) _prompt;

  @override
  EngineKind get engine => EngineKind.llm;

  @override
  ModelSpec? get model => llmModel;

  @override
  Future<void> ensureReady() async {
    final loaded = await getIt<ModelManager>().ensureReady(llmModel);
    await getIt<LlmEngine>().ensureLoaded(loaded.filePath);
  }

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    var text = _textParam(input.params, 'text', '');
    final f = input.files.firstOrNull;
    if (f != null) {
      text = await getIt<FileService>().readString(f.path);
    }
    if (text.trim().isEmpty) {
      throw const ToolException('Enter some text (or pick a text file).');
    }
    yield const ToolRunning(message: 'Generating…');
    final out = await runLlm(_prompt(text.trim(), input.params));
    yield const ToolRunning(fraction: 0.9, message: 'Saving…');
    final name = _outName(f?.name ?? '${meta.id}.txt', 'txt');
    final file = await getIt<FileService>().writeString(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: 'text/plain')],
      text: out,
    ));
  }
}

/// LLM PDF tool: extracts the PDF text first, then prompts.
class _LlmPdfTool extends BaseToolModule {
  _LlmPdfTool(this.meta, this._prompt);
  @override
  final ToolMeta meta;
  final String Function(String pdfText, Map<String, dynamic> params) _prompt;

  @override
  EngineKind get engine => EngineKind.llm;

  @override
  ModelSpec? get model => llmModel;

  @override
  Future<void> ensureReady() async {
    final loaded = await getIt<ModelManager>().ensureReady(llmModel);
    await getIt<LlmEngine>().ensureLoaded(loaded.filePath);
  }

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    final f = input.files.single;
    yield const ToolRunning(message: 'Reading PDF…');
    final bytes = await getIt<FileService>().readBytes(f.path);
    final text =
        await getIt<PdfEngine>().extractText(Uint8List.fromList(bytes));
    if (text.trim().isEmpty) {
      throw const ToolException(
          'No selectable text found — this PDF may be scanned images.');
    }
    yield const ToolRunning(fraction: 0.4, message: 'Generating…');
    final out = await runLlm(_prompt(text.trim(), input.params));
    yield const ToolRunning(fraction: 0.9, message: 'Saving…');
    final name = _outName(f.name, 'txt');
    final file = await getIt<FileService>().writeString(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: 'text/plain')],
      text: out,
    ));
  }
}

/// Deterministic word/character/sentence counter — no model.
class _WordCounter extends BaseToolModule {
  _WordCounter(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    var text = _textParam(input.params, 'text', '');
    final f = input.files.firstOrNull;
    if (f != null) {
      text = await getIt<FileService>().readString(f.path);
    }
    if (text.trim().isEmpty) {
      throw const ToolException('Enter some text (or pick a text file).');
    }
    yield const ToolRunning(message: 'Counting…');
    final report = await runOffThread(() => wordCountReport(text));
    yield ToolSucceeded(ToolResult(files: const [], text: report));
  }
}

/// Pure counting core (host-tested).
String wordCountReport(String text) {
  final words = RegExp(r"[\w'-]+").allMatches(text).length;
  final chars = text.length;
  final charsNoSpace = text.replaceAll(RegExp(r'\s'), '').length;
  final sentences =
      text.split(RegExp(r'[.!?]+(\s|$)')).where((s) => s.trim().isNotEmpty).length;
  final paragraphs = text
      .split(RegExp(r'\n\s*\n'))
      .where((s) => s.trim().isNotEmpty)
      .length;
  return 'Words: $words\n'
      'Characters: $chars\n'
      'Characters (no spaces): $charsNoSpace\n'
      'Sentences: $sentences\n'
      'Paragraphs: $paragraphs';
}

// ── Registration ─────────────────────────────────────────────────────────────

const _txtFiles = ['txt', 'md'];

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description, {
  List<ToolParam> params = const [],
  ToolCategory category = ToolCategory.write,
  List<String> accepts = _txtFiles,
  bool requiresInput = false,
}) => ToolMeta(
  id: id,
  category: category,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  requiresInput: requiresInput,
);

const _textParamDef = ToolParam(
  key: 'text',
  label: 'Your text',
  type: ToolParamType.text,
  multiline: true,
);

const _topicParamDef = ToolParam(
  key: 'text',
  label: 'Topic / brief',
  type: ToolParamType.text,
  multiline: true,
);

const _toneParam = ToolParam(
  key: 'tone',
  label: 'Tone (e.g. friendly, formal)',
  type: ToolParamType.text,
  defaultText: 'professional',
);

/// A rewriter-style tool: takes existing text.
_LlmTool _rewrite(String id, String label, String description,
        String instruction, {IconData icon = Icons.edit_note}) =>
    _LlmTool(
      _meta(id, label, icon, description, params: const [_textParamDef]),
      (text, p) => '$instruction\n\nText:\n$text',
    );

/// A generator-style tool: takes a topic/brief.
_LlmTool _generate(String id, String label, String description,
        String instruction, {IconData icon = Icons.auto_awesome}) =>
    _LlmTool(
      _meta(id, label, icon, description, params: const [_topicParamDef]),
      (text, p) => '$instruction\n\nTopic/brief:\n$text',
    );

/// Every LLM write tool (plus the two LLM PDF tools). The single registration
/// list for this block.
List<ToolModule> buildWriteTools() => [
  _rewrite('ai-detector', 'AI Content Detector',
      'Estimate how likely a text was machine-written (heuristic).',
      'You are an AI-text detector. Estimate the probability (0-100%) that the '
      'following text was written by an AI. Explain the 3 strongest signals. '
      'Start your answer with "AI likelihood: N%". This is a heuristic, not '
      'proof.',
      icon: Icons.radar),
  _rewrite('ai-rephraser', 'AI Rephraser',
      'Rephrase text while keeping its meaning.',
      'Rephrase the following text. Keep the meaning, change the wording. '
      'Return only the rephrased text.'),
  _generate('ai-twitter-generator', 'Tweet Generator',
      'Generate tweet options for a topic.',
      'Write 5 tweet options (max 280 chars each, numbered) about the topic. '
      'Punchy, no hashtag spam (max 2 hashtags each).',
      icon: Icons.tag),
  _generate('article-generator', 'Article Generator',
      'Generate a complete article on a topic.',
      'Write a well-structured ~700-word article with a title, subheadings, '
      'and a conclusion about the topic.'),
  _rewrite('article-rewriter', 'Article Rewriter',
      'Rewrite an article in fresh words.',
      'Rewrite this article completely: new sentence structures and wording, '
      'same facts and message, similar length. Return only the article.'),
  _generate('article-writer', 'Article Writer',
      'Draft an article from a brief.',
      'Draft an engaging article from this brief. Title, intro, 3-5 sections '
      'with subheadings, conclusion.'),
  _generate('bill-sale-generator', 'Bill of Sale Generator',
      'Draft a bill-of-sale template from the deal details.',
      'Draft a bill of sale from these details. Include seller/buyer blocks, '
      'item description, price, date, signatures. Add the note: '
      '"Template only — not legal advice."',
      icon: Icons.receipt_long),
  _generate('blog-outline', 'Blog Outline',
      'Outline a blog post for a topic.',
      'Create a detailed blog-post outline: working title, hook, H2/H3 '
      'section bullets, and a CTA idea.'),
  _generate('business-name-generator', 'Business Name Generator',
      'Suggest brandable business names.',
      'Suggest 12 brandable business names for this idea (numbered), each '
      'with a one-line rationale. Mix real words, blends, and coinages.',
      icon: Icons.storefront),
  _generate('business-plan-generator', 'Business Plan Generator',
      'Draft a lean business plan.',
      'Draft a lean business plan: problem, solution, market, competition, '
      'model, go-to-market, costs, 12-month milestones.'),
  _generate('business-slogan-generator', 'Slogan Generator',
      'Generate slogans for a brand.',
      'Write 10 short memorable slogans (numbered) for this brand/idea.'),
  _generate('cold-email-writer', 'Cold Email Writer',
      'Write a cold outreach email.',
      'Write a concise cold email (subject + ~120-word body + CTA) from this '
      'brief. Personable, no fluff.',
      icon: Icons.mail),
  _generate('content-brief-generator', 'Content Brief Generator',
      'Create an SEO content brief.',
      'Create a content brief: target query, search intent, working titles, '
      'H2/H3 outline, entities/terms to cover, FAQs, suggested length.'),
  _rewrite('content-improver', 'Content Improver',
      'Polish text for clarity and impact.',
      'Improve this text: clearer, tighter, more engaging. Keep the meaning '
      'and rough length. Return only the improved text.'),
  _generate('content-planner', 'Content Planner',
      'Plan a month of content.',
      'Create a 4-week content plan for this topic/brand: weekly themes and '
      '3 posts per week (format + working title + angle).'),
  _rewrite('content-summarizer', 'Content Summarizer',
      'Summarize long text into key points.',
      'Summarize the text: 1 headline takeaway, then 5 bullet key points, '
      'then a 2-sentence TL;DR.',
      icon: Icons.summarize),
  _generate('essay-writer', 'Essay Writer',
      'Write a structured essay.',
      'Write a ~600-word essay with a thesis, 3 supporting arguments with '
      'evidence-style reasoning, counterpoint, and conclusion.'),
  _rewrite('explain-like-five', 'Explain Like I\'m 5',
      'Explain anything in the simplest terms.',
      'Explain the following like I\'m five years old: simple words, one '
      'friendly analogy, no jargon.',
      icon: Icons.child_care),
  _generate('facebook-ad-headlines', 'Facebook Ad Headlines',
      'Generate ad headline variants.',
      'Write 10 Facebook ad headlines (numbered, under 40 chars each) plus 3 '
      'primary-text variants (under 125 chars) for this offer.'),
  _generate('faq-generator', 'FAQ Generator',
      'Generate FAQs for a product or topic.',
      'Generate 8 realistic FAQs with concise answers for this '
      'product/topic. Format: Q: … / A: …'),
  _rewrite('grammar-fixer', 'Grammar Fixer',
      'Fix grammar, spelling, and punctuation.',
      'Fix all grammar, spelling, and punctuation errors. Keep wording and '
      'style otherwise. Return only the corrected text.',
      icon: Icons.spellcheck),
  _rewrite('humanizer-ai', 'AI Text Humanizer',
      'Make AI-sounding text read naturally.',
      'Rewrite this so it reads like a thoughtful human wrote it: varied '
      'sentence rhythm, concrete phrasing, no filler or hedging clichés. '
      'Return only the rewritten text.'),
  _generate('instagram-caption-generator', 'Instagram Captions',
      'Generate Instagram captions.',
      'Write 6 Instagram captions (numbered) for this post idea: 2 short & '
      'punchy, 2 storytelling, 2 witty. Max 3 hashtags each.',
      icon: Icons.photo_camera),
  _generate('instagram-story-ideas', 'Instagram Story Ideas',
      'Brainstorm Instagram story ideas.',
      'Brainstorm 10 Instagram story ideas (numbered) for this brand/topic, '
      'each with a hook and an interaction sticker suggestion.',
      icon: Icons.photo_camera),
  _generate('landing-page-copy', 'Landing Page Copy',
      'Write landing page copy.',
      'Write landing-page copy: hero headline + subheadline, 3 benefit '
      'blocks, social-proof line, FAQ (3), and CTA button text.'),
  _generate('linkedin-post-generator', 'LinkedIn Post Generator',
      'Write a LinkedIn post.',
      'Write a LinkedIn post from this brief: strong hook line, short '
      'paragraphs, a concrete lesson, and a question to drive comments. '
      'No hashtags beyond 3.',
      icon: Icons.business_center),
  _generate('listicle-writer', 'Listicle Writer',
      'Write a listicle article.',
      'Write a listicle article: catchy title with a number, brief intro, '
      '7 items with 2-3 sentences each, wrap-up.'),
  _generate('meta-description-generator', 'Meta Descriptions',
      'Generate SEO meta descriptions.',
      'Write 5 meta descriptions (numbered, 140-155 characters each) for '
      'this page. Include the main keyword naturally and a soft CTA.'),
  _generate('nda-generator', 'NDA Generator',
      'Draft a mutual NDA template.',
      'Draft a mutual non-disclosure agreement template from these details: '
      'parties, purpose, definition of confidential info, exclusions, term, '
      'governing law placeholder, signatures. Add the note: '
      '"Template only — not legal advice."',
      icon: Icons.gavel),
  _rewrite('paragraph-completer', 'Paragraph Completer',
      'Continue a paragraph naturally.',
      'Continue this text with 3-5 sentences in the same voice and topic. '
      'Return only the continuation.'),
  _rewrite('paragraph-rewriter', 'Paragraph Rewriter',
      'Rewrite a paragraph.',
      'Rewrite this paragraph with fresh wording, same meaning and length. '
      'Return only the rewritten paragraph.'),
  _generate('paragraph-writer', 'Paragraph Writer',
      'Write a paragraph on a topic.',
      'Write one tight, informative paragraph (4-6 sentences) about the '
      'topic.'),
  _rewrite('paraphrasing', 'Paraphrasing Tool',
      'Paraphrase text.',
      'Paraphrase the text: different words and structure, identical '
      'meaning. Return only the paraphrase.'),
  _generate('podcast-writer', 'Podcast Script Writer',
      'Write a podcast episode script.',
      'Write a podcast episode script from this brief: cold-open hook, '
      'intro, 3 segments with talking points, listener question, outro.',
      icon: Icons.podcasts),
  _generate('poll-generator', 'Poll Generator',
      'Generate engaging poll questions.',
      'Create 6 engaging poll questions (numbered) about this topic, each '
      'with 3-4 answer options.'),
  _generate('post-generator', 'Social Post Generator',
      'Generate social media posts.',
      'Write 5 social posts (numbered) about this topic for a general '
      'audience: 2 informative, 2 conversational, 1 bold take.'),
  _generate('post-ideas', 'Post Ideas',
      'Brainstorm social post ideas.',
      'Brainstorm 15 social post ideas (numbered, one line each) for this '
      'topic/brand across formats (tips, stories, myths, behind-the-scenes).'),
  _rewrite('post-rewriter', 'Post Rewriter',
      'Rewrite a social post.',
      'Rewrite this social post 3 ways (numbered): shorter & punchier, '
      'story-led, and question-led.'),
  _generate('post-writer', 'Post Writer',
      'Write a social post from a brief.',
      'Write one polished social post from this brief: hook first line, '
      'clear value, natural CTA.'),
  _generate('press-release-generator', 'Press Release Generator',
      'Draft a press release.',
      'Draft a press release: headline, subheadline, dateline, lead '
      'paragraph (who/what/when/where/why), body with a quote placeholder, '
      'boilerplate, media contact block.'),
  _generate('privacy-policy-generator', 'Privacy Policy Generator',
      'Draft a privacy policy template.',
      'Draft a privacy-policy template for this app/site: data collected, '
      'purposes, storage, third parties, user rights, contact. Add the '
      'note: "Template only — not legal advice."',
      icon: Icons.policy),
  _generate('purchase-agreement-generator', 'Purchase Agreement',
      'Draft a purchase agreement template.',
      'Draft a purchase-agreement template from these details: parties, '
      'goods, price and payment, delivery, warranties, signatures. Add the '
      'note: "Template only — not legal advice."',
      icon: Icons.gavel),
  _generate('real-estate-description', 'Real Estate Description',
      'Write a property listing description.',
      'Write a compelling property listing (~150 words) from these details: '
      'lead feature first, lifestyle framing, specifics, viewing CTA.',
      icon: Icons.home_work),
  _rewrite('sentence-rewriter', 'Sentence Rewriter',
      'Rewrite a sentence multiple ways.',
      'Rewrite this sentence 5 ways (numbered), varying tone from formal to '
      'casual.'),
  _rewrite('shorten-content', 'Shorten Content',
      'Cut text length while keeping the message.',
      'Shorten this text by about half. Keep every essential point and the '
      'original tone. Return only the shortened text.',
      icon: Icons.compress),
  _generate('story-generator', 'Story Generator',
      'Write a short story.',
      'Write a ~500-word short story from this premise: clear arc, vivid '
      'but economical prose, satisfying ending.',
      icon: Icons.auto_stories),
  _rewrite('summarize-youtube', 'YouTube Summarizer',
      'Summarize a pasted video transcript.',
      'This is a video transcript. Summarize it: 1-line gist, 5-8 bullet '
      'takeaways with rough order, and who should watch.',
      icon: Icons.smart_display),
  _generate('tiktok-script-writer', 'TikTok Script Writer',
      'Write a short-video script.',
      'Write a 30-45 second TikTok script from this idea: 2-second hook, '
      'beats with on-screen text cues, loopable ending.',
      icon: Icons.movie_filter),
  _rewrite('title-rewriter', 'Title Rewriter',
      'Rewrite a title for more clicks.',
      'Rewrite this title 8 ways (numbered): clearer, more specific, more '
      'curiosity — without clickbait lies.'),
  _LlmTool(
    _meta('tone-of-voice', 'Tone Changer', Icons.record_voice_over,
        'Rewrite text in a chosen tone.',
        params: const [_textParamDef, _toneParam]),
    (text, p) => 'Rewrite the following text in a '
        '${_textParam(p, 'tone', 'professional')} tone. Keep the meaning. '
        'Return only the rewritten text.\n\nText:\n$text',
  ),
  _LlmTool(
    _meta('translate', 'Translate Text', Icons.translate,
        'Translate text to another language on-device.',
        params: const [
          _textParamDef,
          ToolParam(
              key: 'to',
              label: 'Target language',
              type: ToolParamType.text,
              defaultText: 'English'),
        ]),
    (text, p) => 'Translate the following text into '
        '${_textParam(p, 'to', 'English')}. Return only the translation.'
        '\n\nText:\n$text',
  ),
  _generate('trivia-generator', 'Trivia Generator',
      'Generate trivia questions.',
      'Create 10 trivia questions (numbered) about this topic with answers '
      'hidden after each as "Answer: …". Mix difficulties.',
      icon: Icons.quiz),
  _WordCounter(
    _meta('word-counter', 'Word Counter', Icons.onetwothree,
        'Count words, characters, sentences, and paragraphs.',
        params: const [_textParamDef]),
  ),
  _generate('youtube-script-writer', 'YouTube Script Writer',
      'Write a YouTube video script.',
      'Write a YouTube script from this brief: 15-second hook, intro, '
      'chaptered main content with B-roll cues, recap, CTA.',
      icon: Icons.smart_display),
  // ── LLM PDF tools (category: pdf) ─────────────────────────────────────────
  _LlmPdfTool(
    _meta('summarizer', 'Summarize PDF', Icons.summarize,
        'Summarize a PDF\'s text with the on-device model.',
        category: ToolCategory.pdf,
        accepts: const ['pdf'],
        requiresInput: true),
    (text, p) => 'Summarize this document: 1-line gist, then 5-8 bullet key '
        'points, then a short TL;DR.\n\nDocument:\n$text',
  ),
  _LlmPdfTool(
    _meta('translate', 'Translate PDF', Icons.translate,
        'Translate a PDF\'s text to another language on-device.',
        category: ToolCategory.pdf,
        accepts: const ['pdf'],
        requiresInput: true,
        params: const [
          ToolParam(
              key: 'to',
              label: 'Target language',
              type: ToolParamType.text,
              defaultText: 'English'),
        ]),
    (text, p) => 'Translate this document into '
        '${_textParam(p, 'to', 'English')}. Return only the translation.'
        '\n\nDocument:\n$text',
  ),
];
