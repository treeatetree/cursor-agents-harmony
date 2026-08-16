const ICONS = {
  back: 'M14.5 5.5 8 12l6.5 6.5',
  plus: 'M12 6v12M6 12h12',
  send: 'M12 18V6m0 0 5 5M12 6 7 11',
  search: 'M11 18a7 7 0 1 1 0-14 7 7 0 0 1 0 14Zm9-2-3.8-3.8',
  stop: 'M8 8h8v8H8z'
};

function Icon({ name }) {
  if (name === 'more') {
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <circle cx="6" cy="12" r="1.7" />
        <circle cx="12" cy="12" r="1.7" />
        <circle cx="18" cy="12" r="1.7" />
      </svg>
    );
  }
  if (name === 'settings') {
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <rect x="3" y="5.15" width="18" height="2.2" rx="1.1" />
        <rect x="3" y="10.9" width="18" height="2.2" rx="1.1" />
        <rect x="3" y="16.65" width="18" height="2.2" rx="1.1" />
        <circle cx="9" cy="6.25" r="2.55" />
        <circle cx="15.2" cy="12" r="2.55" />
        <circle cx="8.2" cy="17.75" r="2.55" />
      </svg>
    );
  }
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={ICONS[name]} />
    </svg>
  );
}

function shortRepo(name) {
  if (!name) return '';
  const i = name.lastIndexOf('/');
  return i >= 0 ? name.slice(i + 1) : name;
}

function statusMeta(s) {
  if (s === 'run') return { label: '运行中', color: 'var(--run)' };
  if (s === 'err') return { label: '失败', color: 'var(--err)' };
  if (s === 'done') return { label: '已完成', color: 'var(--ink3)' };
  return { label: '', color: 'var(--ink3)' };
}

function cardLine(a) {
  if (a.running && a.step) return a.step;
  if (a.outcome) return a.outcome;
  return '';
}

function urgency(a) {
  if (a.running || a.status === 'run') return 0;
  if (a.status === 'err') return 1;
  if (a.pr) return 2;
  return 3;
}

function parseSecs(label) {
  if (!label) return 0;
  const m = label.match(/(\d+)m/);
  const s = label.match(/(\d+)s/);
  return (m ? parseInt(m[1], 10) * 60 : 0) + (s ? parseInt(s[1], 10) : 0);
}

function fmtSecs(n) {
  const m = Math.floor(n / 60);
  const s = n % 60;
  if (m <= 0) return s + 's';
  return m + 'm ' + (s < 10 ? '0' + s : s) + 's';
}

function useTick(start, on) {
  const [n, setN] = React.useState(start);
  React.useEffect(() => {
    if (!on) return undefined;
    const id = window.setInterval(() => setN((x) => x + 1), 1000);
    return () => window.clearInterval(id);
  }, [on]);
  return n;
}

function knownRepos() {
  const seen = {};
  const out = [];
  (window.AGENTS || []).forEach((a) => {
    if (a.repo && !seen[a.repo]) {
      seen[a.repo] = true;
      out.push(a.repo);
    }
  });
  return out;
}

function AgentCardView({ a, list, sys, active }) {
  const st = statusMeta(a.status);
  const line = cardLine(a);
  const seed = parseSecs(a.time);
  const secs = useTick(seed, sys === 'be' && a.running);
  const time = sys === 'be' && a.running ? fmtSecs(secs) : a.time;
  const be = sys === 'be';
  const showLine = line && !(be && list);
  let mark = st.label;
  if (be) {
    if (a.running) mark = '';
    else if (a.status === 'done' && a.pr) mark = '';
  }
  return (
    <button
      className={list ? 'row' : 'card'}
      data-running={a.running ? '1' : '0'}
      data-err={a.status === 'err' ? '1' : '0'}
      data-on={active ? '1' : '0'}
      onClick={() => a.onOpen && a.onOpen(a)}
    >
      <div className="card-top">
        <div className="card-title">{a.title}</div>
      </div>
      {showLine ? <div className="card-sub">{line}</div> : null}
      <div className="card-foot">
        {mark ? <span className="st" style={{ color: st.color }}>{mark}</span> : null}
        {a.pr ? <span className="pr">{a.prLabel || 'PR'}</span> : null}
        <span className="time" style={a.running ? { color: 'var(--run)' } : undefined}>{time}</span>
      </div>
    </button>
  );
}

function InboxCover({ agents, onOpen, onNew, onSettings, filter, onFilter, staticFit, compact, list, sys, activeId }) {
  const [find, setFind] = React.useState(false);
  const [q, setQ] = React.useState('');
  const be = sys === 'be';
  let shown = (agents || []).filter((a) => {
    if (filter && filter !== 'all' && a.status !== filter) return false;
    if (!q.trim()) return true;
    const hay = (a.title + ' ' + (a.outcome || '') + ' ' + (a.step || '')).toLowerCase();
    return hay.indexOf(q.trim().toLowerCase()) >= 0;
  });
  if (be) shown = shown.slice().sort((x, y) => urgency(x) - urgency(y));
  const groups = [];
  const map = {};
  shown.forEach((a) => {
    if (!map[a.group]) {
      map[a.group] = { key: a.group, items: [] };
      groups.push(map[a.group]);
    }
    map[a.group].items.push(a);
  });
  if (be) {
    groups.sort((g, h) => {
      const ug = Math.min.apply(null, g.items.map(urgency));
      const uh = Math.min.apply(null, h.items.map(urgency));
      return ug - uh;
    });
  }
  const filters = list ? [
    { id: 'all', label: '全部' },
    { id: 'run', label: '运行' },
    { id: 'err', label: '失败' },
    { id: 'done', label: '完成' }
  ] : [
    { id: 'all', label: '全部' },
    { id: 'run', label: '运行中' },
    { id: 'err', label: '失败' },
    { id: 'done', label: '已完成' }
  ];
  const idx = Math.max(0, filters.findIndex((f) => f.id === filter));
  const emptyHint = q ? '没有匹配的任务' : (
    filter === 'err' ? '没有失败的任务' :
    filter === 'run' ? '这一刻没有在跑的任务' :
    filter === 'done' ? '还没有完成的任务' :
    '还没有任务'
  );
  return (
    <div className="screen" data-screen-label="inbox">
      <div className="chrome">
        {find ? (
          <div className="search-bar">
            <input
              autoFocus
              value={q}
              placeholder="标题或结果"
              onChange={(e) => setQ(e.target.value)}
            />
            <button
              className="text-btn"
              type="button"
              onClick={() => { setFind(false); setQ(''); }}
            >取消</button>
          </div>
        ) : (
          <div className={be ? 'be-filters' : (sys === 'hero' ? 'filters track' : 'filters')}>
            {be ? <span className="be-pill" style={{ transform: 'translateX(' + (idx * 100) + '%)' }} /> : null}
            {filters.map((f) => (
              <button key={f.id} className={filter === f.id ? 'seg on' : 'seg'} onClick={() => onFilter && onFilter(f.id)}>{f.label}</button>
            ))}
          </div>
        )}
        {find ? null : (
          <div className="chrome-actions">
            {compact ? null : (
              <button className="icon-btn" aria-label="搜索" onClick={() => setFind(true)}><Icon name="search" /></button>
            )}
            <button className="icon-btn" onClick={onSettings} aria-label="设置">
              <Icon name={be ? 'settings' : 'more'} />
            </button>
            <button className={be ? 'plus round' : 'plus'} onClick={onNew} aria-label="新建"><Icon name="plus" /></button>
          </div>
        )}
      </div>
      <div className={staticFit ? 'inbox-scroll fit' : 'inbox-scroll'}>
        {groups.length === 0 ? (
          <div className="empty">
            <div>{emptyHint}</div>
            {be && !q && filter === 'all' ? (
              <button className="text-btn empty-act" type="button" onClick={onNew}>派一个任务</button>
            ) : null}
          </div>
        ) : groups.map((g) => (
          <div key={g.key} className="group">
            <div className="group-h">{shortRepo(g.key)}</div>
            <div className={list ? 'list' : 'grid'}>
              {g.items.map((a) => (
                <AgentCardView
                  key={a.id}
                  list={list}
                  sys={sys}
                  active={list && activeId === a.id}
                  a={Object.assign({}, a, { onOpen: onOpen })}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PromptShell({ sys, fill, placeholder, value, onChange, onSend, ready, live, repo, onRepo, repos, autoPr, onAutoPr, simple }) {
  const [err, setErr] = React.useState(false);
  const [ok, setOk] = React.useState(false);
  const [more, setMore] = React.useState(false);
  const [pickRepo, setPickRepo] = React.useState(false);
  const [model] = React.useState('Composer');
  const ta = React.useRef(null);
  const be = sys === 'be';
  const grow = () => {
    const el = ta.current;
    if (!el || fill) return;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 160) + 'px';
  };
  React.useEffect(() => { grow(); }, [value]);
  const send = () => {
    if (!ready) {
      if (be) {
        setErr(true);
        window.setTimeout(() => setErr(false), 480);
      }
      return;
    }
    if (be) {
      setOk(true);
      window.setTimeout(() => {
        setOk(false);
        if (onSend) onSend();
      }, 360);
      return;
    }
    if (onSend) onSend();
  };
  return (
    <div className={'prompt-shell' + (fill ? ' fill' : '') + (err ? ' shake' : '')}>
      <textarea
        ref={ta}
        className={'prompt-ta' + (be && !fill ? ' auto' : '')}
        placeholder={placeholder}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            send();
          }
        }}
      />
      {be && pickRepo && !simple ? (
        <div className="be-actions">
          {(repos || []).map((r) => (
            <button
              key={r}
              className={r === repo ? 'chip on' : 'chip'}
              type="button"
              onClick={() => { if (onRepo) onRepo(r); setPickRepo(false); }}
            >{r}</button>
          ))}
        </div>
      ) : null}
      {be && more && !simple && !pickRepo ? (
        <div className="be-actions">
          <button className="chip on" type="button">{model}</button>
          <button className="chip" type="button">图片</button>
          <button
            className={autoPr ? 'chip on' : 'chip'}
            type="button"
            onClick={() => onAutoPr && onAutoPr(!autoPr)}
          >{autoPr ? '自动 PR' : '不开 PR'}</button>
        </div>
      ) : null}
      <div className="prompt-tools">
        {simple ? null : (repo ? (
          <button
            className="chip warn"
            type="button"
            onClick={() => { if (be && repos && repos.length > 1) { setPickRepo(!pickRepo); setMore(false); } }}
          >{repo}</button>
        ) : null)}
        {simple ? null : (
          <button
            className={more ? 'chip on' : 'chip'}
            type="button"
            onClick={() => { setMore(!more); setPickRepo(false); }}
          >更多</button>
        )}
        {live ? (
          <button className="send stop" aria-label="停止" style={{ marginLeft: 'auto' }} type="button"><Icon name="stop" /></button>
        ) : ok ? (
          <svg className="be-check" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
        ) : (
          <button className={ready ? 'send on' : 'send'} onClick={send} aria-label="发送" style={{ marginLeft: 'auto' }} type="button"><Icon name="send" /></button>
        )}
      </div>
    </div>
  );
}

function NewScreen({ onBack, onSend, sys, prefs, onPrefs }) {
  const [text, setText] = React.useState('');
  const [repo, setRepo] = React.useState('edit-DSH');
  const ready = text.trim().length > 0;
  const autoPr = !prefs || prefs.autoPr !== false;
  if (sys === 'hero' || sys === 'be') {
    return (
      <div className="screen" data-screen-label={'new-' + sys}>
        <div className="bar">
          <button className="icon-btn" onClick={onBack} aria-label="返回"><Icon name="back" /></button>
          <div className="bar-title">新任务</div>
        </div>
        {sys === 'hero' ? <div className="new-pad"><div className="dim">字写在壳里。工具条和发送同一块。</div></div> : null}
        <PromptShell
          sys={sys}
          fill={sys === 'be'}
          placeholder="要做什么？目标和约束"
          value={text}
          onChange={setText}
          onSend={onSend}
          ready={ready}
          repo={repo}
          onRepo={setRepo}
          repos={knownRepos()}
          autoPr={autoPr}
          onAutoPr={(v) => onPrefs && onPrefs(Object.assign({}, prefs || {}, { autoPr: v }))}
        />
      </div>
    );
  }
  return (
    <div className="screen" data-screen-label="new-now">
      <div className="bar">
        <button className="icon-btn" onClick={onBack} aria-label="返回"><Icon name="back" /></button>
        <div className="bar-title">新任务</div>
      </div>
      <textarea className="canvas" placeholder="要做什么？目标和约束写在这里" value={text} onChange={(e) => setText(e.target.value)} />
      <div className="composer">
        <button className="chip warn">edit-DSH</button>
        <button className="chip">更多</button>
        <div className="field">{ready ? '可以发送' : '仓库已选，补充即可发'}</div>
        <button className={ready ? 'send on' : 'send'} onClick={onSend} aria-label="发送"><Icon name="send" /></button>
      </div>
    </div>
  );
}

function TimelineBody({ sys, agent, onFollow, onFixKey }) {
  const [openProc, setOpenProc] = React.useState(false);
  const [openThink, setOpenThink] = React.useState(false);
  const [openExplore, setOpenExplore] = React.useState(false);
  const [copied, setCopied] = React.useState('');
  const [prHint, setPrHint] = React.useState(false);
  const box = React.useRef(null);
  const live = !!(agent && (agent.running || agent.status === 'run'));
  const err = !!(agent && agent.status === 'err');
  const be = sys === 'be';
  const prompt = (agent && agent.prompt) || '封面 Inbox 外屏也要固定双列，不要再切单列。';
  const files = (agent && agent.files) || (live ? (window.FILES || []) : []);
  const branch = (agent && agent.branch) || '';
  const explore = window.EXPLORE || [];
  const thinkSecs = useTick(12, be && live);
  React.useEffect(() => {
    if (live && box.current) box.current.scrollTop = box.current.scrollHeight;
  }, [live, openProc, openThink, openExplore]);
  const copy = (key, text) => {
    setCopied(key);
    if (navigator.clipboard && text) navigator.clipboard.writeText(text);
    window.setTimeout(() => setCopied(''), 1200);
  };
  const traces = [
    { kind: '推理', text: '外屏再切单列会碎' },
    { kind: '搜索', text: 'Grep narrowPane' },
    { kind: '改文件', text: '主栏改成行' }
  ];
  return (
    <div className="timeline" ref={box}>
      <div className="bubble user">{prompt}</div>

      {be ? null : (
        <div className="run-h">
          <span>{live ? '运行中' : '运行 1'}</span>
          <span className="elapsed">{live ? '1m 12s' : '4m 08s'}</span>
        </div>
      )}

      {err && be ? (
        <div className="fail-row">
          <span className="why">{agent.outcome || '失败'}</span>
          {agent.errFix === 'key' ? (
            <button className="text-btn" type="button" onClick={onFixKey}>去设置</button>
          ) : null}
        </div>
      ) : null}

      {err ? null : be ? (
        <button className="layer-row" onClick={() => setOpenProc(!openProc)}>
          <span className={'layer-k' + (live && !openProc ? ' be-shimmer' : '')}>
            {live ? '推理中 · ' + fmtSecs(thinkSecs) : '过程 · 18s · 4 步'}
          </span>
          {live && !openProc ? <span className="layer-live">{agent.step || '横屏主栏改成行，不再塞双列'}</span> : null}
        </button>
      ) : (
        <button className="layer-row" onClick={() => setOpenThink(!openThink)}>
          <span className="layer-k">{live ? '推理中' : '推理 18s'}</span>
          {live && !openThink ? <span className="layer-live">横屏主栏改成行，不再塞双列</span> : null}
        </button>
      )}
      {err ? null : (be ? openProc : openThink) ? (
        <div className="layer-open">
          {be ? (
            <div className="be-steps">
              {traces.map((t) => (
                <div key={t.text} className="be-step"><span className="be-kind">{t.kind}</span>{t.text}</div>
              ))}
              {explore.map((t) => <div key={t} className="be-step mono">{t}</div>)}
            </div>
          ) : (
            <div className="layer-body">
              <div>外屏宽度不够，再按窄屏切单列会碎。</div>
              <div>内屏竖仍走双列，和封面同一条规则。</div>
              <div>只有 lg 且横屏才 Split，主栏用行。</div>
            </div>
          )}
        </div>
      ) : null}

      {be || err ? null : (
        <div>
          <button className="layer-row" onClick={() => setOpenExplore(!openExplore)}>
            <span className="layer-k">探索 · 读 3 · 搜 1</span>
          </button>
          {openExplore ? (
            <div className="layer-open layer-body">
              {explore.map((t) => <div key={t} className="mono">{t}</div>)}
            </div>
          ) : null}
        </div>
      )}

      {err ? null : live ? (
        <div>
          <div className="now">正在改 {agent.nowFile || 'BreakpointStore.ets'}</div>
          {be && files.length ? (
            <div className="work live">
              {files.map((f) => (
                <span key={f} className={'file-pill' + (f === agent.nowFile ? '' : ' dim')}>{f}</span>
              ))}
            </div>
          ) : null}
        </div>
      ) : (
        (files.length || (agent && agent.pr) || branch) ? (
          <div className="work">
            {files.map((f) => <span key={f} className="file-pill">{f}</span>)}
            {agent && agent.pr ? (
              <button
                className="file-pill act"
                type="button"
                onClick={() => { setPrHint(true); window.setTimeout(() => setPrHint(false), 1200); }}
              >{prHint ? '已打开' : (agent.prLabel || 'PR')}</button>
            ) : null}
            {be && branch ? (
              <button
                className="file-pill branch"
                type="button"
                onClick={() => copy('branch', branch)}
              >{copied === 'branch' ? '已复制' : branch}</button>
            ) : null}
          </div>
        ) : null
      )}

      {err ? (
        <div className="answer">
          <p className="dim">没有改动。换 Key 后再试，或在下边补一句。</p>
        </div>
      ) : (
        <div className="answer">
          {live ? (
            <p>正在把列数判断从窄屏里拿掉。封面和内屏竖仍是双列；内屏横左侧用行。</p>
          ) : agent && agent.rich ? (
            <div>
              <p>封面和内屏竖保持双列；只有内屏横的左侧改成单列行。</p>
              <h2>改了什么</h2>
              <ul>
                <li>去掉 <code>narrowPane</code> 切单列</li>
                <li>Split 主栏用行，不再塞 357 宽的双列</li>
              </ul>
              <h2>怎么判断</h2>
              <p>外屏、内屏竖都走双列。横屏且 <code>lg</code> 才 Split。</p>
              <div className="code">
                <div className="code-h">
                  <span>ets</span>
                  <span
                    role="button"
                    onClick={() => copy('code', 'useSplit = bp === \'lg\' && landscape')}
                  >{copied === 'code' ? '已复制' : '复制'}</span>
                </div>
                <pre>useSplit = bp === 'lg' && landscape</pre>
              </div>
              {be ? (
                <div className="follow">
                  <button type="button" onClick={() => onFollow && onFollow('内屏横主栏为什么用行？')}>内屏横主栏为什么用行？</button>
                  <button type="button" onClick={() => onFollow && onFollow('把双列规则写进 Tokens')}>把双列规则写进 Tokens</button>
                </div>
              ) : null}
            </div>
          ) : (
            <p>{(agent && agent.outcome) || '这一轮已经结束。'}</p>
          )}
        </div>
      )}

      {be || live || err ? null : (
        <div className="outcome">
          <span>已完成</span>
          {agent && agent.pr ? <span className="pr">{agent.prLabel}</span> : null}
          <span className="dim">4m 08s</span>
        </div>
      )}
    </div>
  );
}

function DetailScreen({ onBack, hideBack, phase, sys, agent, onFixKey }) {
  const live = phase === 'live' || !!(agent && agent.running);
  const [draft, setDraft] = React.useState('');
  const [menu, setMenu] = React.useState(false);
  const [toast, setToast] = React.useState('');
  const ready = draft.trim().length > 0;
  const repo = (agent && (agent.repo || shortRepo(agent.group))) || 'edit-DSH';
  const ping = (t) => {
    setToast(t);
    setMenu(false);
    window.setTimeout(() => setToast(''), 1200);
  };
  return (
    <div className="screen" data-screen-label={live ? 'detail-live' : (agent && agent.status === 'err' ? 'detail-err' : 'detail-done')}>
      <div className="bar">
        {hideBack ? null : (
          <button className="icon-btn" onClick={onBack} aria-label="返回"><Icon name="back" /></button>
        )}
        <div className="bar-mid">
          <div className="bar-title">{(agent && agent.title) || '封面双列对齐'}</div>
          <div className="bar-sub">{sys === 'be' ? repo : (live ? 'edit-DSH · 运行中 · 1m 12s' : 'edit-DSH · 已完成 · 4m 08s')}</div>
        </div>
        <button className="icon-btn" aria-label="更多" onClick={() => setMenu(!menu)}><Icon name="more" /></button>
      </div>
      <TimelineBody sys={sys} agent={agent} onFollow={setDraft} onFixKey={onFixKey} />
      {sys === 'hero' || sys === 'be' ? (
        <PromptShell
          sys={sys}
          placeholder={agent && agent.status === 'err' ? '补一句再试…' : '追问…'}
          value={draft}
          onChange={setDraft}
          ready={ready}
          live={live}
          simple={sys === 'be'}
        />
      ) : (
        <div className="composer">
          <button className="chip">能力</button>
          <div className="field">追问…</div>
          <button className="send on" aria-label="发送"><Icon name="send" /></button>
        </div>
      )}
      {menu ? (
        <div>
          <button className="sheet-mask" type="button" aria-label="关闭" onClick={() => setMenu(false)} />
          <div className="sheet" role="menu">
            <button className="sheet-item" type="button" onClick={() => ping('已在浏览器打开')}>在浏览器打开</button>
            {agent && agent.branch ? (
              <button className="sheet-item" type="button" onClick={() => ping('分支已复制')}>复制分支</button>
            ) : null}
            {agent && agent.pr ? (
              <button className="sheet-item" type="button" onClick={() => ping('已打开 PR')}>打开 {agent.prLabel}</button>
            ) : null}
            <button className="sheet-item danger" type="button" onClick={() => ping('已归档')}>归档</button>
          </div>
        </div>
      ) : null}
      {toast ? <div className="toast">{toast}</div> : null}
    </div>
  );
}

function BeSwitch({ on, onToggle, label, hint }) {
  return (
    <button className="set-row" type="button" onClick={onToggle}>
      <span className="set-lab">
        <span>{label}</span>
        {hint ? <span className="set-hint">{hint}</span> : null}
      </span>
      <span className={'be-sw' + (on ? ' on' : '')} role="switch" aria-checked={on}>
        <span className="be-sw-thumb" />
      </span>
    </button>
  );
}

function SettingsScreen({ onBack, prefs, onPrefs, sys }) {
  const p = prefs || { mode: 'light', type: 'default', density: 'comfortable', autoPr: true, haptics: true };
  const set = (k, v) => onPrefs && onPrefs(Object.assign({}, p, { [k]: v }));
  const [swap, setSwap] = React.useState(false);
  const [keyDraft, setKeyDraft] = React.useState('');
  const name = sys === 'hero' ? 'HeroUI' : sys === 'be' ? 'beUI Agent' : 'Now';
  return (
    <div className="screen" data-screen-label="settings">
      <div className="bar">
        <button className="icon-btn" onClick={onBack} aria-label="返回"><Icon name="back" /></button>
        <div className="bar-title">设置</div>
      </div>
      {sys === 'be' ? null : <div className="sys-tag">当前系统 · {name}</div>}
      <div className="set-list">
        <div className="set-k">账号</div>
        <div className="set-card">
          <div className="set-id">
            <div>
              <div className="set-v">Alex Rivera</div>
              <div className="set-who">developer@example.com · crsr_••••8f2a</div>
            </div>
            <button className="text-btn" type="button" onClick={() => setSwap(!swap)}>{swap ? '取消' : '更换'}</button>
          </div>
          {swap ? (
            <div className="swap-box">
              <input className="set-field" placeholder="粘贴新的 crsr_…" value={keyDraft} onChange={(e) => setKeyDraft(e.target.value)} />
              <button className="text-btn" type="button" disabled={keyDraft.trim().length < 8}>验证并保存</button>
            </div>
          ) : null}
        </div>
        {sys === 'be' ? (
          <div>
            <div className="set-k">阅读</div>
            <div className="set-card tight">
              <BeSwitch label="深色" on={p.mode === 'dark'} onToggle={() => set('mode', p.mode === 'dark' ? 'light' : 'dark')} />
              <BeSwitch label="偏大字号" on={p.type === 'large'} onToggle={() => set('type', p.type === 'large' ? 'default' : 'large')} />
              <BeSwitch label="紧凑密度" hint="只收卡片内边距" on={p.density === 'compact'} onToggle={() => set('density', p.density === 'compact' ? 'comfortable' : 'compact')} />
            </div>
            <div className="set-k">任务</div>
            <div className="set-card tight">
              <BeSwitch label="默认自动创建 PR" on={p.autoPr !== false} onToggle={() => set('autoPr', p.autoPr === false)} />
              <BeSwitch label="触感反馈" on={p.haptics !== false} onToggle={() => set('haptics', p.haptics === false)} />
              <div className="set-row static">
                <span>默认模型</span>
                <span className="dim">Composer</span>
              </div>
            </div>
          </div>
        ) : (
          <div>
            <div className="set-k">外观</div>
            <div className="theme-row">
              {[{ id: 'light', label: '浅色' }, { id: 'dark', label: '深色' }].map((t) => (
                <button key={t.id} className={p.mode === t.id ? 'chip on' : 'chip'} onClick={() => set('mode', t.id)}>{t.label}</button>
              ))}
            </div>
            <div className="set-k">字号</div>
            <div className="theme-row">
              {[{ id: 'default', label: '标准' }, { id: 'large', label: '偏大' }].map((t) => (
                <button key={t.id} className={p.type === t.id ? 'chip on' : 'chip'} onClick={() => set('type', t.id)}>{t.label}</button>
              ))}
            </div>
            <div className="set-k">密度</div>
            <div className="theme-row">
              {[{ id: 'comfortable', label: '舒适' }, { id: 'compact', label: '紧凑' }].map((t) => (
                <button key={t.id} className={p.density === t.id ? 'chip on' : 'chip'} onClick={() => set('density', t.id)}>{t.label}</button>
              ))}
            </div>
            <div className="set-k">偏好</div>
            <div className="set-card tight">
              <div className="set-row"><span>默认自动创建 PR</span><span className="dim">开</span></div>
              <div className="set-row"><span>触感反馈</span><span className="dim">开</span></div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function SplitShell({ master, detail }) {
  return (
    <div className="split">
      <div className="split-master">{master}</div>
      <div className="split-detail">{detail}</div>
    </div>
  );
}

Object.assign(window, { InboxCover, NewScreen, DetailScreen, SettingsScreen, AgentCardView, SplitShell });
