const { TopAppBar, IconButton, ListTile } = window.AnvilDesignSystem_296c7d;

function HistoryScreen({ onBack, onOpen }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--md-surface)' }}>
      <TopAppBar title="My Files" onBack={onBack} actions={<IconButton icon="refresh" label="Refresh" />} />
      <div style={{ flex: 1, overflowY: 'auto' }}>
        {window.ANVIL_HISTORY.map((r) => (
          <ListTile
            key={r.at}
            leadingIcon={r.icon}
            title={r.label}
            subtitle={r.inputs.join(', ') + '\n' + r.at}
            lines={3}
            onClick={() => onOpen(r)}
          />
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { HistoryScreen });
