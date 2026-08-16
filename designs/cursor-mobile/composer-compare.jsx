function Ico({ name }) {
  const d = {
    back: 'M14.5 5.5 8 12l6.5 6.5',
    send: 'M12 18V6m0 0 5 5M12 6 7 11',
    search: 'M11 18a7 7 0 1 1 0-14 7 7 0 0 1 0 14Zm9-2-3.8-3.8',
    mail: 'M4 7h16v10H4zM4 7l8 6 8-6',
    stop: 'M8 8h8v8H8z'
  };
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d[name]} />
    </svg>
  );
}

function BeInput({ label, value, onChange, placeholder, error, success, onSend, ready, left, hideSend }) {
  const [focused, setFocused] = React.useState(false);
  const state = error ? 'error' : success ? 'success' : focused ? 'focused' : 'idle';
  const showRight = success || !hideSend;
  return (
    <div className="be-wrap">
      {label ? <label className="be-label">{label}</label> : null}
      <div className="be-field" data-state={state}>
        <span className="be-left"><Ico name={left || 'search'} /></span>
        <input
          value={value}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          style={{ paddingRight: showRight ? 44 : 14 }}
        />
        {showRight ? (
          <span className="be-right">
            {success ? (
              <svg className="be-check" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M5 12.5l4.5 4.5L19 7.5" />
              </svg>
            ) : (
              <button type="button" className={ready ? 'be-send on' : 'be-send'} onClick={onSend} aria-label="发送">
                <Ico name="send" />
              </button>
            )}
          </span>
        ) : null}
      </div>
      {error ? <p className="be-err" role="alert">{error}</p> : null}
    </div>
  );
}

function NewNow() {
  const [text, setText] = React.useState('');
  const ready = text.trim().length > 0;
  return (
    <div className="cmp-screen" data-screen-label="new-now">
      <div className="cmp-bar">
        <button className="cmp-icon" aria-label="返回"><Ico name="back" /></button>
        <div className="cmp-title">新任务</div>
      </div>
      <textarea className="now-canvas" placeholder="要做什么？目标和约束写在这里" value={text} onChange={(e) => setText(e.target.value)} />
      <div className="now-row">
        <button className="chip warn">edit-DSH</button>
        <button className="chip">更多</button>
        <div className="now-field">{ready ? '可以发送' : '仓库已选，补充即可发'}</div>
        <button className={ready ? 'now-send on' : 'now-send'} aria-label="发送"><Ico name="send" /></button>
      </div>
    </div>
  );
}

function NewHero() {
  const [text, setText] = React.useState('');
  const ready = text.trim().length > 0;
  return (
    <div className="cmp-screen" data-screen-label="new-hero">
      <div className="cmp-bar">
        <button className="cmp-icon" aria-label="返回"><Ico name="back" /></button>
        <div className="cmp-title">新任务</div>
      </div>
      <div className="cmp-pad">
        <div className="cmp-hint">HeroUI PromptInput：字写在壳里，工具条和发送同一块。</div>
      </div>
      <div className="hero-shell">
        <textarea className="hero-ta" placeholder="要做什么？" value={text} onChange={(e) => setText(e.target.value)} />
        <div className="hero-tools">
          <button className="chip warn">edit-DSH</button>
          <button className="chip">更多</button>
          <button className={ready ? 'hero-send on' : 'hero-send'} aria-label="发送"><Ico name="send" /></button>
        </div>
        <div className="hero-foot">发送在工具条右下，不在标题栏。</div>
      </div>
    </div>
  );
}

function NewBe() {
  const [text, setText] = React.useState('');
  const [error, setError] = React.useState('');
  const [ok, setOk] = React.useState(false);
  const ready = text.trim().length > 0;
  const send = () => {
    if (!ready) {
      setOk(false);
      setError('先写目标和约束');
      return;
    }
    setError('');
    setOk(true);
  };
  return (
    <div className="cmp-screen" data-screen-label="new-be">
      <div className="cmp-bar">
        <button className="cmp-icon" aria-label="返回"><Ico name="back" /></button>
        <div className="cmp-title">新任务</div>
      </div>
      <div className="cmp-pad">
        <div className="cmp-hint">beUI Input：标签 + 胶囊。空发会抖，发出去打勾。</div>
      </div>
      <BeInput
        label="要做什么"
        value={text}
        onChange={(v) => { setText(v); setError(''); setOk(false); }}
        placeholder="目标和约束"
        error={error}
        success={ok}
        ready={ready}
        onSend={send}
      />
      <div className="be-chips">
        <button className="chip warn">edit-DSH</button>
        <button className="chip">更多</button>
      </div>
    </div>
  );
}

function DetailChrome({ children, composer }) {
  return (
    <div className="cmp-screen">
      <div className="cmp-bar">
        <button className="cmp-icon" aria-label="返回"><Ico name="back" /></button>
        <div className="cmp-title">封面双列对齐</div>
      </div>
      <div className="detail-mini">
        <div className="detail-user">封面 Inbox 外屏也要固定双列，不要再切单列。</div>
        <div className="detail-quiet">探索 · 读 3 · 搜 1</div>
        <div className="detail-now">正在改 BreakpointStore.ets</div>
        <div className="detail-prose">封面和内屏竖仍是双列；内屏横左侧用行。</div>
      </div>
      {composer}
    </div>
  );
}

function DetailNow() {
  return (
    <DetailChrome
      composer={(
        <div className="now-row">
          <button className="chip">能力</button>
          <div className="now-field">追问…</div>
          <button className="now-send on" aria-label="发送"><Ico name="send" /></button>
        </div>
      )}
    />
  );
}

function DetailHero() {
  const [text, setText] = React.useState('');
  const [run, setRun] = React.useState(true);
  const ready = text.trim().length > 0;
  return (
    <DetailChrome
      composer={(
        <div className="hero-shell">
          <textarea className="hero-ta" style={{ minHeight: 56 }} placeholder="追问…" value={text} onChange={(e) => setText(e.target.value)} />
          <div className="hero-tools">
            <button className="chip">能力</button>
            <button className="chip">图片</button>
            {run ? (
              <button className="hero-send stop" aria-label="停止" onClick={() => setRun(false)}><Ico name="stop" /></button>
            ) : (
              <button className={ready ? 'hero-send on' : 'hero-send'} aria-label="发送"><Ico name="send" /></button>
            )}
          </div>
        </div>
      )}
    />
  );
}

function DetailBe() {
  const [text, setText] = React.useState('');
  const [error, setError] = React.useState('');
  const [ok, setOk] = React.useState(false);
  const ready = text.trim().length > 0;
  return (
    <DetailChrome
      composer={(
        <BeInput
          label="追问"
          value={text}
          onChange={(v) => { setText(v); setError(''); setOk(false); }}
          placeholder="运行中也可先写"
          error={error}
          success={ok}
          ready={ready}
          onSend={() => {
            if (!ready) setError('先写一句追问');
            else setOk(true);
          }}
        />
      )}
    />
  );
}

function BeLab() {
  const [email, setEmail] = React.useState('not-an-email');
  const [query, setQuery] = React.useState('Ada');
  const emailError = email.length > 0 && email.indexOf('@') < 0 ? 'Enter a valid email address.' : '';
  return (
    <div className="lab-card" data-screen-label="be-lab">
      <div className="lab-k">beUI 官方预览（原样）</div>
      <BeInput label="Email" left="mail" hideSend value={email} onChange={setEmail} placeholder="you@example.com" error={emailError} />
      <BeInput label="Search" left="search" hideSend value={query} onChange={setQuery} placeholder="Search" success={query.length > 1} />
    </div>
  );
}

function Frame({ skin, children }) {
  return (
    <div className="theme-frame cover" data-theme="app" data-skin={skin || 'now'}>
      {children}
    </div>
  );
}

function Board() {
  return (
    <DesignCanvas>
      <DCSection id="be-src" title="beUI Input 原件" subtitle="h-11 胶囊 · 标签在上 · 聚焦 ring · 错误抖动 · 成功描勾。单行表单控件，不是 Agent 作曲家。">
        <DCArtboard id="lab" label="官方三态" width={360} height={320}>
          <BeLab />
        </DCArtboard>
        <DCPostIt top={24} left={420} rotate={-2} width={220}>
          空发抖一下，发出去打勾。这是这个组件的全部语言。
        </DCPostIt>
      </DCSection>

      <DCSection id="new" title="新任务 · 三种输入" subtitle="现在：整页是画布。Hero：字写在壳里。beUI：胶囊单行。">
        <DCArtboard id="new-now" label="现在" width={459} height={672}>
          <Frame skin="now"><NewNow /></Frame>
        </DCArtboard>
        <DCArtboard id="new-hero" label="HeroUI PromptInput" width={459} height={672}>
          <Frame skin="hero"><NewHero /></Frame>
        </DCArtboard>
        <DCArtboard id="new-be" label="beUI Input" width={459} height={672}>
          <Frame skin="now"><NewBe /></Frame>
        </DCArtboard>
      </DCSection>

      <DCSection id="detail" title="详情追问 · 三种输入" subtitle="同一条时间线，只换底栏。Hero 运行中是停止键。">
        <DCArtboard id="d-now" label="现在" width={459} height={672}>
          <Frame skin="now"><DetailNow /></Frame>
        </DCArtboard>
        <DCArtboard id="d-hero" label="HeroUI" width={459} height={672}>
          <Frame skin="hero"><DetailHero /></Frame>
        </DCArtboard>
        <DCArtboard id="d-be" label="beUI Input" width={459} height={672}>
          <Frame skin="now"><DetailBe /></Frame>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<Board />);
