const AGENTS = [
  {
    id: '1', title: '布局显示异常', repo: 'edit-DSH', group: 'treeatetree/edit-DSH',
    status: 'done', pr: true, prLabel: 'PR 184', time: '2 小时前', running: false,
    outcome: '封面双列已对齐',
    prompt: '封面 Inbox 外屏也要固定双列，不要再切单列。',
    files: ['Index.ets', 'BreakpointStore.ets'],
    branch: 'cursor/cover-cols',
    rich: true
  },
  {
    id: '2', title: 'Agent retention optimization', repo: 'edit-DSH', group: 'treeatetree/edit-DSH',
    status: 'done', pr: true, prLabel: 'PR 181', time: '5 小时前', running: false,
    outcome: '留存漏斗改完，等你看 diff',
    prompt: '把 Agent 留存漏斗的流失点补上，先出 diff。',
    files: ['Retention.ets'],
    branch: 'cursor/retention-funnel'
  },
  {
    id: '3', title: '封面双列对齐', repo: 'edit-DSH', group: 'treeatetree/edit-DSH',
    status: 'run', pr: false, time: '1m 12s', running: true,
    step: '读 Index.ets · 列数判断',
    prompt: '封面 Inbox 外屏也要固定双列，不要再切单列。',
    files: ['Index.ets', 'BreakpointStore.ets'],
    nowFile: 'BreakpointStore.ets'
  },
  {
    id: '4', title: 'New development environment', repo: 'agents-android-shell', group: 'treeatetree/agents-android-shell',
    status: 'done', pr: false, time: '2 天前', running: false,
    outcome: '环境已建',
    prompt: '给 Android shell 搭一套能跑起来的开发环境。'
  },
  {
    id: '5', title: 'SSE 断线续传', repo: 'MyCloudSever', group: 'treeatetree/MyCloudSever',
    status: 'err', pr: false, time: '昨天', running: false,
    outcome: '401，Key 失效',
    prompt: 'SSE 断线后从上次事件接着拉，不要整段重放。',
    errFix: 'key'
  },
  {
    id: '6', title: '设置页 Key 校验', repo: 'MyCloudSever', group: 'treeatetree/MyCloudSever',
    status: 'done', pr: true, prLabel: 'PR 92', time: '5 天前', running: false,
    outcome: '校验失败会停在设置页',
    prompt: 'Key 校验失败时停在设置页，不要进 Inbox。',
    files: ['SettingsPage.ets'],
    branch: 'cursor/key-validate'
  }
];

const EXPLORE = [
  'Read Index.ets',
  'Read BreakpointStore.ets',
  'Grep narrowPane',
  'Read AgentCard.ets'
];

const FILES = ['Index.ets', 'BreakpointStore.ets'];
const BRANCH = 'cursor/cover-cols';

Object.assign(window, { AGENTS, EXPLORE, FILES, BRANCH });
