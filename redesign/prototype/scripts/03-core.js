/* ══ GitDuo 2.0 原型 · 03 · 导航内核（TABS / stacks / 分支记忆 / SCR 容器 / push·pop）+ 首页屏 ══ */
/* ============================================================ nav core */
const TABS = [
  {id:'home',label:'首页',icon:I.home},
  {id:'repos',label:'仓库',icon:I.folder},
  {id:'explore',label:'探索',icon:I.compass},
  {id:'me',label:'我的',icon:I.user},
];
let stacks = {
  home:[{id:'home',params:{}}],
  repos:[{id:'repos',params:{}}],
  explore:[{id:'explore',params:{}}],
  me:[{id:'me',params:{}}],
};
let active = 'home';
/* 分支：**按仓库分别记忆**（同一仓库内「代码」与「Commits」联动）。
   解析规则：记忆的分支仍存在于该仓库 → 用它；否则回落该仓库的默认分支。
   —— 绝不跨仓库共享，避免"从 A 仓库切到 feature/x，进 B 仓库也显示 feature/x 而 B 根本没有" */
const REPO_BRANCHES = {
  'my-git/gitduo':  {def:'main',   list:['main','feature/repo-hub','develop']},
  'my-git/notes':   {def:'main',   list:['main','gh-pages']},
  'my-git/scripts': {def:'main',   list:['main','release/2.0']},
  'rust-lang/rust': {def:'master', list:['master','beta','nightly']},
};
const BRANCH_SETS = [['main'],['main','gh-pages'],['master','dev'],['main','release/2.0'],['main','next']];
const branchByRepo = {};   // 仓库全名 → 分支（本次会话内记忆；登出清空）
let activeRepo = null;     // 当前打开的仓库详情页，由仓库屏 render 赋值
function repoBranchMeta(repo){
  if(!REPO_BRANCHES[repo]){
    // 未登记的仓库（探索榜等）：按仓库名生成一套稳定且互不相同的分支集，并登记下来供删改
    const seed = String(repo||'').split('').reduce((a,c)=>a+c.charCodeAt(0),0);
    const list = BRANCH_SETS[seed % BRANCH_SETS.length].slice();
    REPO_BRANCHES[repo] = { def:list[0], list };
  }
  return REPO_BRANCHES[repo];
}
function resolveBranch(repo){
  const meta = repoBranchMeta(repo);
  const remembered = branchByRepo[repo];
  return (remembered && meta.list.includes(remembered)) ? remembered : meta.def;
}
function curBranch(){ return resolveBranch(activeRepo); }

const SCR = {};
function push(id, params={}){
  stacks[active].push({id, params});
  paintTab();
}
function pop(){ if(stacks[active].length>1){ stacks[active].pop(); paintTab(); } }
function goTab(id){ active=id; paintTabbar(); paintTab(true); }

/* ============================================================ screens */
SCR.home = {
  large:true, render(){
    return `
    <div class="page-topbar">
      <div class="largetitle">首页</div>
      <button class="iconbtn" id="homeSearchBtn" title="搜索" onclick="openSearch()">${svg(I.search)}</button>
    </div>
    <div class="home-head">
      <div class="section-label">置顶仓库</div>
      <button class="linkbtn" onclick="managePins()">管理</button>
    </div>
    ${pinGrid()}
    <div class="home-head">
      <div class="section-label">最近访问</div>
      ${RECENT.length?`<button class="linkbtn" onclick="openClearRecent()">清除</button>`:''}
    </div>
    ${recentList()}
    ${fnote('首页',[
      '<b>置顶仓库</b>：只读同步 GitHub 个人主页的置顶（最多 6 个），卡片展示语言 / Star / Fork / 私有标记；GitHub 未开放置顶写接口，点「管理」跳网页端调整',
      '<b>最近访问</b>：打开过的仓库自动记录并排到最前，「清除」可清空本机历史',
      '<b>搜索</b>：右上角搜索图标进入搜索页，支持仓库 / 用户 / 代码 / Issue·PR 四个范围，边输边出结果',
      '<b>定位</b>：首页只做常用仓库的快速入口；仓库内的动态请看各仓库页',
    ])}`;
  }
};
