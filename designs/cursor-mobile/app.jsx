function App() {
  const startSys = document.documentElement.getAttribute('data-sys') || 'now';
  const params = new URLSearchParams(location.search);
  const [page, setPage] = React.useState(params.get('p') || 'inbox');
  const [filter, setFilter] = React.useState('all');
  const [frame, setFrame] = React.useState(params.get('f') || 'cover');
  const [sys, setSys] = React.useState(startSys);
  const [detailPhase, setDetailPhase] = React.useState(params.get('phase') || 'done');
  const [activeId, setActiveId] = React.useState(params.get('id') || (params.get('phase') === 'live' ? '3' : '1'));
  const [prefs, setPrefs] = React.useState({ mode: 'light', type: 'default', density: 'comfortable', autoPr: true, haptics: true });
  const split = frame === 'inner-l';
  const compact = frame !== 'inner-p';
  const locked = document.documentElement.getAttribute('data-lock-sys') === '1';

  React.useEffect(() => {
    document.documentElement.setAttribute('data-theme', 'app');
    document.documentElement.setAttribute('data-sys', sys);
    document.documentElement.setAttribute('data-mode', prefs.mode);
    document.documentElement.setAttribute('data-type', prefs.type);
    document.documentElement.setAttribute('data-density', prefs.density);
  }, [sys, prefs]);

  const inbox = (
    <InboxCover
      sys={sys}
      agents={window.AGENTS}
      filter={filter}
      onFilter={setFilter}
      compact={compact}
      list={split}
      activeId={activeId}
      onOpen={(a) => {
        setActiveId(a.id);
        setDetailPhase(a.running || a.status === 'run' ? 'live' : a.status === 'err' ? 'err' : 'done');
        setPage('detail');
      }}
      onNew={() => setPage('new')}
      onSettings={() => setPage('settings')}
    />
  );

  const stack = (
    page === 'inbox' ? inbox
      : page === 'new' ? <NewScreen sys={sys} prefs={prefs} onPrefs={setPrefs} onBack={() => setPage('inbox')} onSend={() => { setActiveId('3'); setDetailPhase('live'); setPage('detail'); }} />
      : page === 'detail' ? <DetailScreen sys={sys} onBack={() => setPage('inbox')} phase={detailPhase} agent={(window.AGENTS || []).find((a) => a.id === activeId)} onFixKey={() => setPage('settings')} />
      : <SettingsScreen sys={sys} onBack={() => setPage('inbox')} prefs={prefs} onPrefs={setPrefs} />
  );

  const detailPane = (
    page === 'new' ? <NewScreen sys={sys} prefs={prefs} onPrefs={setPrefs} onBack={() => setPage('inbox')} onSend={() => { setActiveId('3'); setDetailPhase('live'); setPage('detail'); }} />
      : page === 'settings' ? <SettingsScreen sys={sys} onBack={() => setPage('inbox')} prefs={prefs} onPrefs={setPrefs} />
      : <DetailScreen sys={sys} hideBack phase={detailPhase} agent={(window.AGENTS || []).find((a) => a.id === activeId)} onFixKey={() => setPage('settings')} />
  );

  return (
    <div>
      <div
        id="app"
        data-theme="app"
        data-sys={sys}
        data-mode={prefs.mode}
        data-type={prefs.type}
        data-density={prefs.density}
        data-frame={frame}
      >
        {split ? <SplitShell master={inbox} detail={detailPane} /> : stack}
      </div>
      <div className="frame-dock" role="toolbar" aria-label="预览">
        {locked ? null : (
          <span>
            <button className={sys === 'now' ? 'on' : ''} onClick={() => setSys('now')}>Now</button>
            <button className={sys === 'hero' ? 'on' : ''} onClick={() => setSys('hero')}>Hero</button>
            <button className={sys === 'be' ? 'on' : ''} onClick={() => setSys('be')}>beUI</button>
          </span>
        )}
        <button className={frame === 'cover' ? 'on' : ''} onClick={() => setFrame('cover')}>外屏竖</button>
        <button className={frame === 'inner-p' ? 'on' : ''} onClick={() => setFrame('inner-p')}>内屏竖</button>
        <button className={frame === 'inner-l' ? 'on' : ''} onClick={() => setFrame('inner-l')}>内屏横</button>
        <button className={prefs.mode === 'dark' ? 'on' : ''} onClick={() => setPrefs(Object.assign({}, prefs, { mode: prefs.mode === 'dark' ? 'light' : 'dark' }))}>{prefs.mode === 'dark' ? '深色' : '浅色'}</button>
        <button className={prefs.type === 'large' ? 'on' : ''} onClick={() => setPrefs(Object.assign({}, prefs, { type: prefs.type === 'large' ? 'default' : 'large' }))}>{prefs.type === 'large' ? '大字' : '标准'}</button>
        <button className={prefs.density === 'compact' ? 'on' : ''} onClick={() => setPrefs(Object.assign({}, prefs, { density: prefs.density === 'compact' ? 'comfortable' : 'compact' }))}>{prefs.density === 'compact' ? '紧凑' : '舒适'}</button>
      </div>
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
