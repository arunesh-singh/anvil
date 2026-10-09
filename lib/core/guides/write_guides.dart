/// Write tool guides: generation, composition, code.
library;

import 'package:anvil/core/tool_guide.dart';

const _t = "Put the user's text in `text`.";
const _b = "Put the user's topic or brief in `text`.";

/// Write guides, keyed by `ToolMeta.qualifiedId`.
const writeToolGuides = <String, ToolGuide>{
  'write/ai-detector': ToolGuide(
    'Use for: was this written by ai, check if chatgpt wrote this, '
    'detect machine text. $_t',
    keywords: ['chatgpt', 'gpt', 'machine', 'plagiarism', 'written'],
  ),
  'write/ai-rephraser': ToolGuide(
    'Use for: rephrase this, say this differently, reword this. $_t '
    'Not for: a new tone like formal - use write_tone_of_voice.',
    keywords: ['reword', 'differently', 'wording'],
  ),
  'write/ai-twitter-generator': ToolGuide(
    'Use for: write a tweet, tweet ideas about, x post. $_b',
    keywords: ['tweet', 'tweets', 'thread'],
  ),
  'write/article-generator': ToolGuide(
    'Use for: write an article about, generate a full article on a topic. '
    '$_b Not for: drafting from a detailed brief - use write_article_writer.',
    keywords: ['700', 'longform'],
  ),
  'write/article-rewriter': ToolGuide(
    'Use for: rewrite my article, spin this article, reword this whole '
    'article. $_t',
    keywords: ['spin', 'spinner', 'unique'],
  ),
  'write/article-writer': ToolGuide(
    'Use for: draft an article from my brief, article from these notes. '
    '$_b Not for: just a topic - use write_article_generator.',
    keywords: ['draft', 'notes'],
  ),
  'write/bill-sale-generator': ToolGuide(
    'Use for: bill of sale, sale receipt for a car, sold item paperwork. '
    'Put the seller, buyer, item, price and date in `text`.',
    keywords: ['seller', 'buyer', 'vehicle', 'car', 'sold'],
  ),
  'write/blog-outline': ToolGuide(
    'Use for: outline a blog post, blog structure, headings for a blog. $_b',
    keywords: ['headings', 'structure', 'h2'],
  ),
  'write/business-name-generator': ToolGuide(
    'Use for: name my business, company name ideas, startup name, brand '
    'name. $_b',
    keywords: ['company', 'startup', 'brand', 'naming', 'shop'],
  ),
  'write/business-plan-generator': ToolGuide(
    'Use for: business plan, startup plan, plan for my company. $_b',
    keywords: ['startup', 'market', 'milestones', 'strategy'],
  ),
  'write/business-slogan-generator': ToolGuide(
    'Use for: slogan for my brand, tagline, catchphrase, motto. $_b',
    keywords: ['tagline', 'catchphrase', 'motto', 'jingle'],
  ),
  'write/cold-email-writer': ToolGuide(
    'Use for: cold email, outreach email, sales email to a prospect. $_b',
    keywords: ['outreach', 'mail', 'prospect', 'sales', 'pitch'],
  ),
  'write/content-brief-generator': ToolGuide(
    'Use for: seo content brief, brief for a writer, keyword brief. $_b',
    keywords: ['seo', 'intent', 'keyword', 'query'],
  ),
  'write/content-improver': ToolGuide(
    'Use for: improve my writing, polish this, make this better, make it '
    'clearer. $_t Not for: only typos - use write_grammar_fixer.',
    keywords: ['polish', 'improve', 'better', 'clearer', 'enhance'],
  ),
  'write/content-planner': ToolGuide(
    'Use for: content calendar, plan a month of posts, posting schedule. $_b',
    keywords: ['calendar', 'schedule', 'month', 'weekly'],
  ),
  'write/content-summarizer': ToolGuide(
    'Use for: summarize this, tldr, key points of this text. $_t '
    'Not for: a pdf file - use pdf_summarizer.',
    keywords: ['summary', 'summarise', 'tldr', 'gist', 'recap'],
  ),
  'write/essay-writer': ToolGuide(
    'Use for: write an essay on, school essay, argumentative essay. $_b',
    keywords: ['school', 'thesis', 'argumentative', 'homework'],
  ),
  'write/explain-like-five': ToolGuide(
    'Use for: explain like im five, explain simply, eli5, in simple terms. '
    "Put the user's text or question in `text`.",
    keywords: ['eli5', 'simply', 'simple', 'kid', 'beginner'],
  ),
  'write/facebook-ad-headlines': ToolGuide(
    'Use for: facebook ad copy, fb ad headlines, ad text for my offer. $_b',
    keywords: ['fb', 'meta', 'advert', 'advertising', 'campaign'],
  ),
  'write/faq-generator': ToolGuide(
    'Use for: write faqs, questions and answers for my product, q and a. $_b',
    keywords: ['faqs', 'questions', 'answers', 'qa'],
  ),
  'write/grammar-fixer': ToolGuide(
    'Use for: fix grammar, correct spelling, proofread this, fix typos. $_t',
    keywords: ['spelling', 'proofread', 'typos', 'punctuation', 'correct'],
  ),
  'write/humanizer-ai': ToolGuide(
    'Use for: humanize ai text, make it sound human, less robotic. $_t',
    keywords: ['humanize', 'humanise', 'human', 'robotic', 'natural'],
  ),
  'write/instagram-caption-generator': ToolGuide(
    'Use for: instagram caption, ig caption for my photo, insta caption. $_b',
    keywords: ['ig', 'insta', 'captions', 'hashtags'],
  ),
  'write/instagram-story-ideas': ToolGuide(
    'Use for: instagram story ideas, ig stories, what to post on my story. '
    '$_b',
    keywords: ['ig', 'insta', 'stories', 'sticker'],
  ),
  'write/landing-page-copy': ToolGuide(
    'Use for: landing page text, website hero copy, homepage copy. $_b',
    keywords: ['website', 'homepage', 'hero', 'copywriting', 'cta'],
  ),
  'write/linkedin-post-generator': ToolGuide(
    'Use for: linkedin post, professional network post, post for linkedin. '
    '$_b',
    keywords: ['professional', 'network', 'career'],
  ),
  'write/listicle-writer': ToolGuide(
    'Use for: listicle, top 7 list article, numbered list post. $_b',
    keywords: ['numbered', 'ranking', 'roundup'],
  ),
  'write/meta-description-generator': ToolGuide(
    'Use for: meta description, seo description for my page, search '
    'snippet. $_b',
    keywords: ['seo', 'snippet', 'serp', 'google'],
  ),
  'write/nda-generator': ToolGuide(
    'Use for: nda, non disclosure agreement, confidentiality agreement. '
    'Put the parties and purpose in `text`.',
    keywords: ['confidentiality', 'confidential', 'disclosure', 'contract'],
  ),
  'write/paragraph-completer': ToolGuide(
    'Use for: finish this paragraph, continue my text, what comes next. $_t',
    keywords: ['continue', 'finish', 'continuation'],
  ),
  'write/paragraph-rewriter': ToolGuide(
    'Use for: rewrite this paragraph, reword this paragraph. $_t '
    'Not for: a single sentence - use write_sentence_rewriter.',
    keywords: ['reword', 'fresh'],
  ),
  'write/paragraph-writer': ToolGuide(
    'Use for: write a paragraph about, short paragraph on a topic. $_b',
    keywords: ['short', 'informative'],
  ),
  'write/paraphrasing': ToolGuide(
    'Use for: paraphrase this, put it in other words, paraphraser. $_t',
    keywords: ['paraphrase', 'paraphraser', 'synonyms', 'quillbot'],
  ),
  'write/podcast-writer': ToolGuide(
    'Use for: podcast script, episode outline, script for my podcast. $_b',
    keywords: ['episode', 'show', 'host'],
  ),
  'write/poll-generator': ToolGuide(
    'Use for: poll questions, survey questions, vote options. $_b',
    keywords: ['survey', 'vote', 'voting', 'options'],
  ),
  'write/post-generator': ToolGuide(
    'Use for: social media posts about, write posts for my page. $_b '
    'Not for: linkedin - use write_linkedin_post_generator.',
    keywords: ['social', 'posts', 'socials'],
  ),
  'write/post-ideas': ToolGuide(
    'Use for: what should i post, post ideas, brainstorm content ideas. $_b',
    keywords: ['brainstorm', 'inspiration', 'topics'],
  ),
  'write/post-rewriter': ToolGuide(
    'Use for: rewrite my social post, improve my caption, punchier post. $_t',
    keywords: ['punchier', 'social'],
  ),
  'write/post-writer': ToolGuide(
    'Use for: write one social post from my notes, single post from a '
    'brief. $_b',
    keywords: ['social', 'single'],
  ),
  'write/press-release-generator': ToolGuide(
    'Use for: press release, media announcement, news release. $_b',
    keywords: ['announcement', 'news', 'pr'],
  ),
  'write/privacy-policy-generator': ToolGuide(
    'Use for: privacy policy for my app, gdpr policy, data policy. '
    'Put the app or site details in `text`.',
    keywords: ['gdpr', 'legal', 'terms', 'data'],
  ),
  'write/purchase-agreement-generator': ToolGuide(
    'Use for: purchase agreement, sales contract, buying contract. '
    'Put the parties, goods and price in `text`.',
    keywords: ['contract', 'buyer', 'seller', 'goods', 'buying'],
  ),
  'write/real-estate-description': ToolGuide(
    'Use for: property listing, house listing description, apartment ad. '
    'Put the property details in `text`.',
    keywords: ['property', 'house', 'listing', 'apartment', 'realtor'],
  ),
  'write/sentence-rewriter': ToolGuide(
    'Use for: rewrite this sentence, other ways to say this line. $_t',
    keywords: ['ways', 'variations'],
  ),
  'write/shorten-content': ToolGuide(
    'Use for: shorten this, make it shorter, cut this down, trim my text. '
    '$_t Not for: bullet key points - use write_content_summarizer.',
    keywords: ['shorter', 'condense', 'concise'],
  ),
  'write/story-generator': ToolGuide(
    'Use for: write a story, short story about, bedtime story. '
    "Put the user's premise in `text`.",
    keywords: ['fiction', 'bedtime', 'tale', 'narrative'],
  ),
  'write/summarize-youtube': ToolGuide(
    'Use for: summarize this video transcript, youtube transcript summary. '
    'Put the pasted transcript in `text`; it cannot fetch a link.',
    keywords: ['transcript', 'transcription'],
  ),
  'write/tiktok-script-writer': ToolGuide(
    'Use for: tiktok script, reel script, short video script. $_b',
    keywords: ['reel', 'reels', 'shorts'],
  ),
  'write/title-rewriter': ToolGuide(
    'Use for: better title, rewrite my headline, catchier title. $_t',
    keywords: ['headline', 'headlines', 'catchier', 'clickable'],
  ),
  'write/tone-of-voice': ToolGuide(
    "Use for: make this more formal, friendlier tone, sound professional. "
    "Put the user's text in `text`; set `tone` from words like formal, "
    'casual, friendly.',
    keywords: ['formal', 'casual', 'friendly', 'polite', 'professional'],
  ),
  'write/translate': ToolGuide(
    "Use for: translate to spanish, in french please, what is this in "
    "hindi. Put the user's text in `text`; set `to` to the target language. "
    'Not for: a pdf - use pdf_translate.',
    keywords: [
      'spanish',
      'french',
      'hindi',
      'german',
      'language',
      'translation',
    ],
  ),
  'write/word-counter': ToolGuide(
    'Use for: count words, how many characters, word count. $_t',
    keywords: ['count', 'characters', 'chars', 'length', 'sentences'],
  ),
  'write/trivia-generator': ToolGuide(
    'Use for: trivia questions, quiz about a topic, pub quiz. $_b',
    keywords: ['quiz', 'questions', 'pub'],
  ),
  'write/youtube-script-writer': ToolGuide(
    'Use for: youtube video script, script for my channel. $_b '
    'Not for: summarizing a transcript - use write_summarize_youtube.',
    keywords: ['channel', 'vlog', 'youtuber'],
  ),
};
