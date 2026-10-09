// Sample slice of Anvil's tool registry — labels, icons, descriptions and
// params copied verbatim from lib/tools/**/​*.dart (ToolMeta / ToolParam).
window.ANVIL_TOOLS = [
  { id:'converter/csv-to-json', cat:'Converters', label:'CSV to JSON', icon:'data_object', desc:'Convert a CSV file into a JSON array of objects.', accepts:['csv'], params:[] },
  { id:'converter/csv-to-excel', cat:'Converters', label:'CSV to Excel', icon:'table_chart', desc:'Convert a CSV file into an Excel (.xlsx) spreadsheet.', accepts:['csv'], params:[] },
  { id:'converter/csv-to-xml', cat:'Converters', label:'CSV to XML', icon:'code', desc:'Convert a CSV file into an XML table.', accepts:['csv'], params:[] },
  { id:'converter/xml-to-csv', cat:'Converters', label:'XML to CSV', icon:'grid_on', desc:'Convert an XML table into a CSV file.', accepts:['xml'], params:[] },

  { id:'pdf/merge', cat:'PDF', label:'Merge PDFs', icon:'merge', desc:'Combine several PDF files into one document.', accepts:['pdf'], multi:true, params:[] },
  { id:'pdf/split', cat:'PDF', label:'Split PDF', icon:'call_split', desc:'Split a PDF into smaller files by page count.', accepts:['pdf'], params:[{key:'every',label:'Pages per file',value:'5'}] },
  { id:'pdf/compress', cat:'PDF', label:'Compress PDF', icon:'compress', desc:'Shrink a PDF by optimizing its images.', accepts:['pdf'], params:[{key:'imageQuality',label:'Image quality (1-100)',value:'75'}] },
  { id:'pdf/protect', cat:'PDF', label:'Protect PDF', icon:'lock', desc:'Encrypt a PDF with a password (AES-256).', accepts:['pdf'], params:[{key:'password',label:'Password',value:''}] },
  { id:'pdf/watermark', cat:'PDF', label:'Watermark PDF', icon:'branding_watermark', desc:'Tile a text watermark across every page.', accepts:['pdf'], params:[{key:'text',label:'Watermark text',value:'CONFIDENTIAL'}] },
  { id:'pdf/sign', cat:'PDF', label:'Sign PDF', icon:'draw', desc:'Stamp a signature image onto a page of a PDF.', accepts:['pdf','png','jpg'], params:[] },
  { id:'pdf/extract-text', cat:'PDF', label:'Extract Text', icon:'text_snippet', desc:'Extract selectable text from a PDF.', accepts:['pdf'], params:[] },
  { id:'pdf/from-url', cat:'PDF', label:'Website to PDF', icon:'public', desc:'Render a web page into a PDF.', accepts:[], requiresInput:false, params:[{key:'url',label:'Page URL',value:''}] },

  { id:'image/compress', cat:'Image', label:'Compress Image', icon:'compress', desc:"Shrink an image's file size with lossy re-encoding.", accepts:['png','jpg','webp'], params:[{key:'quality',label:'Quality (0-100)',value:'75'}] },
  { id:'image/crop-circle', cat:'Image', label:'Circle Crop', icon:'panorama_fish_eye', desc:'Crop an image into a circle with a transparent background.', accepts:['png','jpg'], params:[] },
  { id:'image/collage-maker', cat:'Image', label:'Collage Maker', icon:'dashboard', desc:'Arrange several images into a grid collage.', accepts:['png','jpg'], multi:true, params:[{key:'columns',label:'Columns',value:'2'}] },
  { id:'image/border', cat:'Image', label:'Add Border', icon:'border_outer', desc:'Add a solid color border around an image.', accepts:['png','jpg'], params:[{key:'sizePx',label:'Border size (px)',value:'16'},{key:'color',label:'Color (hex, e.g. #FF0000)',value:'#FF000000'}] },

  { id:'video/cutter', cat:'Video', label:'Video Cutter', icon:'content_cut', desc:'Cut a clip out of a video without re-encoding.', accepts:['mp4','mov','mkv'], params:[{key:'start',label:'Start (seconds)',value:'0'},{key:'duration',label:'Duration (seconds)',value:'10'}] },
  { id:'video/mp4-to-gif', cat:'Video', label:'MP4 to GIF', icon:'gif', desc:'Turn an MP4 video into an animated GIF.', accepts:['mp4'], params:[{key:'fps',label:'Frames per second',value:'12'},{key:'width',label:'Width (px)',value:'480'}] },
  { id:'video/extract-audio', cat:'Video', label:'Extract Audio', icon:'music_note', desc:"Extract a video's audio track as an MP3.", accepts:['mp4','mov'], params:[] },
  { id:'video/mute', cat:'Video', label:'Mute Video', icon:'volume_off', desc:'Remove the audio track from a video (no re-encode).', accepts:['mp4','mov'], params:[] },

  { id:'write/word-count', cat:'Write', label:'Word Counter', icon:'numbers', desc:'Count words, characters, sentences and paragraphs.', accepts:['txt'], requiresInput:false, params:[{key:'text',label:'Text',value:''}] },
  { id:'write/summarize', cat:'Write', label:'Summarize PDF', icon:'summarize', desc:'Summarize a PDF with the on-device model.', accepts:['pdf'], params:[] },
];

window.ANVIL_CATEGORIES = ['Converters','PDF','Image','Video','Write'];

window.ANVIL_HISTORY = [
  { toolId:'pdf/split', label:'Split PDF', icon:'call_split', inputs:['quarterly_report.pdf'], at:'2026-08-04 14:02', outputs:['quarterly_report_1.pdf','quarterly_report_2.pdf'] },
  { toolId:'image/compress', label:'Compress Image', icon:'compress', inputs:['IMG_4471.jpg'], at:'2026-08-03 09:18', outputs:['IMG_4471.jpg'] },
  { toolId:'converter/csv-to-json', label:'CSV to JSON', icon:'data_object', inputs:['orders_july.csv'], at:'2026-08-01 21:44', outputs:['orders_july.json'] },
  { toolId:'video/extract-audio', label:'Extract Audio', icon:'music_note', inputs:['lecture_03.mp4'], at:'2026-07-29 11:05', outputs:['lecture_03.mp3'] },
];
