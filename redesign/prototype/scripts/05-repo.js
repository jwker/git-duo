/* ══ GitDuo 2.0 原型 · 05 · 仓库详情与四分段（代码 / Issues / PR / Commits） ══ */
SCR.repos = {
  large:true, render(){
    return `
    <div class="page-topbar">
      <div class="largetitle">仓库</div>
      <button class="iconbtn" id="reposSearchBtn" title="搜索" onclick="openSearch()">${svg(I.search)}</button>
    </div>
    <div class="segbar">
      ${['全部','公开','私有','Starred'].map((s,i)=>`<button class="seg ${i===0?'on':''}" onclick="segPick(this)">${s}</button>`).join('')}
    </div>
    ${REPOS.map(r=>`
      <div class="card" onclick="push('${r.n.startsWith('my-git/')?'repoDetail':'exploreRepoDetail'}',{repo:'${r.n}'})">
        <div class="row">
          <div class="repo-avatar">${svg(I.repo)}</div>
          <div class="grow">
            <div class="t1">${r.n} ${r.priv?'<span class="pill closed-i" style="margin-left:4px">私有</span>':''}</div>
            <div class="t2" style="margin-top:2px">${r.d}</div>
            <div style="margin-top:7px">
              <span class="chip"><span class="lang-dot" style="background:${r.lc}"></span>${r.lang}</span>
              <span class="chip">${svg(I.star)} ${r.s}</span>
              <span class="chip">${svg(I.fork)} ${r.f}</span>
            </div>
          </div>
        </div>
      </div>`).join('')}
    ${fnote('仓库列表',[
      '<b>筛选</b>：全部 / 公开 / 私有 / Starred 分段（原型为静态演示）',
      '<b>搜索</b>：右上角放大镜进入搜索页，范围可选仓库 / 用户 / 代码 / Issue · PR',
      '<b>进入</b>：自己的仓库（my-git/*）进详情页，可改文件、提交、管分支；他人仓库进只读浏览页',
    ])}`;
  }
};

SCR.repoDetail = {
  inline:p=>p.repo.split('/').pop(),
  after(p){ recordVisit(p.repo); }, render(p){
    activeRepo = p.repo;   // 当前仓库 → 分支记忆按它解析
    const seg = p.seg||'code';
    return `
    <div class="content">
      <div class="repo-hero">
        <div class="row">
          <div class="repo-avatar">${svg(I.repo)}</div>
          <div class="grow"><h2>${p.repo}</h2></div>
        </div>
        <div class="desc">GitHub 客户端 · SwiftUI · 零第三方依赖</div>
        <div class="stat-row">
          <button class="stat-btn star" id="starBtn" onclick="toggleStar()">${svg(I.star)}<span>Star · 128</span></button>
          <button class="stat-btn">${svg(I.eye)}<span>Watch · 9</span></button>
          <button class="stat-btn">${svg(I.fork)}<span>Fork · 12</span></button>
        </div>
      </div>
      <div class="prtabs" id="repoSegTabs">
        ${[['code','代码'],['issues','Issues'],['prs','Pull Requests'],['commits','Commits']]
          .map(([k,l])=>`<button class="${seg===k?'on':''}" onclick="switchRepoSeg(this,'${k}')">${l}</button>`).join('')}
      </div>
      <div id="repoSegBody">${repoSeg(seg,p)}</div>
      ${fnote('仓库详情', [
        '<b>代码浏览</b>：多级目录 · 可点击面包屑 · 分支切换（代码与 Commits 联动）',
        '<b>分支作用域</b>：分支<b>按仓库分别记忆</b>——切到别的仓库不会带过去；记忆的分支若已不存在，回落该仓库默认分支',
        '<b>文件操作</b>：新建 / 上传文件（文件 App）/ 上传图片（相册）/ 编辑（保存即一次 commit）',
        '<b>提交面板</b>：提交到当前分支或新分支+PR · 409 冲突保护',
        '<b>Commits</b>：提交详情 · Revert 跳转网页端完成',
        '<b>Issues</b>：开放/关闭筛选 · 新建 Issue · 标签多选与新建标签',
        '<b>Pull Requests</b>：对话/Commits/文件 diff · 合并（Merge/Squash/Rebase）· 关闭/重新打开'
      ])}
    </div>`;
  }
};
function fnote(title, items){
  return `<div class="fnote"><div class="ft">本页功能点 · ${title}</div>${items.join('<br>')}</div>`;
}
function toggleFn(){
  const on = document.body.classList.toggle('show-fn');
  document.getElementById('fnToggle').textContent = on ? '隐藏功能点标注' : '显示功能点标注';
}
function repoSeg(seg,p){
  const pathParts = p.sub ? p.sub.split('/') : [];
  let crumbPath = `<span class="crumb-link" onclick="navToSub('')">${p.repo}</span>`;
  let acc = '';
  pathParts.forEach((part,i)=>{
    acc = acc ? acc+'/'+part : part;
    crumbPath += i===pathParts.length-1 ? ` / <b>${part}</b>` : ` / <span class="crumb-link" onclick="navToSub('${acc}')">${part}</span>`;
  });
  const crumb = `<div class="crumb"><span class="branch-chip" onclick="openBranchSheet()">${svg(I.fork)} ${curBranch()} ▾</span> · ${crumbPath}<button class="btn ghost" style="margin-left:auto;padding:5px 12px" onclick="openAddSheet()">${svg(I.plus)} 添加</button></div>`;
  if(seg==='code'){
    const path = p.sub||'';
    const items = TREE[path]||[];
    const rows = items.length ? items.map(f=>{
      const full = path ? path+'/'+f.n : f.n;
      const act = f.t==='dir'
        ? `push('repoDetail',{repo:'${p.repo}',seg:'code',sub:'${full}'})`
        : `push('fileView',{f:'${full}',repo:'${p.repo}'})`;
      return `<div class="file-row" onclick="${act}">
          ${svg(f.t==='dir'?I.dir:I.file)}
          <div class="grow"><div class="fname">${f.n}</div><div class="fmsg">${f.msg}</div></div>
          ${svg(I.chev)}
        </div>`;
    }).join('') : `<div class="t3" style="padding:16px 8px;text-align:center">空目录</div>`;
    const readme = path ? '' : `
    <div class="section-label">README.md</div>
    <div class="markdown">
      <h1>GitDuo</h1>
      <p>为 iPhone 打造的 <b>GitHub 客户端</b>，SwiftUI 原生实现。</p>
      <h2>特性</h2>
      <ul><li>列表与详情 <code>ETag</code> 条件请求，零配额刷新</li><li>仓库详情四分区导航</li><li>Swift 6 严格并发</li></ul>
      <h2>快速开始</h2>
      <pre><code><span class="kw">let</span> client = GitHubClient(token: store.load())
<span class="kw">try await</span> client.<span class="fn">repos</span>(owner: <span class="st">"my-git"</span>)</code></pre>
    </div>`;
    return `
    ${crumb}
    <div class="card" style="padding:4px 14px">${rows}</div>${readme}`;
  }
  if(seg==='issues') return `
    <div class="segbar">
      <button class="seg on" onclick="segPick(this)">开放 (${ISSUES.filter(i=>i.s==='open').length})</button>
      <button class="seg" onclick="segPick(this)">已关闭</button>
      <button class="seg" onclick="segPick(this)">筛选</button>
    </div>
    ${ISSUES.map(i=>`
      <div class="card" onclick="push('issueDetail',{n:${i.n},t:'${i.t}',s:'${i.s}'})">
        <div class="row"><span class="state-row">${svg(i.s==='open'?I.issueO:I.issueC, i.s==='open'?'ic-open':'ic-closed-i')}</span>
        <div class="grow"><div class="t1">${i.t}</div>
        <div class="t3" style="margin-top:3px">#${i.n} · ${i.d} · 由 ${i.u} 创建</div>
        <div style="margin-top:5px">${i.c?`<span class="pill open">${i.c}</span>`:''}</div></div></div>
      </div>`).join('')}
    <button class="btn primary" style="width:100%;padding:12px" onclick="push('newIssue')">${svg(I.plus)} 新建 Issue</button>`;
  if(seg==='prs') return `
    <div class="segbar">
      <button class="seg on" onclick="segPick(this)">开放 (${PRS.filter(x=>x.s==='open').length})</button>
      <button class="seg" onclick="segPick(this)">已合并</button>
    </div>
    ${PRS.map(pr=>`
      <div class="card" onclick="push('prDetail',{n:${pr.n},t:'${pr.t}',s:'${pr.s}',u:'${pr.u}'})">
        <div class="row"><span class="state-row">${svg(pr.s==='merged'?I.merge:I.pr, pr.s==='merged'?'ic-merge':'ic-pr')}</span>
        <div class="grow"><div class="t1">${pr.t}</div>
        <div class="t3" style="margin-top:3px">#${pr.n} · ${pr.b}</div>
        <div style="margin-top:5px" class="t3">${pr.u} 更新于 ${pr.d} · ${pr.ds}</div></div></div>
      </div>`).join('')}`;
  return `
    <div class="card" style="padding:4px 14px">
      ${COMMITS.map(c=>`
        <div class="commit-row" style="cursor:pointer" onclick="push('commitDetail',{m:'${c.m}',s:'${c.s}',u:'${c.u}',repo:'${p.repo}'})">
          <div class="avatar" style="width:28px;height:28px;font-size:11px;background:#8250df">${c.u[1].toUpperCase()}</div>
          <div class="grow"><div class="t1" style="font-size:13.5px;font-weight:600">${c.m}</div>
          <div class="t3">${c.u} 提交于 2 天前</div></div>
          <span class="sha">${c.s}</span>
        </div>`).join('')}
    </div>`;
}
