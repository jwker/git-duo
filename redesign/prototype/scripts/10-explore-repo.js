/* ══ GitDuo 2.0 原型 · 10 · 他人仓库只读浏览（含 Star 切换） ══ */
/* ============================================================ 他人仓库详情（探索入口 · 只读浏览） */
SCR.exploreRepoDetail = {
  inline:p=>p.repo.split('/').pop(),
  after(p){ recordVisit(p.repo); }, render(p){
    activeRepo = p.repo;   // 当前仓库 → 分支记忆按它解析
    const t = TRENDING.find(x=>x.n===p.repo) || {n:p.repo,d:'',lang:'其他',lc:'#959da5',s:'—',tp:[],watch:'—',fork:'—',lic:'未指定',upd:'未知',rel:'—',reld:'',relNote:'',contrib:0};
    return `
    <div class="content">
      <div class="repo-hero">
        <div class="row">
          <div class="repo-avatar">${svg(I.repo)}</div>
          <div class="grow"><h2>${p.repo}</h2><div class="t3" style="margin-top:2px">${t.upd} 更新 · ${t.lic} 许可证</div></div>
        </div>
        <div class="desc">${t.d}</div>
        ${t.tp.length?`<div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">${t.tp.map(x=>`<span class="chip" style="color:var(--link)">${x}</span>`).join('')}</div>`:''}
        <div class="stat-row">
          <button class="stat-btn star" id="xStarBtn" onclick="toggleXStar(this,'${t.s}')">${svg(I.star)}<span>Star · ${t.s}</span></button>
          <button class="stat-btn" onclick="toast('演示：仅展示 Watch 计数')">${svg(I.eye)}<span>Watch · ${t.watch}</span></button>
          <button class="stat-btn" onclick="toast('演示：Fork 到自己账户后获得完整写权限')">${svg(I.fork)}<span>Fork · ${t.fork}</span></button>
        </div>
        <div class="t3" style="text-align:center;margin-top:8px">他人仓库 · 只读浏览，Fork 后可编辑与提交</div>
      </div>
      <div class="section-label">我的收藏（私人整理 · 仅自己可见）</div>
      ${favFolderOf(p.repo)
        ?`<button class="btn ghost" id="favBtn" style="width:100%;padding:11px;color:var(--link);border-color:var(--link)" onclick="openFavSheet('${p.repo}')">${svg(I.bm)} 已收藏 · ${favFolderOf(p.repo)} ${svg(I.chevD)}</button>`
        :`<button class="btn ghost" id="favBtn" style="width:100%;padding:11px" onclick="favNow('${p.repo}')">${svg(I.bm)} 收藏到我的列表</button>`}
      <div class="t3" style="text-align:center;margin-top:6px">${favFolderOf(p.repo)?'已加入收藏 · 再点可选择 / 更换收藏列表':'私人收藏夹，不影响仓库的 Star 数'}</div>
      <div class="section-label">语言构成</div>
      <div class="card" style="padding:12px 14px">
        <div style="display:flex;height:8px;border-radius:4px;overflow:hidden">
          <div style="flex:72;background:${t.lc}"></div>
          <div style="flex:18;background:#8250df"></div>
          <div style="flex:10;background:#d1d5da"></div>
        </div>
        <div style="display:flex;gap:14px;margin-top:8px;font-size:12px;color:var(--text2)">
          <span><span class="lang-dot" style="background:${t.lc}"></span>${t.lang} 72%</span>
          <span><span class="lang-dot" style="background:#8250df"></span>Shell 18%</span>
          <span><span class="lang-dot" style="background:#d1d5da"></span>其他 10%</span>
        </div>
      </div>
      <div class="section-label">Latest Release</div>
      <div class="card" style="padding:12px 14px">
        <div class="row"><span class="pill merged" style="background:var(--chip)">${svg(I.fork)} ${t.rel}</span><span class="t3">${t.reld}</span></div>
        <div class="t2" style="margin-top:7px">${t.relNote}</div>
        <div class="row" style="gap:8px;margin-top:10px">
          <button class="btn ghost" style="padding:6px 14px" onclick="toast('演示：下载 Source code (zip)')">下载源码</button>
          <button class="btn ghost" style="padding:6px 14px" onclick="toast('演示：查看 3 个附件资产')">资产 (3)</button>
        </div>
      </div>
      <div class="section-label">文件浏览</div>
      <div class="card" style="padding:4px 14px">
        <div class="file-row" onclick="push('repoCode',{repo:'${p.repo}',ro:1})">
          ${svg(I.folder)}<div class="grow"><div class="fname">浏览目录</div></div>${svg(I.chev)}
        </div>
      </div>
      ${readmeBlock()}
      <div class="section-label">参与协作</div>
      <div class="card" style="padding:4px 14px">
        <div class="file-row" onclick="push('exploreIssueList',{repo:'${p.repo}'})">
          ${svg(I.issueO)}<div class="grow"><div class="fname">Issues</div><div class="fmsg">浏览与参与讨论 · 无关闭权限</div></div>${svg(I.chev)}
        </div>
        <div class="file-row" onclick="push('explorePRList',{repo:'${p.repo}'})">
          ${svg(I.pr)}<div class="grow"><div class="fname">Pull Requests</div><div class="fmsg">查看他人贡献 · 可评论不可合并</div></div>${svg(I.chev)}
        </div>
      </div>
      <div class="section-label">贡献者 · ${t.contrib} 位</div>
      <div class="card" style="padding:12px 14px">
        <div style="display:flex;gap:6px">${Array.from({length:8},(_,i)=>`<div class="avatar" style="background:${['#1f883d','#8250df','#d73a4a','#e16f24','#0075ca','#db61a2','#5b3a8e','#0e8a16'][i]}">${'ABCDEFGHI'[i]}</div>`).join('')}</div>
        <div class="t3" style="margin-top:8px">以及另外 ${t.contrib-8} 位贡献者</div>
      </div>
      ${fnote('探索仓库详情（他人仓库 · 只读）', [
        '<b>Star</b>：公开星标，计数 +1 并进入 Starred 列表（与下方收藏互不相关）',
        '<b>Watch</b>：展示订阅计数；<b>Fork</b>：Fork 后获得完整写权限',
        '<b>收藏</b>：私人收藏夹，仅自己可见（对 Star 数无影响）｜先点收藏，再点才可选择列表；一个仓库只在一个列表里，换列表会从原列表移出',
        '<b>只读浏览</b>：⑤ 文件浏览是一条入口（「浏览目录」），进的是目录页 —— 那里可切分支（仅浏览，无管理分支）｜⑥ README **就在本页**，在 ⑤ 那条入口行之下',
        '<b>Releases</b>：版本说明 · 下载源码与附件资产',
        '<b>洞察</b>：语言构成 · 贡献者概览',
        '<b>参与协作</b>：Issues 可参与讨论（无关闭）· PR 可评论（不可合并）',
        '<b>无写操作</b>：没有 添加/编辑/提交/Revert —— 这些只在「我的仓库」详情页'
      ])}
    </div>`;
  }
};
function toggleXStar(btn, base){
  btn.classList.toggle('starred');
  const n = parseInt(String(base).replace(/\D/g,''))||0;
  const on = btn.classList.contains('starred');
  const shown = /^[,\d]+$/.test(String(base)) ? (on? n+1 : n).toLocaleString('en-US') : base;
  btn.querySelector('span').textContent = on ? `已 Star · ${shown}` : `Star · ${shown}`;
  toast(on ? '已 Star · 公开星标，仓库计数 +1' : '已取消 Star · 仓库计数 −1');
}
/* ⚠️ 2026-10-14（走查第 63 条）：本页原来内嵌一整块目录浏览（`exploreTree`），
   子目录靠 `push('exploreRepoDetail',{sub})` 推入一个**新的详情页**。
   现在 ⑤ 文件浏览 是一条入口行（「浏览目录」），点它进 `SCR.repoCode`（`ro:1`，
   目录层级在那一页内部推进）—— 原函数随之删除。
   ⚠️ **同日晚些：⑥ README 回到本页**（在 ⑤ 那条入口行之下，用 `readmeBlock()`）——
   它一度跟着目录进了代码页，现在两个仓库首页共用那一块（§4.4 的枢纽也一样）。
   ⇒ 那条入口行因此**不再叫「浏览目录与 README」**（README 就在它下面）。 */
SCR.exploreIssueList = {
  inline:p=>'Issues', render(p){
    return `
    <div class="content">
      <div class="t3" style="margin:0 2px 10px">${p.repo} · 开放 ${ISSUES.filter(i=>i.s==='open').length} 个 · 只读演示数据</div>
      ${ISSUES.map(i=>`
        <div class="card" onclick="push('issueDetail',{n:${i.n},t:'${i.t}',s:'${i.s}'})">
          <div class="row"><span class="state-row">${svg(i.s==='open'?I.issueO:I.issueC, i.s==='open'?'ic-open':'ic-closed-i')}</span>
          <div class="grow"><div class="t1">${i.t}</div>
          <div class="t3" style="margin-top:3px">#${i.n} · ${i.d} · 由 ${i.u} 创建</div></div></div>
        </div>`).join('')}
      <div class="t3" style="text-align:center;padding:10px">他人仓库：可评论参与讨论，关闭 Issue 需维护者权限</div>
    </div>`;
  }
};
SCR.explorePRList = {
  inline:p=>'Pull Requests', render(p){
    return `
    <div class="content">
      <div class="t3" style="margin:0 2px 10px">${p.repo} · 只读演示数据</div>
      ${PRS.map(pr=>`
        <div class="card" onclick="push('prDetail',{n:${pr.n},t:'${pr.t}',s:'${pr.s}',u:'${pr.u}',ro:1})">
          <div class="row"><span class="state-row">${svg(pr.s==='merged'?I.merge:I.pr, pr.s==='merged'?'ic-merge':'ic-pr')}</span>
          <div class="grow"><div class="t1">${pr.t}</div>
          <div class="t3" style="margin-top:3px">#${pr.n} · ${pr.b}</div></div></div>
        </div>`).join('')}
      <div class="t3" style="text-align:center;padding:10px">他人仓库：可评论 Review，合并 / 关闭需维护者权限</div>
    </div>`;
  }
};

/* 收藏 →（收藏之后）选择收藏列表 */
/* d:true = 内置默认收藏夹（新收藏的默认去处，不可重命名 / 不可删除） */
/* 规则：一个仓库同时只属于一个收藏夹；**收藏夹的项目数完全由 favMap 推导**，不存在独立计数器字段——
   收藏 +1 ／ 换夹 = 源夹 −1 且目标夹 +1 ／ 取消收藏 −1 ／ 删除夹时其中项回落默认夹（默认夹自动 +N）。 */
