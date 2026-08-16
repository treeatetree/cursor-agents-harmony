function HeroApp() {
  const [frame, setFrame] = React.useState('cover');
  const [page, setPage] = React.useState('inbox');
  const [filter, setFilter] = React.useState('all');
  const [themePref, setThemePref] = React.useState('light');
  const dark = themePref === 'dark';
  const split = frame === 'inner-l';
  const compact = frame === 'cover' || split;

  React.useEffect(() => {
    document.documentElement.setAttribute('data-theme', 'hero');
    document.documentElement.setAttribute('data-mode', dark ? 'dark' : 'light');
  }, [dark]);

  const inbox = (
    <InboxCover
      agents={window.AGENTS}
      filter={filter}
      onFilter={setFilter}
      onOpen={() => setPage('detail')}
      onNew={() => setPage('new')}
      onSettings={() => setPage('settings')}
      compact={compact}
      segmented
    />
  );

  let detail = inbox;
  if (page === 'new') {
    detail = <NewScreen onBack={() => setPage('inbox')} onSend={() => setPage('detail')} />;
  } else if (page === 'detail') {
    detail = <DetailScreen onBack={() => setPage('inbox')} />;
  } else if (page === 'settings') {
    detail = <SettingsScreen onBack={() => setPage('inbox')} mode={themePref} onMode={setThemePref} />;
  }

  return (
    <React.Fragment>
      <div id="app" data-theme="hero" data-mode={dark ? 'dark' : 'light'} data-frame={frame}>
        {split ? (
          <SplitShell
            master={inbox}
            detail={page === 'inbox' ? <DetailScreen onBack={() => setPage('inbox')} /> : detail}
          />
        ) : detail}
      </div>
      <div className="frame-dock">
        <button className={frame === 'cover' ? 'on' : ''} onClick={() => setFrame('cover')}>外屏竖 459×672</button>
        <button className={frame === 'inner-p' ? 'on' : ''} onClick={() => setFrame('inner-p')}>内屏竖 664×939</button>
        <button className={frame === 'inner-l' ? 'on' : ''} onClick={() => { setFrame('inner-l'); setPage('detail'); }}>内屏横 939×664</button>
      </div>
    </React.Fragment>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<HeroApp />);
