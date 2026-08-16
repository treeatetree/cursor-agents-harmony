function Hierarchy() {
  return (
    <div className="pair">
      <div className="col">
        <div className="lab">运行中 · 过程收成行，只有当前改动用铜色</div>
        <div className="theme-frame cover" data-theme="app" data-mode="light">
          <DetailScreen phase="live" />
        </div>
      </div>
      <div className="col">
        <div className="lab">已完成 · 过程合上，正文用标题 / 列表 / 代码分阶</div>
        <div className="theme-frame inner-p" data-theme="app" data-mode="light">
          <DetailScreen phase="done" />
        </div>
      </div>
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<Hierarchy />);
