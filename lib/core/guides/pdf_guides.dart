/// PDF tool guides: model-facing hints for reasoning & routing.
library;

import 'package:anvil/core/tool_guide.dart';

/// Guides for PDF tools. Each maps ToolMeta.qualifiedId → ToolGuide.
const pdfToolGuides = <String, ToolGuide>{
  'pdf/sign': ToolGuide(
    'Use for: sign, e-sign, add my signature or initials. Pass the PDF as document and an '
    'attached signature image as signature; with none the user draws and places it by hand. '
    'Set page if asked.',
    keywords: ['signature', 'autograph', 'esign', 'initials', 'countersign'],
  ),
  'pdf/add-images': ToolGuide(
    'Use for: put a logo, stamp or picture onto an existing PDF. Pass the PDF as document '
    'and the attached picture as image; with no picture attached the user picks and places '
    'one by hand.',
    keywords: ['logo', 'stamp', 'overlay'],
  ),
  'pdf/crop': ToolGuide(
    'Use for: trim or cut away page margins or borders of a PDF. The user sets the margins '
    'by hand in the editor.',
    keywords: ['trim', 'margins', 'margin', 'borders'],
  ),
  'pdf/edit': ToolGuide(
    'Use for: highlight, draw, black out or redact, add shapes or notes anywhere on a PDF. '
    'The user does it by hand in the editor. Not for: one line of text - use pdf_add_text.',
    keywords: ['highlight', 'redact', 'annotate', 'draw', 'markup', 'blackout'],
  ),
  'pdf/remove-watermark': ToolGuide(
    'Use for: erase a watermark, stamp or logo that sits in the same spot on every page. '
    'The user marks the area by hand in the editor.',
    keywords: ['erase', 'logo', 'draft', 'confidential'],
  ),
  'pdf/compress': ToolGuide(
    'Use for: make a PDF smaller, reduce its size for email or upload. method optimize '
    'keeps selectable text; raster is smallest but turns pages into images.',
    keywords: ['reduce', 'email', 'upload', 'lighter'],
  ),
  'pdf/photo-caption': ToolGuide(
    'Use for: make a new PDF from one photo, optionally with a name or caption below it. '
    'Put the caption text in caption. Not for: stamping onto an existing PDF - use pdf_add_images.',
    keywords: ['create', 'image', 'below', 'label', 'insert', 'place'],
  ),
  'pdf/to-csv': ToolGuide(
    'Use for: extract text from a PDF and format as CSV rows, one per paragraph, split on '
    'wide gaps.',
    keywords: ['table', 'tables', 'spreadsheet', 'excel', 'rows'],
  ),
  'pdf/summarizer': ToolGuide(
    'Use for: summarize a PDF or give its key points or gist, using the on-device model. '
    'Not for: the full text - use pdf_extract_text.',
    keywords: ['summary', 'summarize', 'gist', 'tldr', 'overview', 'points'],
  ),
  'pdf/translate': ToolGuide(
    'Use for: translate the text of a PDF into another language. Put the target language '
    'in to, e.g. Spanish; default English.',
    keywords: ['language', 'spanish', 'french', 'hindi', 'english', 'german'],
  ),
  'pdf/add-pages': ToolGuide(
    'Use for: append blank pages to the end of a PDF. Set count (1-100) from the request. '
    'Not for: joining another PDF on - use pdf_merge.',
    keywords: ['blank', 'append', 'empty', 'extra'],
  ),
  'pdf/add-text': ToolGuide(
    'Use for: write a line of text such as a name, date or note on a PDF page. Put it in text; '
    'page 0 = every page. Not for: repeated text over every page - use pdf_watermark.',
    keywords: ['write', 'type', 'words', 'heading', 'date', 'name'],
  ),
  'pdf/create': ToolGuide(
    'Use for: a new blank PDF from scratch. Set pages (1-50) and size a4 or letter. '
    'Not for: a PDF built from a photo - use pdf_photo_caption.',
    keywords: ['new', 'blank', 'scratch', 'empty', 'a4', 'letter'],
  ),
  'pdf/delete': ToolGuide(
    'Use for: remove some pages from a PDF. Put the page numbers in pages, e.g. 2,4-6. '
    'Not for: cutting a PDF into several files - use pdf_split.',
    keywords: ['page', 'drop', 'discard', 'erase'],
  ),
  'pdf/extract-img': ToolGuide(
    'Use for: save the pictures embedded inside a PDF as separate image files. '
    'Not for: turning whole pages into images - use pdf_to_png.',
    keywords: ['images', 'pictures', 'photos', 'embedded', 'save'],
  ),
  'pdf/extract-text': ToolGuide(
    'Use for: get or copy the selectable text out of a PDF; shows it on screen and saves a .txt. '
    'Scanned PDFs have no text. Not for: tables - use pdf_to_csv.',
    keywords: ['get', 'copy', 'read', 'out', 'contents'],
  ),
  'pdf/from-gif': ToolGuide(
    'Use for: put one or more GIF images into one PDF, one image per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['images', 'convert', 'combine'],
  ),
  'pdf/from-heic': ToolGuide(
    'Use for: put one or more iPhone HEIC photos into one PDF, one photo per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['iphone', 'photos', 'convert', 'combine'],
  ),
  'pdf/from-jpg': ToolGuide(
    'Use for: put one or more JPG photos or scans into one PDF, one image per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['photos', 'scans', 'convert', 'combine'],
  ),
  'pdf/from-png': ToolGuide(
    'Use for: put one or more PNG images or screenshots into one PDF, one image per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['screenshots', 'images', 'convert', 'combine'],
  ),
  'pdf/from-tiff': ToolGuide(
    'Use for: put one or more TIFF images or scans into one PDF, one image per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['scans', 'convert', 'combine'],
  ),
  'pdf/from-url': ToolGuide(
    'Use for: save a web page as a PDF. Put the address in url; no file needed.',
    keywords: ['website', 'webpage', 'web', 'link', 'site', 'save'],
  ),
  'pdf/from-webp': ToolGuide(
    'Use for: put one or more WebP images into one PDF, one image per page. '
    'Not for: one photo with a caption - use pdf_photo_caption.',
    keywords: ['images', 'convert', 'combine'],
  ),
  'pdf/merge': ToolGuide(
    'Use for: join two or more PDF files into one document, in the order given. '
    'Not for: adding blank pages - use pdf_add_pages.',
    keywords: ['combine', 'join', 'together', 'pdfs', 'one'],
  ),
  'pdf/protect': ToolGuide(
    'Use for: lock or encrypt a PDF with a password. Put the password from the request in password.',
    keywords: ['password', 'encrypt', 'lock', 'secure'],
  ),
  'pdf/rearrange': ToolGuide(
    'Use for: reorder or move PDF pages. Put the new order in order, e.g. 3,1,2; pages left '
    'out are dropped.',
    keywords: ['reorder', 'order', 'move', 'swap', 'sort'],
  ),
  'pdf/rotate': ToolGuide(
    'Use for: turn every page of a PDF sideways or upside down. Set degrees to 90, 180 or 270.',
    keywords: ['sideways', 'landscape', 'portrait', 'upside', 'degrees'],
  ),
  'pdf/split': ToolGuide(
    'Use for: cut a PDF into several smaller PDFs. Set every to the pages per file '
    '(1 = separate pages). Not for: removing pages - use pdf_delete.',
    keywords: ['separate', 'cut', 'break', 'divide'],
  ),
  'pdf/to-jpg': ToolGuide(
    'Use for: save each PDF page as a JPG image. Not for: pictures inside the PDF '
    '- use pdf_extract_img.',
    keywords: ['jpeg', 'image', 'photo', 'convert'],
  ),
  'pdf/to-png': ToolGuide(
    'Use for: save each PDF page as a PNG image. Not for: pictures inside the PDF '
    '- use pdf_extract_img.',
    keywords: ['image', 'screenshot', 'convert'],
  ),
  'pdf/to-text': ToolGuide(
    'Use for: convert a PDF into a plain .txt file of its selectable text. '
    'Not for: tables - use pdf_to_csv.',
    keywords: ['txt', 'plain', 'convert'],
  ),
  'pdf/to-tiff': ToolGuide(
    'Use for: save each PDF page as a TIFF image. Not for: pictures inside the PDF '
    '- use pdf_extract_img.',
    keywords: ['tif', 'image', 'convert'],
  ),
  'pdf/unlock': ToolGuide(
    'Use for: remove the password from a PDF. Needs the current password in password; '
    'ask the user if it is not given.',
    keywords: ['password', 'decrypt', 'remove', 'open'],
  ),
  'pdf/watermark': ToolGuide(
    'Use for: repeat a text like DRAFT or CONFIDENTIAL across every page. Put it in text. '
    'Not for: one line at a spot - use pdf_add_text.',
    keywords: ['draft', 'confidential', 'copy', 'sample'],
  ),
};
