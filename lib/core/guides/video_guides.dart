/// Video tool guides: transcoding, trimming, composition.
library;

import 'package:anvil/core/tool_guide.dart';

/// Model-facing guides for video/audio tools, keyed by qualified id.
const videoToolGuides = <String, ToolGuide>{
  'video/aac-to-flac': ToolGuide(
    'Use for: AAC to FLAC, convert AAC audio to FLAC.',
    keywords: ['lossless'],
  ),
  'video/aac-to-m4r': ToolGuide(
    'Use for: AAC to M4R, make an iPhone ringtone from an AAC file.',
    keywords: ['ringtone', 'iphone'],
  ),
  'video/aac-to-mp3': ToolGuide(
    'Use for: AAC to MP3, convert AAC audio to MP3.',
  ),
  'video/aac-to-mp4': ToolGuide(
    'Use for: AAC to MP4, wrap AAC audio in an MP4 container without re-encoding. Not for: video files - use video_mov_to_mp4.',
    keywords: ['container', 'rewrap'],
  ),
  'video/aac-to-wav': ToolGuide(
    'Use for: AAC to WAV, convert AAC audio to WAV.',
  ),
  'video/add-subtitles': ToolGuide(
    'Use for: add subtitles, make captions, SRT file from speech. Outputs an .srt file; it does not burn text into the video. Not for: plain text - use video_audio_to_text.',
    keywords: ['srt', 'captions', 'cc'],
  ),
  'video/audio-to-text': ToolGuide(
    'Use for: transcribe speech, speech to text, transcript of a recording. Not for: timestamps - use video_transcribe_podcast.',
    keywords: ['speech', 'dictation', 'voice', 'recording'],
  ),
  'video/avi-to-gif': ToolGuide(
    'Use for: AVI to GIF, animated GIF from a AVI. Set `fps` and `width` (px) only if the user gives them. Not for: animated WebP - use video_to_webp.',
    keywords: ['animated', 'meme', 'animation'],
  ),
  'video/avi-to-mkv': ToolGuide(
    'Use for: AVI to MKV, change a AVI video\'s format to MKV. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/avi-to-mov': ToolGuide(
    'Use for: AVI to MOV, change a AVI video\'s format to MOV. Not for: animated GIFs - use video_to_gif.',
    keywords: ['iphone', 'quicktime'],
  ),
  'video/avi-to-mp3': ToolGuide(
    'Use for: AVI to MP3, save the audio of a AVI as MP3. Not for: removing the sound - use video_mute.',
  ),
  'video/avi-to-mp4': ToolGuide(
    'Use for: AVI to MP4, change a AVI video\'s format to MP4. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/compress': ToolGuide(
    'Use for: compress a video, reduce video size, smaller for WhatsApp or email. Set `height` (px, default 720) and `quality` (1 best - 31 smallest) only if given. Not for: exact width and height - use video_resize.',
    keywords: ['size', 'reduce', 'mb', 'whatsapp', 'email', 'lighter'],
  ),
  'video/compress-avi': ToolGuide(
    'Use for: compress a AVI, reduce AVI size. Set `height` (px, default 720) and `quality` (1 best - 31 smallest) only if given. Not for: other formats - use video_compress.',
    keywords: ['size', 'reduce', 'mb'],
  ),
  'video/compress-mkv': ToolGuide(
    'Use for: compress a MKV, reduce MKV size. Set `height` (px, default 720) and `quality` (1 best - 31 smallest) only if given. Not for: other formats - use video_compress.',
    keywords: ['size', 'reduce', 'mb'],
  ),
  'video/compress-mov': ToolGuide(
    'Use for: compress a MOV, reduce MOV size. Set `height` (px, default 720) and `quality` (1 best - 31 smallest) only if given. Not for: other formats - use video_compress.',
    keywords: ['size', 'reduce', 'mb'],
  ),
  'video/cutter': ToolGuide(
    'Use for: trim a video, cut a clip, keep part of a video. Set `start` and `duration` in seconds from the user\'s times. Not for: removing the sound - use video_mute.',
    keywords: ['trim', 'clip', 'shorten', 'snippet', 'excerpt'],
  ),
  'video/extract-audio': ToolGuide(
    'Use for: extract audio, save the music of a video as MP3. Not for: a silent video - use video_mute.',
    keywords: ['music', 'soundtrack'],
  ),
  'video/gif-to-mov': ToolGuide(
    'Use for: GIF to MOV, turn an animated GIF into a MOV video.',
  ),
  'video/gif-to-webm': ToolGuide(
    'Use for: GIF to WEBM, turn an animated GIF into a WEBM video.',
  ),
  'video/m4a-to-mp3': ToolGuide(
    'Use for: M4A to MP3, convert M4A audio to MP3.',
  ),
  'video/m4a-to-mp4': ToolGuide(
    'Use for: M4A to MP4, wrap M4A audio in an MP4 container without re-encoding. Not for: video files - use video_mov_to_mp4.',
    keywords: ['container', 'rewrap'],
  ),
  'video/m4a-to-wav': ToolGuide(
    'Use for: M4A to WAV, convert M4A audio to WAV.',
  ),
  'video/mkv-to-avi': ToolGuide(
    'Use for: MKV to AVI, change a MKV video\'s format to AVI. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mkv-to-gif': ToolGuide(
    'Use for: MKV to GIF, animated GIF from a MKV. Set `fps` and `width` (px) only if the user gives them. Not for: animated WebP - use video_to_webp.',
    keywords: ['animated', 'meme', 'animation'],
  ),
  'video/mkv-to-mov': ToolGuide(
    'Use for: MKV to MOV, change a MKV video\'s format to MOV. Not for: animated GIFs - use video_to_gif.',
    keywords: ['iphone', 'quicktime'],
  ),
  'video/mkv-to-mp3': ToolGuide(
    'Use for: MKV to MP3, save the audio of a MKV as MP3. Not for: removing the sound - use video_mute.',
  ),
  'video/mkv-to-mp4': ToolGuide(
    'Use for: MKV to MP4, change a MKV video\'s format to MP4. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mov-to-avi': ToolGuide(
    'Use for: MOV to AVI, change a MOV video\'s format to AVI. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mov-to-gif': ToolGuide(
    'Use for: MOV to GIF, animated GIF from a MOV. Set `fps` and `width` (px) only if the user gives them. Not for: animated WebP - use video_to_webp.',
    keywords: ['animated', 'meme', 'animation'],
  ),
  'video/mov-to-mp3': ToolGuide(
    'Use for: MOV to MP3, save the audio of a MOV as MP3. Not for: removing the sound - use video_mute.',
  ),
  'video/mov-to-mp4': ToolGuide(
    'Use for: MOV to MP4, change a MOV video\'s format to MP4. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mov-to-wav': ToolGuide(
    'Use for: MOV to WAV, save the audio of a MOV as WAV. Not for: removing the sound - use video_mute.',
  ),
  'video/mp4-to-avi': ToolGuide(
    'Use for: MP4 to AVI, change a MP4 video\'s format to AVI. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mp4-to-gif': ToolGuide(
    'Use for: MP4 to GIF, animated GIF from a MP4. Set `fps` and `width` (px) only if the user gives them. Not for: animated WebP - use video_to_webp.',
    keywords: ['animated', 'meme', 'animation'],
  ),
  'video/mp4-to-mov': ToolGuide(
    'Use for: MP4 to MOV, change a MP4 video\'s format to MOV. Not for: animated GIFs - use video_to_gif.',
    keywords: ['iphone', 'quicktime'],
  ),
  'video/mp4-to-mp3': ToolGuide(
    'Use for: MP4 to MP3, save the audio of a MP4 as MP3. Not for: removing the sound - use video_mute.',
  ),
  'video/mp4-to-ogg': ToolGuide(
    'Use for: MP4 to OGG, save the audio of a MP4 as OGG. Not for: removing the sound - use video_mute.',
  ),
  'video/mp4-to-wav': ToolGuide(
    'Use for: MP4 to WAV, save the audio of a MP4 as WAV. Not for: removing the sound - use video_mute.',
  ),
  'video/mp4-to-webm': ToolGuide(
    'Use for: MP4 to WEBM, change a MP4 video\'s format to WEBM. Not for: animated GIFs - use video_to_gif.',
  ),
  'video/mute': ToolGuide(
    'Use for: remove sound, silent video, drop the audio track. Not for: keeping only the audio - use video_extract_audio.',
    keywords: ['sound', 'silent', 'silence', 'noise', 'volume'],
  ),
  'video/ogg-to-mp3': ToolGuide(
    'Use for: OGG to MP3, convert OGG audio to MP3.',
  ),
  'video/ogg-to-wav': ToolGuide(
    'Use for: OGG to WAV, convert OGG audio to WAV.',
  ),
  'video/resize': ToolGuide(
    'Use for: resize a video, exact width and height, 1080p or 720p. Set `width` and `height` (px) from the user\'s words. Not for: making the file smaller - use video_compress.',
    keywords: ['dimensions', 'resolution', 'scale', '1080p', '720p', 'aspect'],
  ),
  'video/summarize-podcast': ToolGuide(
    'Use for: summarize a podcast, recording, lecture or meeting audio. Not for: full transcript - use video_transcribe_podcast.',
    keywords: ['summary', 'tldr', 'lecture', 'meeting', 'recap'],
  ),
  'video/to-gif': ToolGuide(
    'Use for: video to GIF, make an animated GIF or meme clip. Set `fps` and `width` (px) only if the user gives them. Not for: animated WebP - use video_to_webp.',
    keywords: ['animated', 'meme', 'animation'],
  ),
  'video/to-text': ToolGuide(
    'Use for: read on-screen text from a video, OCR a video. Not for: spoken words - use video_audio_to_text.',
    keywords: ['ocr', 'onscreen', 'frames'],
  ),
  'video/to-webp': ToolGuide(
    'Use for: video to WebP, animated WebP sticker. Set `fps` and `width` (px) only if the user gives them. Not for: GIF output - use video_to_gif.',
    keywords: ['sticker', 'animated'],
  ),
  'video/transcribe-podcast': ToolGuide(
    'Use for: transcript with timestamps, podcast or interview transcript. Not for: subtitles - use video_add_subtitles.',
    keywords: ['timestamps', 'interview', 'timestamped', 'episode'],
  ),
  'video/webm-to-mov': ToolGuide(
    'Use for: WEBM to MOV, change a WEBM video\'s format to MOV. Not for: animated GIFs - use video_to_gif.',
    keywords: ['iphone', 'quicktime'],
  ),
  'video/webm-to-mp3': ToolGuide(
    'Use for: WEBM to MP3, save the audio of a WEBM as MP3. Not for: removing the sound - use video_mute.',
  ),
  'video/webm-to-mp4': ToolGuide(
    'Use for: WEBM to MP4, change a WEBM video\'s format to MP4. Not for: animated GIFs - use video_to_gif.',
  ),
};
