/* ══ GitDuo 2.0 原型 · 15 · 弹层与提示原语 + 分支切换 / 添加文件 / 提交 ══ */
/* ============================================================ sheets / toast / git ops */
function toast(msg){
  const t=document.createElement('div'); t.className='toast'; t.textContent=msg;
  document.getElementById('phone').appendChild(t);
  setTimeout(()=>t.remove(), 2400);
}
function openSheet(html){
  document.getElementById('sheetHost').innerHTML =
    `<div class="sheet-mask" onclick="closeSheet()"></div><div class="sheet">${html}</div>`;
}
function closeSheet(){ document.getElementById('sheetHost').innerHTML=''; }
function switchBranch(b){
  const meta = repoBranchMeta(activeRepo);
  if(!meta.list.includes(b)){ toast('该分支不属于当前仓库'); return; }
  branchByRepo[activeRepo] = b;   // 只改当前仓库的记忆，其它仓库的分支不受影响
  closeSheet(); paintTab(); toast('已切换到 '+b);
}
function openBranchSheet(own){
  own = own!==false;
  const meta = repoBranchMeta(activeRepo), cb = curBranch();
  openSheet(`
    <div class="sheet-title">${own?'切换分支 · 代码与 Commits 联动':'切换分支 · 浏览他人仓库'}</div>
    ${meta.list.map(b=>`
      <div class="sheet-row" onclick="switchBranch('${b}')">${svg(I.fork)}<span class="grow">${b}</span>${b===cb?'<b style="color:var(--green)">✓</b>':''}</div>`).join('')}
    ${own?`<div class="sheet-row" onclick="closeSheet();push('branches')">${svg(I.dir)}<span class="grow">管理分支…（创建 / 删除 / 合并）</span>${svg(I.chev)}</div>`
         :`<div class="sheet-hint">他人仓库：可切换分支浏览，创建 / 删除 / 合并需先 Fork</div>`}`);
}
function openAddSheet(){
  openSheet(`
    <div class="sheet-title">添加文件 · ${curBranch()}</div>
    <div class="sheet-row" onclick="closeSheet();push('editor',{f:'NewFile.swift',mode:'create'})">${svg(I.file)}<span class="grow">新建文件</span></div>
    <div class="sheet-row" onclick="closeSheet();openCommitSheet('上传文件（文件 App）')">${svg(I.file)}<span class="grow">上传文件 · 文件 App</span></div>
    <div class="sheet-row" onclick="closeSheet();openCommitSheet('上传图片（相册）')">${svg(I.file)}<span class="grow">上传图片 · 相册</span></div>
    <div class="sheet-hint">≤1MB 走 Contents API · 大文件走 Git Data API（blob → tree → commit → ref，上限 100MB）</div>`);
}
let commitSrc = '编辑';
let commitNew = false;
function openCommitSheet(src){
  commitSrc = src||'编辑'; commitNew = false;
  openSheet(`
    <div class="sheet-title">提交更改 · ${commitSrc}</div>
    <textarea class="sheet-input" id="cmsg" rows="2" placeholder="提交信息（commit message）"></textarea>
    <div class="segbar" style="margin:10px 0 6px">
      <button class="seg on" onclick="pickTarget(this,false)">提交到 ${curBranch()}</button>
      <button class="seg" onclick="pickTarget(this,true)">新分支 + PR</button>
    </div>
    <div class="sheet-hint" id="newBranchRow" style="display:none;background:var(--add-bg);color:var(--add-tx);border-radius:8px;padding:8px 10px">将创建新分支并自动打开 Pull Request，改动不直接进 ${curBranch()}</div>
    <button class="btn primary" style="width:100%;padding:12px" onclick="doCommit()">提交</button>
    <div class="sheet-hint">冲突保护：提交遇 409（远端已更新）时，可选查看最新版或强制覆盖</div>`);
}
function pickTarget(btn, isNew){
  commitNew = isNew;
  [...btn.parentElement.children].forEach(b=>b.classList.remove('on'));
  btn.classList.add('on');
  document.getElementById('newBranchRow').style.display = isNew?'block':'none';
}
function doCommit(){
  const msg=(document.getElementById('cmsg').value||'').trim()||'update via GitDuo';
  closeSheet();
  toast(commitNew ? `已提交到新分支并创建 PR #58 · “${msg}”` : `已提交到 ${curBranch()} · “${msg}”`);
  const st=stacks[active], top=st[st.length-1];
  if(top.id==='editor') pop();
}

