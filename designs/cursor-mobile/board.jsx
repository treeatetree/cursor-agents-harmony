function Frame({ size, mode, type, density, children }) {
  return (
    <div
      className={'theme-frame ' + (size || 'cover')}
      data-theme="app"
      data-sys="now"
      data-mode={mode || 'light'}
      data-type={type || 'default'}
      data-density={density || 'comfortable'}
    >
      {children}
    </div>
  );
}

function inbox(extra) {
  return Object.assign({ agents: window.AGENTS || [], filter: 'all', staticFit: true }, extra || {});
}

function Board() {
  return (
    <DesignCanvas>
      <DCSection id="tone" title="一套系统 · 浅 / 深" subtitle="锌灰底 + 铜色只标运行中。卡片中间行是步骤或结果，不再重复仓库名。">
        <DCArtboard id="light" label="浅色 · 外屏竖" width={459} height={672}>
          <Frame size="cover">
            <InboxCover {...inbox({ compact: true })} />
          </Frame>
        </DCArtboard>
        <DCArtboard id="dark" label="深色 · 外屏竖" width={459} height={672}>
          <Frame size="cover" mode="dark">
            <InboxCover {...inbox({ compact: true })} />
          </Frame>
        </DCArtboard>
        <DCPostIt top={20} left={56} rotate={-1} width={230}>
          不再并排卖三套皮。深浅是同一套 token，不是浅色倒一下。
        </DCPostIt>
      </DCSection>

      <DCSection id="fold" title="折叠三态" subtitle="外屏/内屏竖双列 · 内屏横 38% 主栏改成行。">
        <DCArtboard id="cover" label="外屏竖 459×672" width={459} height={672}>
          <Frame size="cover">
            <InboxCover {...inbox({ compact: true })} />
          </Frame>
        </DCArtboard>
        <DCArtboard id="inner-p" label="内屏竖 664×939" width={664} height={939}>
          <Frame size="inner-p">
            <InboxCover {...inbox({ compact: false })} />
          </Frame>
        </DCArtboard>
        <DCArtboard id="inner-l" label="内屏横 939×664" width={939} height={664}>
          <Frame size="inner-l">
            <SplitShell
              master={<InboxCover {...inbox({ compact: true, list: true })} />}
              detail={<DetailScreen hideBack phase="live" />}
            />
          </Frame>
        </DCArtboard>
      </DCSection>

      <DCSection id="flow" title="新建 · 详情层级" subtitle="过程收成一行；改动用文件 chip；正文才是阅读面。">
        <DCArtboard id="new" label="新任务" width={459} height={672}>
          <Frame size="cover"><NewScreen /></Frame>
        </DCArtboard>
        <DCArtboard id="detail-live" label="详情 · 运行中" width={459} height={672}>
          <Frame size="cover"><DetailScreen phase="live" /></Frame>
        </DCArtboard>
        <DCArtboard id="detail-done" label="详情 · 已完成" width={664} height={939}>
          <Frame size="inner-p"><DetailScreen phase="done" /></Frame>
        </DCArtboard>
        <DCArtboard id="settings" label="设置 · 字号/密度" width={459} height={672}>
          <Frame size="cover" type="large">
            <SettingsScreen prefs={{ mode: 'light', type: 'large', density: 'comfortable' }} />
          </Frame>
        </DCArtboard>
        <DCPostIt top={40} left={980} rotate={1} width={220}>
          桌面端：探索永远折叠。手机只准一层展开，不要套「Worked for 15m」。
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<Board />);
