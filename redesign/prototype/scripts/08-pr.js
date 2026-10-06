/* ══ GitDuo 2.0 原型 · 08 · PR 详情（diff 卡片）与合并 / 关闭 / 评论 ══ */
SCR.prDetail = {
  inline:p=>`#${p.n}`, render(p){
    curPr = PRS.find(x=>x.n===p.n) || {n:p.n,t:p.t,s:p.s,b:'feature/repo-hub → main',u:p.u,d:'2 小时前',ds:'+842 −156'};
    curPr.ro = !!p.ro;
    const seg = p.seg||'conv';
    return `
    <div class="content">
      <div class="conv-head">
        <div class="row">${pillOf(curPr.s)}<span class="t3">${prHeadNote()}</span></div>
        <h2>${curPr.t}</h2>
        <div class="t3">#${curPr.n} · ${curPr.b} · 更新于 ${curPr.d}</div>
      </div>
      <div class="prtabs">
        ${[['conv','对话'],['commits','Commits'],['files',`文件 ${curPr.ds}`]]
          .map(([k,l])=>`<button class="${seg===k?'on':''}" onclick="switchPrSeg(this,'${k}')">${l}</button>`).join('')}
      </div>
      <div id="prSegBody">${prSeg(seg)}</div>
    </div>`;
  }
};
let curPr = null;
function prHeadNote(){
  const pr = curPr;
  if(pr.s==='merged') return `已由 ${pr.u} 合并进 main`;
  if(pr.s==='closed-p') return '已关闭，未合并';
  return `${pr.u} 请求合并到 ${pr.b.split('→')[1].trim()}`;
}
function prSeg(seg){
  const pr = curPr;
  if(seg==='conv'){
    let body = `
    <div class="comment">
      <div class="avatar" style="background:#1f883d">${pr.u[1].toUpperCase()}</div>
      <div class="bubble">
        <div class="bhead"><span class="author">${pr.u}</span><span class="t3">2 小时前</span></div>
        <div class="bbody"><p>仓库详情升级为 <b>代码 / Issues / PR / Commits</b> 四分区枢纽，全部走标准 <code>NavigationLink</code> push。</p></div>
      </div>
    </div>
    <div class="comment">
      <div class="avatar" style="background:#8250df">K</div>
      <div class="bubble">
        <div class="bhead"><span class="author">dev-k</span><span class="t3">1 小时前</span><span class="pill merged" style="margin-left:auto">已批准</span></div>
        <div class="bbody"><p>导航结构 LGTM，等 <code>fileView</code> 的分支切换再合。</p></div>
      </div>
    </div>`;
    if(pr.s==='merged') body =
      `<div style="background:var(--chip);border-radius:9px;padding:9px 12px;font-size:12.5px;color:var(--text2);margin-bottom:10px">已由 ${pr.u} 于 ${pr.d} 合并进 main · 讨论已锁定</div>` + body;
    let ops='';
    if(curPr.ro){ ops = `<div class="t3" style="text-align:center;padding:10px 0 0">他人仓库 · 可评论 Review，合并 / 关闭需维护者权限</div>`; }
    else if(pr.s==='open') ops = `
      <div class="section-label" style="margin:18px 2px 8px">操作</div>
      <button class="btn primary" style="width:100%;padding:12px" onclick="openMergeSheet()">${svg(I.merge)} 合并 Pull Request</button>
      <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="closePr()">关闭 Pull Request</button>`;
    else if(pr.s==='closed-p') ops = `
      <div class="section-label" style="margin:18px 2px 8px">操作</div>
      <button class="btn primary" style="width:100%;padding:12px" onclick="reopenPr()">重新打开 Pull Request</button>`;
    const composer = pr.s==='merged' ? '' : `
      <div class="composer" style="margin-top:12px"><textarea id="prCmt" placeholder="写评论…"></textarea><button class="btn primary" style="padding:9px 14px" onclick="sendPrComment()">发送</button></div>`;
    return `<div id="convList">${body}</div>${ops}${composer}`;
  }
  if(seg==='commits') return `
    <div class="card" style="padding:4px 14px">
      ${COMMITS.concat([{m:'feat: star toggle animation',u:'dev-j',s:'c881f0b'}]).map(c=>`
        <div class="commit-row" style="cursor:pointer" onclick="push('commitDetail',{m:'${c.m}',s:'${c.s}',u:'${c.u}',repo:'my-git/gitduo',ro:${curPr.ro?1:0}})">
          <div class="avatar" style="width:28px;height:28px;font-size:11px;background:#1f883d">${c.u[1].toUpperCase()}</div>
          <div class="grow"><div class="t1" style="font-size:13.5px;font-weight:600">${c.m}</div>
          <div class="t3">${c.u}</div></div><span class="sha">${c.s}</span>
        </div>`).join('')}
    </div>`;
  return `
    <div class="t3" style="margin:0 2px 10px">12 个文件 · 点击文件卡片展开 diff</div>
    ${diffCard('GitDuo/App/AppTabs.swift', 46, 12, `
      <div class="hunk">@@ -12,7 +12,9 @@</div>
      <div class="dline"><span class="ln">12</span><span class="code">  <span class="kw">var</span> body: <span class="kw">some</span> View {</span></div>
      <div class="dline del"><span class="ln">13</span><span class="code">-     TabView(selection: $selection) {</span></div>
      <div class="dline del"><span class="ln">14</span><span class="code">-         RepoListView()</span></div>
      <div class="dline add"><span class="ln">13</span><span class="code">+     TabView {</span></div>
      <div class="dline add"><span class="ln">14</span><span class="code">+         DashboardView()   <span class="cm">// 新首页</span></span></div>
      <div class="dline add"><span class="ln">15</span><span class="code">+         RepoListView()    <span class="cm">// 标准 push 栈</span></span></div>
      <div class="dline"><span class="ln">15</span><span class="code">         NotificationsView()</span></div>`)}
    ${diffCard('GitDuo/Features/Repos/RepoListView.swift', 301, 88, `
      <div class="hunk">@@ -40,9 +40,14 @@</div>
      <div class="dline"><span class="ln">40</span><span class="code">         PaginatedList(items: store.repos) {</span></div>
      <div class="dline del"><span class="ln">41</span><span class="code">-             Button { selection = repo } label: {</span></div>
      <div class="dline add"><span class="ln">41</span><span class="code">+             NavigationLink(value: repo) {</span></div>
      <div class="dline add"><span class="ln">42</span><span class="code">+                 RepoRow(repo: repo)</span></div>
      <div class="dline"><span class="ln">43</span><span class="code">             }</span></div>`)}
    ${diffCard('Packages/GitDuoKit/RepoContentService.swift', 595, 56, `
      <div class="hunk">@@ -1,0 +1,28 @@</div>
      <div class="dline add"><span class="ln">1</span><span class="code">+ <span class="cm">/// 代码树 / 文件内容 / 分支切换。</span></span></div>
      <div class="dline add"><span class="ln">2</span><span class="code">+ <span class="kw">public struct</span> <span class="fn">RepoContentService</span> {</span></div>
      <div class="dline add"><span class="ln">3</span><span class="code">+     <span class="kw">public func</span> <span class="fn">tree</span>(owner: <span class="fn">String</span>, ref: <span class="fn">String</span>) <span class="kw">async throws</span> -> [TreeEntry]</span></div>`)}
    `;
}
function diffCard(file, add, del, body){
  return `
  <div class="diffcard open" onclick="this.classList.toggle('open')">
    <div class="dhead">
      <span class="fn">▾ ${file}</span>
      <span style="margin-left:auto"></span>
      <span class="dstat add">+${add}</span><span class="dstat del">−${del}</span>
    </div>
    <div class="dbody" onclick="event.stopPropagation()">${body}</div>
  </div>`;
}

/* ============================================================ PR operations */
function openMergeSheet(){
  openSheet(`
    <div class="sheet-title">合并 · ${curPr.b}</div>
    <div id="mergeMethods">
      ${[['merge','Merge commit','保留全部分支提交历史'],['squash','Squash and merge','压成一个提交，历史更干净'],['rebase','Rebase and merge','线性历史，不含合并节点']]
        .map(([k,t,dsc],i)=>`
        <div class="sheet-row" onclick="pickMerge(this,'${k}')">
          <span class="grow"><b style="font-weight:600">${t}</b><br><span class="t3" style="font-weight:400">${dsc}</span></span>
          ${i===0?'<b class="mk" style="color:var(--green)">✓</b>':''}
        </div>`).join('')}
    </div>
    <button class="btn primary" style="width:100%;padding:12px;margin-top:8px" onclick="doMerge()">确认合并进 main</button>
    <div class="sheet-hint">Merge 走 API · 分支有冲突时引导到网页端处理</div>`);
}
let mergeMethod = 'merge';
function pickMerge(el, k){
  mergeMethod = k;
  document.querySelectorAll('#mergeMethods .mk').forEach(m=>m.remove());
  el.insertAdjacentHTML('beforeend','<b class="mk" style="color:var(--green)">✓</b>');
}
function doMerge(){
  const name = {merge:'Merge commit',squash:'Squash',rebase:'Rebase'}[mergeMethod];
  curPr.s = 'merged';
  closeSheet(); paintTab();
  toast(`已用 ${name} 合并 #${curPr.n} 进 main`);
}
function closePr(){
  curPr.s = 'closed-p'; paintTab();
  toast('已关闭 Pull Request，未合并');
}
function reopenPr(){
  curPr.s = 'open'; paintTab();
  toast('已重新打开 Pull Request');
}
function sendPrComment(){
  const ta = document.getElementById('prCmt');
  const v = (ta.value||'').trim();
  if(!v){ toast('先写点内容再发送'); return; }
  const div = document.createElement('div');
  div.className = 'comment';
  div.innerHTML = `<div class="avatar" style="background:var(--link)">Y</div><div class="bubble"><div class="bhead"><span class="author">you</span><span class="t3">刚刚</span></div><div class="bbody"></div></div>`;
  div.querySelector('.bbody').textContent = v;
  document.getElementById('convList').appendChild(div);
  ta.value = '';
  toast('评论已发送');
}

