/* ══ GitDuo 2.0 原型 · 05 · 仓库首页（枢纽 · 四行入口）· 代码页（页内层级）· 三个列表页 ══ */
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
      '<b>进入</b>：自己的仓库（my-git/*）进仓库首页（枢纽），可改文件、提交、管分支；他人仓库进只读浏览页',
    ])}`;
  }
};

/* ============================================================ 仓库首页 = 枢纽页 */
/* 2026-10-14（走查第 63 条）：这一页**只做枢纽** —— 头部大卡 + 四行入口。
   ⚠️ 它原来是「大卡 + 四分段条 + 就地换内容」，而「代码」那一档里还内嵌着目录树：
      ① 文件浏览占太多空间 —— 大卡（约 145pt）+ 分段条连上下间距（约 60pt）顶在
         **每一层目录**上面，进几次目录就要重复看几次；
      ② 点进下级目录 = `push` 一个**新的仓库详情页**（`sub` 写在路由里），
         那一页要从头部开始把四条数据重取一遍。
   现在四个分区各自成页，「代码」那一页自己承载目录层级（见下面的 SCR.repoCode）。 */
SCR.repoDetail = {
  inline:p=>p.repo.split('/').pop(),
  after(p){ recordVisit(p.repo); }, render(p){
    activeRepo = p.repo;   // 当前仓库 → 分支记忆按它解析
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
      <div class="menu-card">
        ${repoEntryRows(p.repo)}
      </div>
      ${readmeBlock()}
      ${fnote('仓库首页（枢纽）', [
        '<b>四行入口</b>：代码 / Issues / Pull Requests / Commits —— 每一行都落到**独立页面**',
        '<b>为什么不再是分段条</b>：过去四个分段与头部大卡挤在同一页，而「代码」那一档里还内嵌着目录树 ⇒ 进一次下级目录就要把大卡与分段条重看一遍（约 200pt 顶在每一层上面）。现在这一页只做枢纽',
        '<b>「代码」是入口不是分区</b>：它带自己的一页，目录层级在那一页**内部**推进 —— 往回走一层时，上一层的内容立刻就在（不重取、不闪骨架）',
        '<b>每页各取各的</b>：四行入口的列表与目录由各自那一页去取；本页只取头部（仓库简介 + Star 基准）与 **README** 两块',
        '<b>README 在四行入口之下</b>：它可能很长 ⇒ 放在那四行**上面**会把这一页的四个出口挤出首屏，而四行正是枢纽的用处（本次改动的前提就是"别让首屏被别的东西占满"）',
      ])}
    </div>`;
  }
};

/* 仓库首页的 **README 块**（§4.4 枢纽 + §4.13 他人仓库详情各画一份）。
   ⚠️ 2026-10-14：它**从代码页搬到了这两个首页**（`codeBodyHTML` 里那份已删）——
      README 回答的是"这个仓库是什么"，代码页回答的是"里面有什么文件"；
      当年它出现在代码页里，只因为"仓库根"那个位置顺带取到了那一份。
   ⚠️ **两页共用这一个函数**（与 App 的 `RepoReadmeSection` 同一个处置）：
      README 的正文、以及它那几处接线（仓库内相对链接 / 相对图片）在两页上必须同源，
      各写一份只会漂移 —— 而"链接点了没反应"正是那种漂移最难查的样子。 */
function readmeBlock(){
  return `
    <div class="section-label">README.md</div>
    <div class="markdown">
      <h1>GitDuo</h1>
      <p>为 iPhone 打造的 <b>GitHub 客户端</b>，SwiftUI 原生实现。</p>
      <h2>特性</h2>
      <ul><li>列表与详情 <code>ETag</code> 条件请求，零配额刷新</li><li>仓库首页四行入口 · 代码页自带目录层级</li><li>Swift 6 严格并发</li></ul>
      <h2>快速开始</h2>
      <pre><code><span class="kw">let</span> client = GitHubClient(token: store.load())
<span class="kw">try await</span> client.<span class="fn">repos</span>(owner: <span class="st">"my-git"</span>)</code></pre>
    </div>`;
}

/* 四行入口：图标 / 颜色 / 文字 / 落点全在一处（同 App `RepoDetailView.entryRows`）。
   ⚠️ 2026-10-15（走查第 73 条 · 方案 D）：图标升级为 40pt 实底色块 + 白字形，
      `--ic` 内联给色（原 `.tint-open` 绿描边机制随之移除）——
      Issues 用开放态那个绿、PR 用链接蓝，颜色仍是「这一类东西」的固定色而非状态。 */
function repoEntryRows(repo){
  const rows = [
    {t:'代码',           ic:I.folder, c:'var(--slate)', act:`push('repoCode',{repo:'${repo}'})`},
    {t:'Issues',         ic:I.issueO, c:'var(--green)', act:`push('repoSection',{repo:'${repo}',seg:'issues'})`},
    {t:'Pull Requests',  ic:I.pr,     c:'var(--link)',  act:`push('repoSection',{repo:'${repo}',seg:'prs'})`},
    {t:'Commits',        ic:I.commit, c:'var(--merge)', act:`push('repoSection',{repo:'${repo}',seg:'commits'})`},
  ];
  return rows.map(r=>`<div class="menu-item" style="--ic:${r.c}" onclick="${r.act}">${svg(r.ic)} ${r.t}<span class="chev">${svg(I.chev)}</span></div>`).join('');
}

/* ============================================================ 代码页（页内层级） */
/* ⚠️ 这一页的要点：目录层级是**它自己内部**的状态（`params.sub`）——
   点一行目录只重绘 `#codeBody`，**不进导航栈、也不整页重绘** ⇒ 往回走一层时，
   上一层的内容立刻就在（不重取、不闪骨架）。这就是"像文件夹操作那样流畅"的来源。
   本次改动之前：进一层 = `push` 一个新仓库详情页，返回键回的是"上一页"而不是"上一层"。
   规则（与 App `RepoCodeView` 一致）：

     | 动作 | 结果 |
     |---|---|
     | 点一行目录 | 往这一页的层级栈推进一层（不换页面）|
     | 返回键 | 回上一层目录；**已经在仓库根层时**才退出这一页 |
     | 点面包屑某一层 | 直接截断到那一层 |
     | 点一行文件 | 推入文件页（那是**外层**路由）—— 返回时这一层连同目录栈原样还在 |

   ⚠️ **没有左滑返回**（2026-10-14，随 App 那边的一次崩溃修复一起去掉）：层级是这一页
   自己的状态，而系统的左滑手势属于**外层**导航栈、语义是"退出这一页"——两者不是一回事。
   要给层级配左滑就得自己写手势（原型的按钮上本来也长不出手势），**不做**。

   ⚠️ 一页服务两种仓库：`params.ro` = 1 是他人仓库（右上角菜单里只剩「复制路径」、
   分支弹层不给「管理分支…」）—— 与 App 的 `readOnly` 同一档。 */
SCR.repoCode = {
  inline:p=>p.repo.split('/').pop(),
  /* 导航栏右上角那颗「⋯」（2026-10-14 从面包屑右侧搬来 —— 用户要求与文件页统一）。
     ⚠️ 两档**都给**这颗按钮：只读那一档只是菜单里少一项（`openCodeMenuSheet` 判）。
     ⚠️ 原型这边菜单一律落到底部 sheet（原型没有系统 `Menu` 那种控件）——
        表达的是"这一颗入口里有两件事"，展开形态与 App 不同，**位置与项一致**。 */
  action:p=>`<button class="nact" onclick="openCodeMenuSheet(${p.ro?1:0})" aria-label="目录操作菜单">${svg(I.dots)}</button>`,
  render(p){
    activeRepo = p.repo;   // 分支记忆按它解析（本页不记最近访问，那是仓库首页的事）
    const ro = !!p.ro;
    const notes = [
      '<b>目录层级在页内推进</b>：点一行目录 = 往这一页的层级栈推进一层，**不换页面** ⇒ 往回走一层时上一层的内容立刻就在，不重取、也不闪骨架（这是本次改动的要点）',
      '<b>两条回上层的路</b>：返回键（回上一层目录，到仓库根层才退出这一页）／点面包屑某一层（直接截断到那一层）。⚠️ 没有左滑返回 —— 层级是这一页自己的状态，配不上系统的返回手势',
      '<b>点一行文件</b>：推入文件页（那是**外层**路由）—— 返回时这一层连同整个目录栈原样还在',
      '<b>分支作用域</b>：分支<b>按仓库分别记忆</b>——切到别的仓库不会带过去；记忆的分支若已不存在，回落该仓库默认分支',
      '<b>代码与 Commits 联动</b>：两页共用同一份"按仓库记忆"的分支',
    ];
    if(ro) notes.push('<b>只读</b>：他人仓库这一档右上角菜单里只剩「复制路径」（没有「添加文件」），分支弹层也没有「管理分支…」—— 要写就先 Fork');
    return `
    <div class="content">
      <div id="codeBody">${codeBodyHTML(p)}</div>
      ${fnote('代码页'+(ro?'（他人仓库 · 只读）':''), notes)}
    </div>`;
  }
};

/* 当前这一层的内容：面包屑 + 目录卡片。
   ⚠️ **没有 README**（2026-10-14）—— 它原先长在根层（`sub` 为空时多画一块），
   现在画在**两个仓库首页**上（`readmeBlock`，见上面那个函数的说明）。
   ⇒ 本函数不再需要知道"这是不是根层"。 */
function codeBodyHTML(p){
  const sub = p.sub||'', ro = !!p.ro;
  const parts = sub ? sub.split('/') : [];
  let crumbPath = `<span class="crumb-link" onclick="codeGo('')">${p.repo}</span>`;
  let acc = '';
  parts.forEach((part,i)=>{
    acc = acc ? acc+'/'+part : part;
    crumbPath += i===parts.length-1 ? ` / <b>${part}</b>` : ` / <span class="crumb-link" onclick="codeGo('${acc}')">${part}</span>`;
  });
  /* ⚠️ 面包屑**右端没有按钮**了（2026-10-14）：那颗「＋ 添加」搬到了导航栏右上角，
     变成一颗「⋯」（`SCR.repoCode.action` → `openCodeMenuSheet`）。 */
  const crumb = `<div class="crumb"><span class="branch-chip" onclick="openBranchSheet(${ro?'false':'true'})">${svg(I.fork)} ${curBranch()} ▾</span> · ${crumbPath}</div>`;
  const items = TREE[sub]||[];
  const rows = items.length ? items.map(f=>{
    const full = sub ? sub+'/'+f.n : f.n;
    const act = f.t==='dir'
      ? `codeGo('${full}')`
      : `push('fileView',{f:'${full}',repo:'${p.repo}'${ro?',ro:1':''}})`;
    return `<div class="file-row" onclick="${act}">
        ${svg(f.t==='dir'?I.dir:I.file)}
        <div class="grow"><div class="fname">${f.n}</div><div class="fmsg">${f.msg}</div></div>
        ${svg(I.chev)}
      </div>`;
  }).join('') : `<div class="t3" style="padding:16px 8px;text-align:center">空目录</div>`;
  return `${crumb}
    <div class="card" style="padding:4px 14px">${rows}</div>`;
}

/* 页内进 / 退一层：只改这一页的状态，**只重绘 `#codeBody`**（不 paintTab、不进导航栈）。
   ⚠️ 别改成 `push('repoCode',{...,sub})` —— 那就退回"每进一层压一个新页面"的老行为，
      而这条正是用户报回来的两个症状之一。 */
function codeGo(sub){
  const st = stacks[active], top = st[st.length-1];
  if(!top || top.id!=='repoCode') return;
  if(sub) top.params.sub = sub; else delete top.params.sub;
  const body = document.getElementById('codeBody');
  if(body) body.innerHTML = codeBodyHTML(top.params);
}

/* 上一层目录的路径（返回键用；根层返回空串）。 */
function codeParentPath(sub){
  const parts = String(sub||'').split('/').filter(Boolean);
  parts.pop();
  return parts.join('/');
}

/* ============================================================ 三个列表页 */
/* Issues / Pull Requests / Commits 各自一页（原来是同一条分段条里的三段）。
   ⚠️ 一个路由三档标题 —— 与 App 的 `RepoSectionListView` 同一形状。 */
const SECTION_TITLE = {issues:'Issues', prs:'Pull Requests', commits:'Commits'};
const SECTION_NOTES = {
  issues: [
    '<b>状态</b>：开放 / 已关闭 / 筛选',
    '<b>新建 Issue</b>：标题 + 正文 + 标签多选（可当场新建标签）',
    '<b>这一页从哪来</b>：仓库首页四行入口的第二行 —— 它是一页独立列表，不再与头部大卡挤在同一屏',
  ],
  prs: [
    '<b>状态</b>：开放 / 已合并',
    '<b>Pull Request 详情</b>：对话 / Commits / 文件 diff · 合并（Merge / Squash / Rebase）· 关闭 / 重新打开',
    '<b>这一页从哪来</b>：仓库首页四行入口的第三行',
  ],
  commits: [
    '<b>提交列表</b>：走当前分支（**按仓库分别记忆**，与「代码」页共用同一份）',
    '<b>提交详情</b>：文件 diff · Revert 跳转网页端完成',
    '<b>这一页从哪来</b>：仓库首页四行入口的第四行',
  ],
};
SCR.repoSection = {
  inline:p=>SECTION_TITLE[p.seg]||'',
  render(p){
    activeRepo = p.repo;
    return `
    <div class="content">
      <div id="repoSegBody">${repoSeg(p.seg,p)}</div>
      ${fnote('仓库列表页 · '+(SECTION_TITLE[p.seg]||''), SECTION_NOTES[p.seg]||[])}
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
