/* ══ GitDuo 2.0 原型 · 11 · 收藏夹（归属映射 / 增删改 / 计数派生） ══ */
const FOLDERS = [{n:'默认收藏夹',d:true},{n:'前端好项目'},{n:'Swift 学习'},{n:'以后再看'}];
const DEFAULT_FOLDER = '默认收藏夹';
const favMap = {};              // 仓库全名 → 收藏夹名（单一数据源）
/* 演示种子：把「初始项目数」也放进 favMap（合成仓库名，不会渲染成仓库卡片、也不会与真实仓库碰撞），
   于是删除收藏夹时计数是真的搬去默认夹——与文案「回落到『默认收藏夹』、默认夹 +N」对得上。 */
const FAV_SEED = {'前端好项目':2,'Swift 学习':5,'以后再看':12};
Object.keys(FAV_SEED).forEach(fn=>{ for(let i=1;i<=FAV_SEED[fn];i++) favMap[`seed/${fn}-${i}`]=fn; });
let favPendingRepo = null;      // 「选择收藏列表」弹层当前操作的仓库
function folderByName(n){ return FOLDERS.find(x=>x.n===n); }
function favTotal(folderName){  // 项目数 = 归属该夹的仓库数（派生，永不手工增减）
  return Object.keys(favMap).filter(k=>favMap[k]===folderName).length;
}
function favFolderOf(repo){ return favMap[repo] || null; }
function favSet(repo, folder){      // 收藏 / 换夹：只改归属，计数自动跟随
  if(favFolderOf(repo)===folder) return;
  favMap[repo] = folder;
}
function favUnset(repo){            // 取消收藏：只删归属，计数自动跟随
  delete favMap[repo];
}
function favNow(repo){
  favSet(repo, DEFAULT_FOLDER);
  paintTab();
  toast('已收藏到「默认收藏夹」（私人，不影响 Star 数）· 再点可选择列表');
}
function openFavSheet(repo){
  favPendingRepo = repo;
  const cur = favFolderOf(repo);
  openSheet(`
    <div class="sheet-title">选择收藏列表</div>
    ${FOLDERS.map(f=>`
      <div class="sheet-row" onclick="pickFav('${f.n}')">
        ${svg(I.bm)}<span class="grow">${f.n}</span><span class="t3">${favTotal(f.n)} 项</span>
        ${cur===f.n?'<b style="color:var(--green)">✓</b>':''}
      </div>`).join('')}
    <div class="sheet-row" onclick="newFavForm()">${svg(I.plus)}<span class="grow">新建收藏夹…</span>${svg(I.chev)}</div>
    <div class="sheet-hint">选择列表收藏 · 再点已选列表取消收藏 · 一个仓库只在一个列表里</div>`);
}
function pickFav(list){
  const repo = favPendingRepo;
  if(favFolderOf(repo)===list){ favUnset(repo); closeSheet(); paintTab(); toast('已从收藏移除'); return; }
  favSet(repo, list);
  closeSheet(); paintTab(); toast(`已收藏到「${list}」（私人收藏夹）`);
}
function newFavForm(){
  openSheet(`
    <div class="sheet-title">新建收藏夹</div>
    <input class="sheet-input" id="favName" placeholder="收藏夹名称">
    <button class="btn primary" style="width:100%;padding:12px;margin-top:8px" onclick="createFav()">创建并收藏</button>`);
}
function createFav(){
  const name = (document.getElementById('favName').value||'').trim();
  if(!name){ toast('先输入收藏夹名称'); return; }
  if(FOLDERS.some(f=>f.n===name)) toast('收藏夹已存在，已为你选中');
  else { FOLDERS.push({n:name}); toast(`已创建收藏夹「${name}」`); }
  favSet(favPendingRepo, name);   // 计数随映射增减（若原本在别的夹，源夹会 −1）
  closeSheet(); paintTab();
}

/* 收藏夹管理页 → 重命名 / 删除 */
let favTarget = null;
SCR.folders = {
  inline:()=>'我的收藏', render(){
    return `
    <div class="content">
      <div class="t3" style="padding:2px 2px 4px;line-height:1.6">私人整理 · 仅你自己可见，不影响仓库的 Star 数</div>
      <div class="menu-card" id="folderList">
        ${FOLDERS.map((f,i)=>`
          <div class="menu-item" ${f.d?'':`onclick="openFolderSheet(${i})"`}>
            ${svg(I.bm)} ${f.n}
            <span style="margin-left:auto" class="t3">${favTotal(f.n)} 项</span>
            ${f.d?'<span class="ftag">默认</span>':`<span class="chev">${svg(I.chev)}</span>`}
          </div>`).join('')}
      </div>
      <button class="btn ghost" style="width:100%;padding:11px" onclick="newFolderForm()">${svg(I.plus)} 新建收藏夹</button>
      <div class="t3" style="text-align:center;margin-top:10px;line-height:1.7">「默认收藏夹」是新收藏的默认去处，不可重命名或删除<br>删除其它收藏夹不会取消 Star，也不会影响仓库本身</div>
      ${fnote('我的收藏',[
        '<b>列表</b>：每个收藏夹展示名称与项目数；「默认收藏夹」带默认标记，不可重命名 / 删除',
        '<b>管理</b>：点任一自建收藏夹 → 打开操作菜单（重命名 / 删除收藏夹）',
        '<b>重命名</b>：空名或与其它收藏夹重名会被拦截；重命名不影响已收藏的仓库',
        '<b>删除</b>：二次确认；删除后其中的收藏记录<b>回落到「默认收藏夹」</b>（默认夹计数相应 +N，收藏并未丢失；不影响 Star 与仓库本身）',
        '<b>新建</b>：底部「新建收藏夹」；重名会被拦截',
        '<b>入口</b>：我的 → 我的收藏；仓库详情页「收藏」按钮里的列表与此处是同一份数据',
      ])}
    </div>`;
  }
};
function openFolderSheet(i){
  const f = FOLDERS[i]; if(!f) return; favTarget = f;
  openSheet(`
    <div class="sheet-title">${f.n} · ${favTotal(f.n)} 项</div>
    <div class="sheet-row" onclick="renameFolderForm()">${svg(I.pencil)}<span class="grow">重命名</span></div>
    <div class="sheet-row" style="color:var(--closed-p)" onclick="deleteFolderConfirm()">${svg(I.trash)}<span class="grow">删除收藏夹</span></div>
    <div class="sheet-hint">删除收藏夹后，其中的收藏记录会回落到「默认收藏夹」，不影响仓库本身</div>`);
}
function renameFolderForm(){
  if(!favTarget) return;
  const i = FOLDERS.indexOf(favTarget);
  openSheet(`
    <div class="sheet-title">重命名收藏夹</div>
    <input class="sheet-input" id="folderName" value="${favTarget.n}">
    <button class="btn primary" style="width:100%;padding:12px;margin-top:8px" onclick="renameFolder()">保存</button>
    <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="openFolderSheet(${i})">取消</button>`);
}
function renameFolder(){
  if(!favTarget) return;
  const name = (document.getElementById('folderName').value||'').trim();
  if(!name){ toast('先输入收藏夹名称'); return; }
  if(name===favTarget.n){ closeSheet(); return; }
  if(FOLDERS.some(f=>f!==favTarget && f.n===name)){ toast('已有同名收藏夹'); return; }
  const old = favTarget.n;
  favTarget.n = name;
  Object.keys(favMap).forEach(k=>{ if(favMap[k]===old) favMap[k]=name; });   // 映射跟随改名，计数不变
  closeSheet(); paintTab(); toast(`已重命名为「${name}」`);
}
function deleteFolderConfirm(){
  const f = favTarget; if(!f) return;
  if(f.d){ toast('「默认收藏夹」不可删除'); return; }
  const i = FOLDERS.indexOf(f), n = favTotal(f.n);
  openSheet(`
    <div class="sheet-title">删除「${f.n}」？</div>
    <div class="sheet-hint" style="padding:2px 8px 12px">其中的 ${n} 项收藏记录会回落到「默认收藏夹」（默认收藏夹计数相应 +${n}），收藏并未丢失。这不会取消 Star，也不会影响仓库本身。</div>
    <button class="btn primary" style="width:100%;padding:12px;background:var(--closed-p)" onclick="deleteFolder()">删除收藏夹</button>
    <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="openFolderSheet(${i})">取消</button>`);
}
function deleteFolder(){
  const i = FOLDERS.indexOf(favTarget);
  if(i<0 || FOLDERS[i].d) return;
  const n = FOLDERS[i].n;
  const moved = favTotal(n);
  FOLDERS.splice(i,1);
  // 其中的收藏项回落默认夹（不留"收藏到已不存在的列表"的悬空归属）；计数由 favMap 派生，默认夹自动 +moved
  Object.keys(favMap).forEach(k=>{ if(favMap[k]===n) favMap[k]=DEFAULT_FOLDER; });
  favTarget = null;
  closeSheet(); paintTab(); toast(`已删除收藏夹「${n}」· ${moved} 项已回落到「${DEFAULT_FOLDER}」`);
}
function newFolderForm(){
  openSheet(`
    <div class="sheet-title">新建收藏夹</div>
    <input class="sheet-input" id="folderNewName" placeholder="收藏夹名称">
    <button class="btn primary" style="width:100%;padding:12px;margin-top:8px" onclick="createFolder()">创建</button>`);
}
function createFolder(){
  const name = (document.getElementById('folderNewName').value||'').trim();
  if(!name){ toast('先输入收藏夹名称'); return; }
  if(FOLDERS.some(f=>f.n===name)){ toast('收藏夹已存在'); return; }
  FOLDERS.push({n:name});
  closeSheet(); paintTab(); toast(`已创建收藏夹「${name}」`);
}

