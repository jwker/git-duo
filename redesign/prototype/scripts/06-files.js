/* ══ GitDuo 2.0 原型 · 06 · 文件查看 / 编辑器 / 提交详情 / 分支管理页 ══ */
SCR.fileView = {
  inline:p=>p.f, render(p){
    return `
    <div class="content">
      <div class="crumb"><b>${p.f}</b> · ${curBranch()}</div>
      <div class="markdown"><pre><code><span class="kw">import</span> Foundation
<span class="kw">import</span> SwiftUI

<span class="cm">/// Markdown → AttributedString, block-aware.</span>
<span class="kw">public struct</span> <span class="fn">BasicMarkdownRenderer</span> {
    <span class="kw">public func</span> <span class="fn">render</span>(_ md: <span class="fn">String</span>) -> <span class="fn">AttributedString</span> {
        <span class="kw">var</span> out = <span class="fn">AttributedString</span>()
        <span class="kw">for</span> block <span class="kw">in</span> <span class="fn">parseBlocks</span>(md) {
            out += <span class="fn">styled</span>(block)
        }
        <span class="kw">return</span> out
    }
}</code></pre></div>
      <div class="row" style="justify-content:center;gap:10px;margin-top:14px">
        ${p.ro?`<button class="btn ghost" style="padding:9px 22px" onclick="toast('演示：Fork 该仓库后即可编辑')">⑂ Fork 后可编辑</button>`
             :`<button class="btn primary" style="padding:9px 22px" onclick="push('editor',{f:'${p.f}'})">编辑</button>`}
        <button class="btn ghost" onclick="toast('演示：该文件的提交历史')">历史</button>
        <button class="btn ghost" onclick="toast('已复制 Raw 内容')">Raw</button>
        ${p.ro?'':`<button class="btn ghost" onclick="toast('演示：重命名 / 删除（带 sha 校验）')">更多</button>`}
      </div>
      <div class="t3" style="text-align:center;margin-top:10px">${p.ro?'只读浏览 · 他人仓库文件':'保存即一次 commit · 提交面板可选当前分支或新分支 + PR'}</div>
    </div>`;
  }
};
SCR.editor = {
  inline:p=>p.f, render(p){
    return `
    <div class="content" style="display:flex;flex-direction:column;gap:10px">
      <div class="t3">${p.mode==='create'?'新建文件 · 输入路径（自动创建目录）':'编辑 · 语法高亮轻量编辑器'} · 分支 ${curBranch()}</div>
      ${p.mode==='create'?'<input class="sheet-input" value="GitDuo/Features/NewFile.swift">':''}
      <textarea class="code-editor" spellcheck="false">import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, GitDuo!")
    }
}</textarea>
      <button class="btn primary" style="width:100%;padding:12px" onclick="openCommitSheet('${p.mode==='create'?'新建文件':'编辑 '+p.f}')">提交更改…</button>
      <div class="t3" style="text-align:center">保存即一次提交 · 单个文件超过 1MB 请到 GitHub 网页端处理</div>
    </div>`;
  }
};
SCR.commitDetail = {
  inline:p=>p.s, render(p){
    return `
    <div class="content">
      <div class="conv-head">
        <h2 style="font-size:17px">${p.m}</h2>
        <div class="t3">${p.u||'dev-j'} 提交于 2 天前 · <span class="sha">${p.s}</span> · 1 个文件 · +12 −4</div>
      </div>
      ${diffCard('GitDuo/Features/Repos/RepoListView.swift', 12, 4, `
        <div class="hunk">@@ -40,7 +40,9 @@</div>
        <div class="dline"><span class="ln">40</span><span class="code">         PaginatedList(items: store.repos) {</span></div>
        <div class="dline del"><span class="ln">41</span><span class="code">-             Button { selection = repo } label: {</span></div>
        <div class="dline add"><span class="ln">41</span><span class="code">+             NavigationLink(value: repo) {</span></div>`)}
      ${p.ro?`<div class="t3" style="text-align:center;margin-top:12px">只读浏览 · 他人仓库提交</div>`
           :`<button class="btn ghost" style="width:100%;padding:12px;margin-top:12px" onclick="toast('Revert 需在 GitHub 网页端完成 · 已为你打开')">↩ Revert 此提交（跳转网页端）</button>`}
    </div>`;
  }
};
SCR.branches = {
  inline:()=>'分支管理', render(){
    const meta = repoBranchMeta(activeRepo), cb = curBranch();
    const src = meta.list.find(b=>b!==cb) || cb;
    return `
    <div class="content">
      <div class="section-label">${activeRepo} · 全部分支（${meta.list.length}）</div>
      <div class="menu-card">
        ${meta.list.map(b=>`
          <div class="menu-item" onclick="switchBranch('${b}')">
            ${svg(I.fork)} ${b}
            ${b===cb?'<span class="pill open" style="margin-left:8px">当前</span>':''}
            ${b!==meta.def?`<button class="btn ghost" style="margin-left:auto;padding:4px 10px" onclick="event.stopPropagation();deleteBranchAsk('${b}')">删除</button>`:''}
          </div>`).join('')}
      </div>
      <button class="btn primary" style="width:100%;padding:12px;margin-top:12px" onclick="toast('演示：输入名称 → 从 ${cb} 创建并切换')">＋ 新建分支</button>
      <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="openCommitSheet('合并 ${src} → ${cb}')">合并分支到 ${cb}…</button>
      <div class="t3" style="text-align:center;margin-top:8px">Merge 走 API · 冲突时引导到网页端处理</div>
      ${fnote('分支管理',[
        '<b>分支列表</b>：只列<b>当前仓库</b>的分支；默认分支不可删除',
        '<b>切换</b>：切换只影响当前仓库的「代码」与「Commits」，不跨仓库',
        '<b>删除</b>：删前校验是否有未合并提交；删除的若是当前分支，自动回落默认分支',
      ])}
    </div>`;
  }
};
function deleteBranchAsk(b){
  const meta = repoBranchMeta(activeRepo);
  if(b===meta.def){ toast(`${meta.def} 是默认分支，不可删除`); return; }
  openSheet(`
    <div class="sheet-title">删除分支「${b}」？</div>
    <div class="sheet-hint" style="padding:2px 8px 12px">删除前会校验该分支是否有未合并提交，有则阻止。删除后不可恢复。</div>
    <button class="btn primary" style="width:100%;padding:12px;background:var(--closed-p)" onclick="deleteBranch('${b}')">删除分支</button>
    <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="closeSheet()">取消</button>`);
}
function deleteBranch(b){
  const meta = repoBranchMeta(activeRepo);
  const i = meta.list.indexOf(b);
  if(i<0) return;
  meta.list.splice(i,1);
  const wasCurrent = branchByRepo[activeRepo]===b;
  if(wasCurrent) delete branchByRepo[activeRepo];   // 记忆失效 → 下次解析回落默认分支
  closeSheet(); paintTab();
  toast(wasCurrent ? `已删除分支 ${b} · 已回到 ${resolveBranch(activeRepo)}` : `已删除分支 ${b}`);
}

SCR.issueDetail = {
  inline:p=>`#${p.n}`, render(p){
    return `
    <div class="content">
      <div class="conv-head">
        <div class="row">${pillOf(p.s)}<span class="t3">${p.s==='open'?'该 Issue 仍然开放':'已于 3 天前关闭'}</span></div>
        <h2>${p.t}</h2>
        <div class="t3">#${p.n} · my-git/gitduo · 由 reviewer-a 创建于昨天</div>
      </div>
      <div class="comment">
        <div class="avatar" style="background:#5b3a8e">R</div>
        <div class="bubble">
          <div class="bhead"><span class="author">reviewer-a</span><span class="t3">昨天 21:40</span></div>
          <div class="bbody"><p>真机上 <code>session.start()</code> 返回 false 后状态没有回退，按钮一直灰着。建议补上返回值检查。</p></div>
        </div>
      </div>
      <div class="comment">
        <div class="avatar" style="background:#1f883d">J</div>
        <div class="bubble">
          <div class="bhead"><span class="author">you</span><span class="t3">昨天 22:05</span></div>
          <div class="bbody"><p>已确认，修复在 <code>feature/auth-fix</code> 分支，稍后提 PR。</p></div>
        </div>
      </div>
      <div class="composer">
        <textarea placeholder="写评论… (Markdown 支持)"></textarea>
        <button class="btn primary" style="padding:9px 14px" onclick="fakeSend()">发送</button>
      </div>
      <div id="sendErr" style="display:none;margin-top:8px">
        <div style="background:var(--del-bg);color:var(--del-tx);border-radius:9px;padding:9px 12px;font-size:12.5px">⚠ 发送失败：网络不可用。草稿已保留，可重试。</div>
      </div>
    </div>`;
  }
};
