const { TopAppBar, IconButton, TextField, ToolTile, Banner, Button } = window.AnvilDesignSystem_296c7d;

function CategorySection({ title, tools, onOpen }) {
  if (!tools.length) return null;
  return (
    <>
      <div style={{ padding: '16px 4px 8px', font: 'var(--title-small)', letterSpacing: 'var(--title-small-tracking)' }}>{title}</div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--grid-gutter)' }}>
        {tools.map((t) => <ToolTile key={t.id} icon={t.icon} label={t.label} onClick={() => onOpen(t)} />)}
      </div>
    </>
  );
}

function HomeScreen({ onOpenTool, onOpenHistory, onOpenSettings, shared, onDismissShared }) {
  const [q, setQ] = React.useState('');
  const query = q.trim().toLowerCase();
  const tools = query
    ? window.ANVIL_TOOLS.filter((t) => t.label.toLowerCase().includes(query) || t.desc.toLowerCase().includes(query))
    : window.ANVIL_TOOLS;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--md-surface)' }}>
      <TopAppBar
        title="Anvil"
        actions={<>
          <IconButton icon="history" label="History" onClick={onOpenHistory} />
          <IconButton icon="settings" label="Settings" onClick={onOpenSettings} />
        </>}
      />
      {shared ? (
        <Banner icon="attach_file" actions={<Button variant="text" onClick={onDismissShared}>Dismiss</Button>}>
          {'Shared file ready: ' + shared + ' — pick a tool'}
        </Banner>
      ) : null}
      <div style={{ padding: 'var(--list-padding)' }}>
        <TextField hint="Search tools" prefixIcon="search" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '0 var(--list-padding) 16px' }}>
        {tools.length === 0 ? (
          <div style={{ padding: '48px 0', textAlign: 'center', font: 'var(--body-large)', color: 'var(--md-on-surface)' }}>No tools match.</div>
        ) : (
          window.ANVIL_CATEGORIES.map((c) => (
            <CategorySection key={c} title={c} tools={tools.filter((t) => t.cat === c)} onOpen={onOpenTool} />
          ))
        )}
      </div>
    </div>
  );
}

Object.assign(window, { HomeScreen });
