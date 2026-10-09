const { HomeScreen, ToolScreen, ResultScreen, HistoryScreen, SettingsScreen } = window;

function outputsFor(tool, file) {
  const base = (file || 'document').replace(/\.[^.]+$/, '');
  switch (tool.id) {
    case 'pdf/split': return { files: [base + '_1.pdf', base + '_2.pdf', base + '_3.pdf'] };
    case 'converter/csv-to-json': return { files: [base + '.json'] };
    case 'converter/csv-to-excel': return { files: [base + '.xlsx'] };
    case 'pdf/extract-text': return { files: [base + '.txt'], text: 'Q2 revenue grew 14% quarter over quarter…' };
    case 'video/extract-audio': return { files: [base + '.mp3'] };
    case 'video/mp4-to-gif': return { files: [base + '.gif'] };
    case 'write/word-count': return { files: [], text: 'Words: 1284\nCharacters: 7910\nCharacters (no spaces): 6702\nSentences: 71\nParagraphs: 12' };
    default: return { files: [base + '.' + (tool.accepts[0] || 'pdf')] };
  }
}

function App() {
  const [stack, setStack] = React.useState([{ screen: 'home' }]);
  const [mode, setMode] = React.useState('light');
  const [shared, setShared] = React.useState('invoice.pdf');
  const top = stack[stack.length - 1];
  const push = (s) => setStack((st) => [...st, s]);
  const pop = () => setStack((st) => (st.length > 1 ? st.slice(0, -1) : st));
  const home = () => setStack([{ screen: 'home' }]);

  const dark = mode === 'dark';

  return (
    <div data-theme={dark ? 'dark' : undefined} style={{ height: '100%', background: 'var(--md-surface)', color: 'var(--md-on-surface)' }}>
      {top.screen === 'home' && (
        <HomeScreen
          shared={shared}
          onDismissShared={() => setShared(null)}
          onOpenTool={(t) => push({ screen: 'tool', tool: t, file: shared && t.accepts.includes(shared.split('.').pop()) ? shared : null })}
          onOpenHistory={() => push({ screen: 'history' })}
          onOpenSettings={() => push({ screen: 'settings' })}
        />
      )}
      {top.screen === 'tool' && (
        <ToolScreen
          tool={top.tool}
          preselected={top.file}
          onBack={pop}
          onDone={(tool, file) => { const out = outputsFor(tool, file); setStack((st) => [...st.slice(0, -1), { screen: 'result', ...out }]); }}
        />
      )}
      {top.screen === 'result' && <ResultScreen files={top.files} text={top.text} onBack={pop} onHome={home} />}
      {top.screen === 'history' && (
        <HistoryScreen onBack={pop} onOpen={(r) => push({ screen: 'result', files: r.outputs })} />
      )}
      {top.screen === 'settings' && <SettingsScreen onBack={pop} mode={mode} onMode={setMode} />}
    </div>
  );
}

Object.assign(window, { App });
