/* ══ GitDuo 2.0 原型 · 04 · 搜索（仓库 / 用户 / 代码 / Issue·PR 四范围 + 历史 + 热词） ══ */
/* ============================================================ search */
const SEARCH_SCOPES = [['repos','仓库'],['users','用户'],['code','代码'],['issues','Issue · PR']];
const SEARCH_HOT = ['swiftui','markdown','设计令牌','oauth','折叠屏'];
const SEARCH_USERS = [
  {u:'torvalds',n:'Linus Torvalds',c:'#5b3a8e',bio:'Linux kernel · Git',repo:5,fol:'210k'},
  {u:'gaearon',n:'Dan Abramov',c:'#1f883d',bio:'React 核心成员 · 前端性能',repo:12,fol:'98k'},
  {u:'yyx990803',n:'Evan You',c:'#767676',bio:'Vue / Vite 作者',repo:24,fol:'112k'},
  {u:'dev-j',n:'jiangjiang',c:'#0969da',bio:'my-git · iOS / SwiftUI 开发',repo:3,fol:'21'},
  {u:'dev-k',n:'kay',c:'#8250df',bio:'my-git · 测试与 CI',repo:6,fol:'8'},
];
const CODE_INDEX = [
  {p:'Packages/GitDuoKit/Sources/GitHubAPI/GitHubClient.swift',r:'my-git/gitduo',lang:'Swift',l:'let client = GitHubClient(token: store.load())'},
  {p:'GitDuo/App/AppEnvironment.swift',r:'my-git/gitduo',lang:'Swift',l:'private var authFailureNotified = Mutex(false)'},
  {p:'GitDuo/Features/Repos/RepoDetailView.swift',r:'my-git/gitduo',lang:'Swift',l:'@State private var renderedReadme: AttributedString?'},
  {p:'GitDuo/Features/Repos/RepoListView.swift',r:'my-git/gitduo',lang:'Swift',l:'NavigationLink(value: repo) { RepoRow(repo: repo) }'},
  {p:'Sources/PanelKit/HingeContainer.swift',r:'misoge/paneltkit',lang:'Swift',l:'struct HingeContainer<Content: View>: View {'},
  {p:'src/core/parser.rs',r:'nicedoc/mdx-engine',lang:'Rust',l:'pub fn parse_inline(&self, src: &str) -> Vec<Node>'},
  {p:'packages/tokens/src/duration.ts',r:'openui/tokens',lang:'TypeScript',l:'export const duration = { fast: 120, base: 240 }'},
];
let SEARCH_HISTORY = ['swiftui','next.js','头像降采样','Issues 标签'];
let searchState = { q:'', scope:'repos' };
const esc = s => String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const hit = (s,k) => String(s||'').toLowerCase().includes(k);

SCR.search = {
  inline:()=>'搜索',
  after(){ const el=document.getElementById('searchInput'); if(el) el.focus(); },
  render(){
    return `
    <div class="content" style="padding-top:10px">
      <div class="searchfield">
        ${svg(I.search)}
        <input id="searchInput" value="${esc(searchState.q)}" placeholder="搜索仓库、用户、代码、Issue…" autocomplete="off"
          oninput="onSearchInput(this.value)" onkeydown="if(event.key==='Enter')commitSearch()">
        <button class="search-clr" id="searchClear" style="${searchState.q?'':'display:none'}" onclick="clearQuery()">${svg(I.x)}</button>
      </div>
      <div class="segbar" id="scopeBar">${scopeBarHTML()}</div>
      <div id="searchBody">${searchBody()}</div>
    </div>`;
  }
};
function openSearch(){ searchState.q=''; push('search'); }
function scopeBarHTML(){
  return SEARCH_SCOPES.map(([k,l])=>`<button class="seg ${searchState.scope===k?'on':''}" onclick="setSearchScope('${k}')">${l}</button>`).join('');
}
function setSearchScope(s){
  searchState.scope = s;
  document.getElementById('scopeBar').innerHTML = scopeBarHTML();
  document.getElementById('searchBody').innerHTML = searchBody();
}
function onSearchInput(v){
  searchState.q = v;
  const c = document.getElementById('searchClear'); if(c) c.style.display = v ? '' : 'none';
  document.getElementById('searchBody').innerHTML = searchBody();
}
function clearQuery(){
  searchState.q = '';
  const el = document.getElementById('searchInput'); if(el){ el.value=''; el.focus(); }
  const c = document.getElementById('searchClear'); if(c) c.style.display='none';
  document.getElementById('searchBody').innerHTML = searchBody();
}
function useTerm(q){
  searchState.q = q;
  const el = document.getElementById('searchInput'); if(el) el.value = q;
  const c = document.getElementById('searchClear'); if(c) c.style.display='';
  document.getElementById('searchBody').innerHTML = searchBody();
}
function useHistory(i){ useTerm(SEARCH_HISTORY[i]); }
function useHot(i){ useTerm(SEARCH_HOT[i]); }
function clearSearchHistory(){ SEARCH_HISTORY = []; document.getElementById('searchBody').innerHTML = searchBody(); toast('已清除搜索记录'); }
function recordTerm(){
  const q = searchState.q.trim(); if(!q) return;
  SEARCH_HISTORY = [q].concat(SEARCH_HISTORY.filter(x=>x!==q)).slice(0,8);
}
function commitSearch(){
  if(!searchState.q.trim()){ toast('先输入关键词'); return; }
  recordTerm(); toast(`搜索「${searchState.q.trim()}」`);
}
function searchBody(){
  const q = searchState.q.trim();
  if(!q) return searchIdleHTML();
  const rows = searchRows(q), label = SEARCH_SCOPES.find(s=>s[0]===searchState.scope)[1];
  if(!rows.length) return `<div class="empty-box">没有匹配「${esc(q)}」的${label}<br>换个关键词，或切换上方范围试试</div>`;
  return `<div class="section-label" style="margin-top:2px">${label} · ${rows.length} 个结果</div>${rows.join('')}`;
}
function searchIdleHTML(){
  const hist = SEARCH_HISTORY.length ? `
    <div class="home-head" style="margin-top:2px">
      <div class="section-label">最近搜索</div>
      <button class="linkbtn" onclick="clearSearchHistory()">清除</button>
    </div>
    ${SEARCH_HISTORY.map((h,i)=>`
      <div class="sr-item" onclick="useHistory(${i})">
        ${svg(I.clock)}<span class="grow t1" style="font-size:14px;font-weight:500">${esc(h)}</span>${svg(I.chev)}
      </div>`).join('')}` : `
    <div class="home-head" style="margin-top:2px"><div class="section-label">最近搜索</div></div>
    <div class="empty-box">还没有搜索记录</div>`;
  return `${hist}
    <div class="section-label">热门关键词</div>
    <div style="display:flex;flex-wrap:wrap;gap:8px">
      ${SEARCH_HOT.map((t,i)=>`<button class="fchip" onclick="useHot(${i})">${t}</button>`).join('')}
    </div>
    ${fnote('搜索',[
      '<b>四个范围</b>：仓库 / 用户 / 代码 / Issue · PR，切换范围只筛当前关键词，不丢输入',
      '<b>边输边搜</b>：无需点搜索按钮，输入即出结果；回车记录到「最近搜索」',
      '<b>结果可点</b>：仓库进仓库详情、代码进只读文件页、Issue·PR 进讨论详情、用户弹出资料卡',
      '<b>历史</b>：最近 8 条，点一条直接复用关键词，「清除」清空本机记录',
    ])}`;
}
function searchRepoPool(){
  return REPOS.concat(TRENDING.filter(t=>!REPOS.some(r=>r.n===t.n)));
}
function searchRows(q){
  const k = q.toLowerCase();
  if(searchState.scope==='repos') return searchRepoPool().filter(r=>hit(r.n+' '+r.d+' '+r.lang,k)).map(repoResultRow);
  if(searchState.scope==='users') return SEARCH_USERS.filter(u=>hit(u.u+' '+u.n+' '+u.bio,k)).map(userResultRow);
  if(searchState.scope==='code') return CODE_INDEX.filter(c=>hit(c.p+' '+c.l+' '+c.r+' '+c.lang,k)).map(codeResultRow);
  return ISSUES.filter(i=>hit(i.t+' '+i.c+' '+i.n,k)).map(i=>convResultRow(i,'issue'))
    .concat(PRS.filter(p=>hit(p.t+' '+p.n+' '+p.b,k)).map(p=>convResultRow(p,'pr')));
}
function repoResultRow(r){
  const parts = r.n.split('/'), owner = parts[0], name = parts.slice(1).join('/');
  return `
    <div class="sr-item" onclick="openSearchRepo('${r.n}')">
      <div class="repo-avatar">${svg(I.repo)}</div>
      <div class="grow">
        <div class="t1" style="font-size:14px"><span style="color:var(--text3);font-weight:500">${owner}/</span>${name}</div>
        <div class="t3" style="margin-top:3px">${esc(r.d||'—')}</div>
        <div style="margin-top:6px">
          ${r.lang?`<span class="chip"><span class="lang-dot" style="background:${r.lc||'#959da5'}"></span>${r.lang}</span>`:''}
          ${r.s?`<span class="chip">${svg(I.star)} ${r.s}</span>`:''}
        </div>
      </div>
      ${svg(I.chev)}
    </div>`;
}
function userResultRow(u){
  return `
    <div class="sr-item" onclick="openUserSheet('${u.u}')">
      <div class="avatar" style="background:${u.c}">${u.n[0].toUpperCase()}</div>
      <div class="grow">
        <div class="t1" style="font-size:14px">${u.n} <span style="color:var(--text3);font-weight:500">@${u.u}</span></div>
        <div class="t3" style="margin-top:3px">${esc(u.bio)}</div>
        <div class="t3" style="margin-top:4px">${u.repo} 个公开仓库 · ${u.fol} 关注者</div>
      </div>
      ${svg(I.chev)}
    </div>`;
}
function codeResultRow(c){
  return `
    <div class="sr-item" style="align-items:flex-start" onclick="openCodeFile('${c.p}')">
      ${svg(I.file)}
      <div class="grow">
        <div class="t1" style="font-size:13.5px;word-break:break-all">${esc(c.p)}</div>
        <div class="t3" style="margin-top:3px">${esc(c.r)} · ${c.lang}</div>
        <div class="sr-code">${esc(c.l)}</div>
      </div>
    </div>`;
}
function convResultRow(x, kind){
  const icon = kind==='pr' ? svg(I.pr,'ic-pr') : (x.s==='open' ? svg(I.issueO,'ic-open') : svg(I.issueC,'ic-closed-i'));
  return `
    <div class="sr-item" onclick="openConvRow('${kind}',${x.n})">
      <span class="state-row">${icon}</span>
      <div class="grow">
        <div class="t1" style="font-size:13.5px">${esc(x.t)}</div>
        <div class="t3" style="margin-top:3px">my-git/gitduo #${x.n}${x.d?' · '+x.d:''}</div>
      </div>
      ${pillOf(x.s)}
    </div>`;
}
function openSearchRepo(n){ recordTerm(); openRepo(n); }
function openCodeFile(p){ recordTerm(); push('fileView',{f:p,ro:1}); }
function openConvRow(kind,n){
  recordTerm();
  if(kind==='pr'){ const p = PRS.find(x=>x.n===n); push('prDetail',{n:p.n,t:p.t,s:p.s,u:p.u}); }
  else { const i = ISSUES.find(x=>x.n===n); push('issueDetail',{n:i.n,t:i.t,s:i.s}); }
}
function openUserSheet(u){
  const x = SEARCH_USERS.find(v=>v.u===u); if(!x) return;
  openSheet(`
    <div class="sheet-title">用户</div>
    <div class="row" style="gap:12px;padding:2px 8px 10px">
      <div class="avatar" style="width:52px;height:52px;font-size:19px;background:${x.c}">${x.n[0].toUpperCase()}</div>
      <div class="grow">
        <div class="t1" style="font-size:16px">${x.n}</div>
        <div class="t3" style="margin-top:3px">@${x.u} · ${x.repo} 个仓库 · ${x.fol} 关注者</div>
      </div>
    </div>
    <div class="t2" style="padding:0 8px 12px">${esc(x.bio)}</div>
    <button class="btn primary" style="width:100%;padding:11px" onclick="closeSheet();toast('演示：已关注 @${x.u}')">关注</button>
    <button class="btn ghost" style="width:100%;padding:11px;margin-top:8px" onclick="closeSheet();toast('演示：@${x.u} 的公开仓库列表')">查看公开仓库</button>`);
}

function repoMeta(n){ return REPOS.find(r=>r.n===n) || {n:n,d:'',lang:'',lc:'',s:'',f:'',priv:false}; }
function openRepo(n){ push(n.indexOf('my-git/')===0?'repoDetail':'exploreRepoDetail',{repo:n}); }
function managePins(){ toast('置顶仓库在 GitHub 个人主页管理 · 已为你打开'); }
// 2026-10-15 走查第 75 条：置顶卡改**行**（结构与 .recent-row 同款：头像 + 全名/描述 + 右侧一项）。
// 网格时代的两个约束随之作废：描述不再补 '—'（不等高也没关系了）、指标只留 Star
// （语言点 / Fork / 私有胶囊在半行宽里挤成一团，是"难看"的主要来源）。
function pinCard(n){
  const r = repoMeta(n), parts = n.split('/'), owner = parts[0], name = parts.slice(1).join('/');
  return `
    <div class="pin-card" onclick="openRepo('${n}')">
      <div class="repo-avatar">${svg(I.repo)}</div>
      <div class="grow">
        <div class="pn"><span class="pname"><span class="owner">${owner}/</span>${name}</span>${r.priv?'<span class="pill closed-i" style="margin-left:5px;font-size:10px;padding:1px 7px">私有</span>':''}</div>
        ${r.d?`<div class="pd">${r.d}</div>`:''}
      </div>
      ${r.s?`<span class="pm">${svg(I.star)} ${r.s}</span>`:''}
    </div>`;
}
function pinGrid(){
  if(!PINNED.length) return `<div class="empty-box">GitHub 个人主页还没有置顶仓库<br>去个人主页「Customize your pins」挑几个，回到首页下拉即可看到</div>`;
  return `<div class="pin-grid">${PINNED.map(pinCard).join('')}</div>`;
}
function recentRow(v){
  const r = repoMeta(v.n), parts = v.n.split('/'), owner = parts[0], name = parts.slice(1).join('/');
  return `
    <div class="recent-row" onclick="openRepo('${v.n}')">
      <div class="repo-avatar">${svg(I.repo)}</div>
      <div class="grow">
        <div class="t1" style="font-size:13.5px"><span style="color:var(--text3);font-weight:500">${owner}/</span>${name}${r.priv?'<span class="pill closed-i" style="margin-left:5px;font-size:10px;padding:1px 7px">私有</span>':''}</div>
        ${r.d?`<div class="t3" style="margin-top:2px">${r.d}</div>`:''}
      </div>
      <span class="t3" style="white-space:nowrap">${v.t}</span>
    </div>`;
}
function recentList(){
  if(!RECENT.length) return `<div class="empty-box">暂无访问记录<br>打开任意仓库后会自动出现在这里</div>`;
  return RECENT.map(recentRow).join('');
}
function openClearRecent(){
  openSheet(`
    <div class="sheet-title">清除最近访问记录？</div>
    <div class="sheet-hint" style="padding:2px 8px 12px">只清空本机的浏览历史，不影响仓库本身，也不会影响首页的置顶仓库。</div>
    <button class="btn primary" style="width:100%;padding:12px;background:var(--closed-p)" onclick="clearRecent()">清除全部记录</button>
    <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="closeSheet()">取消</button>`);
}
function clearRecent(){ RECENT = []; closeSheet(); paintTab(); toast('已清除最近访问记录'); }
function recordVisit(n){ RECENT = [{n:n,t:'刚刚'}].concat(RECENT.filter(v=>v.n!==n)).slice(0,6); }

