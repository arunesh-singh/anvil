const { TopAppBar, RadioTile } = window.AnvilDesignSystem_296c7d;

function SettingsScreen({ onBack, mode, onMode }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--md-surface)' }}>
      <TopAppBar title="Settings" onBack={onBack} />
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ padding: '16px 16px 8px', font: 'var(--body-large)', letterSpacing: 'var(--body-large-tracking)' }}>Theme</div>
        {[['System', 'system'], ['Light', 'light'], ['Dark', 'dark']].map(([l, v]) => (
          <RadioTile key={v} label={l} value={v} selected={mode === v} onSelect={onMode} />
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { SettingsScreen });
