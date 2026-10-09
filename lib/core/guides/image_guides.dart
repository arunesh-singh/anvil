/// Image tool guides: model-facing hints for reasoning & routing.
library;

import 'package:anvil/core/tool_guide.dart';

/// Guides for image tools: native, convert, and ML variants.
const imageToolGuides = <String, ToolGuide>{
  'image/add-images': ToolGuide(
    'Use for: put a logo, sticker or second picture on top of a photo. The user places it '
    'by hand in the editor. Not for: PDFs - use pdf_add_images.',
    keywords: ['logo', 'sticker', 'overlay', 'superimpose'],
  ),
  'image/flip': ToolGuide(
    'Use for: mirror or flip a photo. direction horizontal mirrors left-right; vertical '
    'turns it upside down.',
    keywords: ['mirror', 'upside'],
  ),
  'image/upscale': ToolGuide(
    'Use for: enlarge a photo up to 4× with on-device super-resolution.',
    keywords: ['bigger', 'enlarge', 'sharper', 'resolution', 'hd'],
  ),
  'image/blur-background': ToolGuide(
    'Use for: blur the background, portrait or bokeh effect keeping the subject '
    'sharp. blurRadius sets the strength.',
    keywords: ['bokeh', 'portrait', 'backdrop'],
  ),
  'image/border': ToolGuide(
    'Use for: frame a photo, add an outline or edge. sizePx is the border thickness; '
    'color is a hex like #FF0000.',
    keywords: ['frame', 'outline', 'edge'],
  ),
  'image/change-bg-photo': ToolGuide(
    'Use for: replace the background with a solid colour, white backdrop for ID '
    'photos. color is a hex like #FFFFFFFF.',
    keywords: ['backdrop', 'replace', 'background', 'passport'],
  ),
  'image/chart-maker': ToolGuide(
    'Use for: draw a bar chart or graph from a CSV of label,value rows. width and '
    'height in pixels.',
    keywords: ['bar', 'graph', 'plot'],
  ),
  'image/cleanup-picture': ToolGuide(
    'Use for: clean a blemish, spot or distraction from a photo. Needs the region in '
    'pixels; if the user gave none, ask in plain text.',
    keywords: ['blemish', 'spot', 'distraction', 'clean'],
  ),
  'image/collage-maker': ToolGuide(
    'Use for: arrange several photos in a grid, photo collage. columns sets the grid '
    'width. Not for: one strip side by side - use image_combine_maker.',
    keywords: ['grid', 'mosaic'],
  ),
  'image/colorize-photo': ToolGuide(
    'Use for: add colour to a black-and-white or old photo with an on-device model.',
    keywords: ['colour', 'old', 'vintage'],
  ),
  'image/combine-maker': ToolGuide(
    'Use for: join or stitch photos side by side into one picture. columns 0 keeps '
    'them in one row.',
    keywords: ['stitch', 'together', 'sidebyside'],
  ),
  'image/compress': ToolGuide(
    'Use for: reduce file size, make a photo lighter for upload. quality 0-100, '
    'lower is smaller. Not for: changing pixel dimensions - use image_resize.',
    keywords: ['size', 'kb', 'mb', 'lighter', 'reduce'],
  ),
  'image/crop': ToolGuide(
    'Use for: trim or cut a rectangle out of a photo. Needs the rectangle as x, y, '
    'width, height in pixels; if the user gave none, ask in plain text.',
    keywords: ['trim', 'cutout', 'rectangle'],
  ),
  'image/crop-circle': ToolGuide(
    'Use for: round or circular cutout of a photo, transparent corners. Output is '
    'PNG.',
    keywords: ['round', 'circular', 'avatar'],
  ),
  'image/font-to-png': ToolGuide(
    'Use for: preview a TTF/OTF font as a specimen sheet image.',
    keywords: ['typeface', 'specimen', 'preview'],
  ),
  'image/gif-to-apng': ToolGuide(
    'Use for: convert an animated GIF to animated PNG (APNG).',
    keywords: ['animated'],
  ),
  'image/gif-to-avif': ToolGuide(
    'Use for: convert a GIF to AVIF, animation kept.',
    keywords: ['animated'],
  ),
  'image/gif-to-jpg': ToolGuide(
    'Use for: save a GIF\'s first frame as JPG.',
    keywords: ['frame', 'jpeg'],
  ),
  'image/gif-to-png': ToolGuide(
    'Use for: save a GIF\'s first frame as PNG.',
    keywords: ['frame'],
  ),
  'image/grayscale': ToolGuide(
    'Use for: black and white, monochrome, remove colour from a photo.',
    keywords: ['black', 'white', 'monochrome', 'greyscale'],
  ),
  'image/heic-to-avif': ToolGuide(
    'Use for: convert an iPhone HEIC/HEIF photo to AVIF.',
    keywords: ['iphone'],
  ),
  'image/heic-to-jpg': ToolGuide(
    'Use for: convert an iPhone HEIC/HEIF photo to JPG. quality 0-100.',
    keywords: ['iphone', 'jpeg'],
  ),
  'image/heic-to-png': ToolGuide(
    'Use for: convert an iPhone HEIC/HEIF photo to PNG.',
    keywords: ['iphone'],
  ),
  'image/identify': ToolGuide(
    'Use for: what is in this photo, recognize objects, scene or food; returns '
    'labels. Not for: reading text - use image_to_text.',
    keywords: ['what', 'recognize', 'object', 'label', 'food'],
  ),
  'image/jpg-to-avif': ToolGuide('Use for: convert a JPG/JPEG to AVIF.'),
  'image/jpg-to-gif': ToolGuide('Use for: convert a JPG/JPEG to GIF.'),
  'image/jpg-to-png': ToolGuide('Use for: convert a JPG/JPEG photo to PNG.'),
  'image/jpg-to-svg': ToolGuide(
    'Use for: wrap a JPG in an SVG file; the bitmap is embedded, not traced.',
    keywords: ['vector'],
  ),
  'image/jpg-to-tiff': ToolGuide(
    'Use for: convert a JPG/JPEG to TIFF.',
    keywords: ['tif'],
  ),
  'image/jpg-to-webp': ToolGuide(
    'Use for: convert a JPG/JPEG photo to WebP. quality 0-100.',
  ),
  'image/make-background-transparent': ToolGuide(
    'Use for: transparent background, cut out the subject onto alpha. Output is PNG.',
    keywords: ['alpha', 'cutout'],
  ),
  'image/metadata': ToolGuide(
    'Use for: view a photo\'s EXIF data and save a copy with it stripped, e.g. remove '
    'location or camera info.',
    keywords: ['exif', 'gps', 'location', 'strip', 'privacy'],
  ),
  'image/pixelate': ToolGuide(
    'Use for: pixelate or mosaic a whole photo, censor look. blockSize sets the '
    'square size in pixels. Not for: soft blur behind a subject - use '
    'image_blur_background.',
    keywords: ['censor', 'faces', 'pixels'],
  ),
  'image/png-to-avif': ToolGuide('Use for: convert a PNG to AVIF.'),
  'image/png-to-eps': ToolGuide(
    'Use for: convert a PNG to EPS (PostScript) for print.',
    keywords: ['postscript', 'print'],
  ),
  'image/png-to-gif': ToolGuide('Use for: convert a PNG to GIF.'),
  'image/png-to-jpg': ToolGuide(
    'Use for: convert a PNG to JPG/JPEG. quality 0-100.',
    keywords: ['jpeg'],
  ),
  'image/png-to-svg': ToolGuide(
    'Use for: wrap a PNG in an SVG file; the bitmap is embedded, not traced.',
    keywords: ['vector'],
  ),
  'image/png-to-tiff': ToolGuide(
    'Use for: convert a PNG to TIFF.',
    keywords: ['tif'],
  ),
  'image/png-to-webp': ToolGuide(
    'Use for: convert a PNG to WebP. quality 0-100.',
  ),
  'image/profile-photo': ToolGuide(
    'Use for: profile picture or avatar, subject cut out on a round coloured disc. '
    'color is the disc hex like #FFE5E7EB.',
    keywords: ['avatar', 'dp', 'headshot'],
  ),
  'image/psd-to-ai': ToolGuide(
    'Use for: convert a Photoshop PSD to an Illustrator .ai file (PDF-based, '
    'flattened).',
    keywords: ['photoshop', 'illustrator'],
  ),
  'image/psd-to-jpg': ToolGuide(
    'Use for: convert a Photoshop PSD to JPG.',
    keywords: ['photoshop', 'jpeg'],
  ),
  'image/psd-to-pdf': ToolGuide(
    'Use for: convert a Photoshop PSD to a single-page PDF.',
    keywords: ['photoshop'],
  ),
  'image/psd-to-png': ToolGuide(
    'Use for: convert a Photoshop PSD to PNG.',
    keywords: ['photoshop'],
  ),
  'image/psd-to-svg': ToolGuide(
    'Use for: wrap a Photoshop PSD in an SVG file; the bitmap is embedded, not '
    'traced.',
    keywords: ['photoshop', 'vector'],
  ),
  'image/remove-bg': ToolGuide(
    'Use for: remove or erase the background, cut out the subject. Output is a '
    'transparent PNG. Not for: erasing an object - use image_remove_objects.',
    keywords: ['background', 'cut', 'erase', 'cutout'],
  ),
  'image/remove-objects': ToolGuide(
    'Use for: erase an unwanted object and fill the gap. Needs the region in pixels; '
    'if the user gave none, ask in plain text. Not for: the background - use '
    'image_remove_bg.',
    keywords: ['erase', 'unwanted', 'object', 'inpaint'],
  ),
  'image/remove-person': ToolGuide(
    'Use for: erase the main person from a photo automatically and fill the gap.',
    keywords: ['people', 'human', 'photobomber'],
  ),
  'image/remove-text-photo': ToolGuide(
    'Use for: erase words, captions or writing from a photo; text is found '
    'automatically.',
    keywords: ['words', 'caption', 'writing', 'erase'],
  ),
  'image/remove-watermark-photo': ToolGuide(
    'Use for: erase a watermark or logo stamp from a photo. Needs the region in '
    'pixels; if the user gave none, ask in plain text.',
    keywords: ['logo', 'stamp'],
  ),
  'image/repair-defects': ToolGuide(
    'Use for: fix scratches, tears or damage on an old photo. Needs the region in '
    'pixels; if the user gave none, ask in plain text.',
    keywords: ['scratch', 'damage', 'restore', 'old', 'fix'],
  ),
  'image/resize': ToolGuide(
    'Use for: change pixel dimensions, scale to a width or height. width and height '
    'in pixels; 0 keeps the aspect ratio. Not for: smaller file size - use '
    'image_compress.',
    keywords: ['dimensions', 'pixels', 'wide', 'tall', 'scale'],
  ),
  'image/sharpen': ToolGuide(
    'Use for: sharpen a soft or slightly out-of-focus photo with an on-device model.',
    keywords: ['crisp', 'soft', 'focus', 'clearer'],
  ),
  'image/split': ToolGuide(
    'Use for: cut a photo into a grid of tiles, e.g. an Instagram grid. rows and '
    'cols set the tile count.',
    keywords: ['tiles', 'grid', 'slice', 'pieces'],
  ),
  'image/svg-to-png': ToolGuide(
    'Use for: rasterize an SVG vector to PNG. width in pixels; 0 keeps the intrinsic '
    'size.',
    keywords: ['rasterize', 'vector'],
  ),
  'image/text-image-generator': ToolGuide(
    'Use for: make a quote card or shareable text graphic. text is the words; '
    'background and color are hex.',
    keywords: ['quote', 'card', 'graphic'],
  ),
  'image/text-to-image': ToolGuide(
    'Use for: render plain text onto a picture. text is the words; fontSize, color '
    'and background (hex) style it.',
    keywords: ['render', 'words', 'typography'],
  ),
  'image/tiff-to-jpg': ToolGuide(
    'Use for: convert a TIFF/TIF to JPG.',
    keywords: ['jpeg'],
  ),
  'image/tiff-to-png': ToolGuide('Use for: convert a TIFF/TIF to PNG.'),
  'image/tiff-to-svg': ToolGuide(
    'Use for: wrap a TIFF in an SVG file; the bitmap is embedded, not traced.',
    keywords: ['vector'],
  ),
  'image/tiff-to-text': ToolGuide(
    'Use for: read or extract text from a TIFF scan (OCR).',
    keywords: ['ocr', 'scan', 'extract', 'read'],
  ),
  'image/to-text': ToolGuide(
    'Use for: read or extract text from a photo or screenshot (OCR). Not for: naming '
    'objects - use image_identify.',
    keywords: ['ocr', 'read', 'extract', 'screenshot', 'copy'],
  ),
  'image/translate': ToolGuide(
    'Use for: translate the text in a photo or sign. from and to are language codes '
    'like es, en; from is required.',
    keywords: ['language', 'sign', 'menu', 'spanish', 'english'],
  ),
  'image/unblur': ToolGuide(
    'Use for: fix a blurry or motion-blurred photo with an on-device model. Not for: '
    'making it bigger - use image_upscale.',
    keywords: ['blurry', 'deblur', 'shaky', 'clear'],
  ),
  'image/webp-to-avif': ToolGuide('Use for: convert a WebP to AVIF.'),
  'image/webp-to-gif': ToolGuide(
    'Use for: convert a WebP to GIF, animation kept.',
    keywords: ['animated'],
  ),
  'image/webp-to-jpg': ToolGuide(
    'Use for: convert a WebP to JPG/JPEG. quality 0-100.',
    keywords: ['jpeg'],
  ),
  'image/webp-to-png': ToolGuide('Use for: convert a WebP to PNG.'),
};
