/* ══ GitDuo 2.0 原型 · 09 · 探索榜（新星 / 活跃 + 筛选） ══ */
SCR.explore = {
  large:true, render(){
    return `
    <div class="page-topbar">
      <div class="largetitle">探索</div>
      <button class="iconbtn" id="exploreSearchBtn" title="搜索" onclick="openSearch()">${svg(I.search)}</button>
    </div>
    <div class="segbar" id="exploreSeg" style="margin:0 0 12px">
      <button class="seg ${EXPLORE_BOARD==='rising'?'on':''}" data-b="rising" onclick="pickBoard(this,'rising')">新星榜</button>
      <button class="seg ${EXPLORE_BOARD==='active'?'on':''}" data-b="active" onclick="pickBoard(this,'active')">活跃榜</button>
    </div>
    <div class="row" style="gap:8px;margin:0 0 14px;flex-wrap:wrap">
      ${exploreChip('range')}${exploreChip('lang')}
    </div>
    <div class="section-label" id="trendTitle">${trendTitle()} · ${boardRows().length} 个仓库</div>
    <div id="trendList">${trendRows()}</div>
    ${fnote('探索',[
      '<b>两个榜</b>：新星榜（近 90 天新建 · 按新增 Star 排序）/ 活跃榜（近期有推送 · 按最近推送排序），同一批仓库两个视角',
      '<b>筛选</b>：日期范围 / 编程语言两个下拉；不选 = 全部，再点当前选中项即取消',
      '<b>趋势列表</b>：新星榜按日期范围缩放"新增 Star"，活跃榜按时间窗过滤推送',
      '<b>请求</b>：切榜 / 切筛选按「榜 · 日期 · 语言」复用缓存，来回切换不重复请求（Search 配额独立且很紧）',
      '<b>搜索</b>：右上角放大镜进入搜索页，与首页、仓库页同一个页面',
      '<b>进入</b>：点卡片进他人仓库只读浏览页（Star / Watch / Fork / 收藏）',
    ])}`;
  }
};
const EXPLORE_FILTERS = { range:'本周', lang:'' };
let EXPLORE_BOARD = 'rising';
const BOARDS = { rising:'新星榜', active:'活跃榜' };
const BASE_DATE = new Date('2026-10-05T00:00:00Z');  // 演示基准日：静态数据下保证排序稳定
const NEW_DAYS = 90;
const RANGE_OPTS = ['今天','本周','本月'];
const RANGE_LABEL = {'今天':'今日','本周':'本周','本月':'本月'};
const LANG_OPTS = ['Swift','Rust','TypeScript','Python','Go'];
const FILTER_META = {
  range:{ title:'日期范围', opts:()=>RANGE_OPTS, blank:'日期' },
  lang:{ title:'编程语言', opts:()=>LANG_OPTS, blank:'语言' }
};
function exploreChip(key){
  const meta = FILTER_META[key];
  const val = EXPLORE_FILTERS[key];
  const label = val || meta.blank || val;
  return `<button class="fchip ${val?'on':''}" onclick="openFilterSheet('${key}')">${label} ${svg(I.chevD)}</button>`;
}
function openFilterSheet(key){
  const meta = FILTER_META[key];
  const cur = EXPLORE_FILTERS[key];
  const hint = cur ? '再次点击已选语言可取消，取消后显示全部' : '不选则显示全部';
  openSheet(`
    <div class="sheet-title">${meta.title}</div>
    ${meta.opts().map(o=>`
      <div class="sheet-row" onclick="pickFilter('${key}','${o}')">
        <span class="grow">${o}</span>
        ${cur===o?'<b style="color:var(--green)">✓</b>':''}
      </div>`).join('')}
    <div class="sheet-hint">${hint}</div>`);
}
function pickFilter(key, val){
  const meta = FILTER_META[key];
  if(EXPLORE_FILTERS[key]===val){ EXPLORE_FILTERS[key]=''; closeSheet(); paintTab(); toast(`${meta.title}：已取消，显示全部`); return; }
  EXPLORE_FILTERS[key] = val;
  closeSheet(); paintTab();
  toast(`${meta.title}：${val}`);
}
function daysSince(dateStr){ return (BASE_DATE - new Date(dateStr+'T00:00:00Z')) / 86400000; }
/* 榜单取数：新星榜=近 90 天新建，按新增 Star 排序；活跃榜=时间窗内有推送，按最近推送排序 */
function boardRows(){
  const f = EXPLORE_FILTERS;
  let list = TRENDING.filter(t=>
    (!f.lang||t.lang===f.lang));
  const win = {'今天':1440,'本周':10080,'本月':43200}[f.range] || 10080;
  if(EXPLORE_BOARD==='rising'){
    list = list.filter(t=>daysSince(t.created)<=NEW_DAYS).sort((a,b)=>b.st-a.st);
  }else{
    list = list.filter(t=>t.pushedM<=win).sort((a,b)=>a.pushedM-b.pushedM);
  }
  return list;
}
function trendTitle(){ return BOARDS[EXPLORE_BOARD] || '趋势'; }
function paintTrend(){
  const tt = document.getElementById('trendTitle');
  if(tt) tt.textContent = `${trendTitle()} · ${boardRows().length} 个仓库`;
  const tl = document.getElementById('trendList');
  if(tl) tl.innerHTML = trendRows();
}
function pickBoard(el, b){
  if(EXPLORE_BOARD===b) return;
  EXPLORE_BOARD = b;
  document.querySelectorAll('#exploreSeg .seg').forEach(x=>x.classList.toggle('on', x.dataset.b===b));
  paintTrend();
}
function trendRows(){
  const list = boardRows();
  if(!list.length) return `<div class="t3" style="text-align:center;padding:28px 0">没有符合条件的仓库，试试放宽筛选</div>`;
  const rl = RANGE_LABEL[EXPLORE_FILTERS.range] || '近期';
  const mult = {'今天':1/7,'本周':1,'本月':4.3}[EXPLORE_FILTERS.range] || 1;
  return list.map(t=>{
    const gain = `+${Math.max(1,Math.round(t.st*mult))} ${rl}`;
    const metric = EXPLORE_BOARD==='rising'
      ? `<span class="chip" style="color:var(--green);font-weight:650">${gain}</span><span class="chip">🆕 ${t.created.slice(5)} 创建</span>`
      : `<span class="chip" style="color:var(--green);font-weight:650">⚡ ${t.upd}推送</span>`;
    return `
      <div class="card" onclick="push('exploreRepoDetail',{repo:'${t.n}'})">
        <div class="row">
          <div class="repo-avatar">${svg(I.repo)}</div>
          <div class="grow">
            <div class="t1" style="color:var(--link)">${t.n}</div>
            <div class="t2" style="margin-top:2px">${t.d}</div>
            <div style="margin-top:7px">
              <span class="chip"><span class="lang-dot" style="background:${t.lc}"></span>${t.lang}</span>
              <span class="chip">${svg(I.star)} ${t.s}</span>
              ${metric}
            </div>
          </div>
        </div>
      </div>`;
  }).join('');
}

