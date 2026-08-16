function Frame({ size, mode, type, density, sys, children }) {
  return (
    <div
      className={'theme-frame ' + (size || 'cover')}
      data-theme="app"
      data-sys={sys || 'now'}
      data-mode={mode || 'light'}
      data-type={type || 'default'}
      data-density={density || 'comfortable'}
    >
      {children}
    </div>
  );
}

function inbox(sys, extra) {
  return Object.assign({ sys: sys, agents: window.AGENTS || [], filter: 'all', staticFit: true }, extra || {});
}

function SystemSection({ sys, title, sub }) {
  return (
    <DCSection id={sys} title={title} subtitle={sub}>
      <DCArtboard id={sys + '-light'} label="浅色 · 外屏 Inbox" width={459} height={672}>
        <Frame size="cover" sys={sys}><InboxCover {...inbox(sys, { compact: true })} /></Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-dark'} label="深色 · 外屏 Inbox" width={459} height={672}>
        <Frame size="cover" sys={sys} mode="dark"><InboxCover {...inbox(sys, { compact: true })} /></Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-inner'} label="内屏竖 Inbox" width={664} height={939}>
        <Frame size="inner-p" sys={sys}><InboxCover {...inbox(sys, { compact: false })} /></Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-split'} label="内屏横 Split" width={939} height={664}>
        <Frame size="inner-l" sys={sys}>
          <SplitShell
            master={<InboxCover {...inbox(sys, { compact: true, list: true, activeId: '3' })} />}
            detail={<DetailScreen sys={sys} hideBack phase="live" agent={(window.AGENTS || []).find((a) => a.id === '3')} />}
          />
        </Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-new'} label="新任务" width={459} height={672}>
        <Frame size="cover" sys={sys}><NewScreen sys={sys} /></Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-done'} label="详情 · 已完成" width={664} height={939}>
        <Frame size="inner-p" sys={sys}><DetailScreen sys={sys} phase="done" agent={(window.AGENTS || []).find((a) => a.id === '1')} /></Frame>
      </DCArtboard>
      <DCArtboard id={sys + '-set'} label="设置" width={459} height={672}>
        <Frame size="cover" sys={sys} type="large">
          <SettingsScreen sys={sys} prefs={{ mode: 'light', type: 'large', density: 'comfortable' }} />
        </Frame>
      </DCArtboard>
    </DCSection>
  );
}

function Board() {
  return (
    <DesignCanvas>
      <SystemSection sys="now" title="Now · 现在" sub="空画布新建。铜色只标运行和发送。过程收成行，正文分阶。" />
      <SystemSection sys="hero" title="HeroUI" sub="Segment 筛选。字写在 PromptInput 壳里。官方蓝，运行中发送变停止。" />
      <SystemSection sys="be" title="beUI Agent" sub="密度收口：过程一行，卡上不重复仓库/完成，横屏行标出当前任务。" />
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<Board />);
