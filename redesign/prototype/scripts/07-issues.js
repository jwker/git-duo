/* ══ GitDuo 2.0 原型 · 07 · 标签（列表 / 新建）与新建 Issue ══ */
const REPO_LABELS = [
  {n:'bug',c:'#d73a4a'},{n:'enhancement',c:'#a2eeef'},{n:'docs',c:'#0075ca'},
  {n:'good first issue',c:'#7057ff'},{n:'help wanted',c:'#008672'}
];
const LBL_COLORS = ['#d73a4a','#e16f24','#fbca04','#0e8a16','#0075ca','#5319e7','#8250df','#db61a2','#959da5','#1f2328'];
let pickedClr = LBL_COLORS[0];
let niLabels = [];
SCR.newIssue = {
  inline:()=>'新建 Issue', render(){
    niLabels = [];
    return `
    <div class="content" style="display:flex;flex-direction:column;gap:10px">
      <div class="t3">目标仓库 · my-git/gitduo</div>
      <input class="sheet-input" id="niTitle" placeholder="标题">
      <textarea class="code-editor" id="niBody" style="min-height:150px" placeholder="描述（支持 Markdown）…"></textarea>
      <div class="section-label" style="margin:0">标签</div>
      <div id="niLblRow" class="row" style="gap:6px;flex-wrap:wrap;margin-top:-4px"></div>
      <button class="btn primary" style="width:100%;padding:12px" onclick="createIssue()">提交 Issue</button>
    </div>`;
  },
  after(){
    refreshLblRow();
  }
};
function refreshLblRow(){
  const el = document.getElementById('niLblRow');
  if(!el) return;
  el.innerHTML =
    niLabels.map(l=>`<span class="lbl-tag" style="background:${l.c}">${l.n}</span>`).join('') +
    `<button class="lbl-add" onclick="openLabelSheet()">＋ 标签 / 新建</button>`;
}
function openLabelSheet(){
  openSheet(`
    <div class="sheet-title">选择标签 · ${REPO_LABELS.length} 个</div>
    ${REPO_LABELS.map(l=>`
      <div class="sheet-row" onclick="toggleLabel('${l.n}')">
        <span class="lbl-dot" style="background:${l.c}"></span>
        <span class="grow">${l.n}</span>
        ${niLabels.some(x=>x.n===l.n)?'<b style="color:var(--green)">✓</b>':''}
      </div>`).join('')}
    <div class="sheet-title" style="margin-top:8px">新建标签</div>
    <input class="sheet-input" id="newLblName" placeholder="标签名称，如 performance">
    <div style="display:flex;gap:8px;margin:12px 0 4px;flex-wrap:wrap" id="clrRow">
      ${LBL_COLORS.map(c=>`<div class="clr-swatch ${c===pickedClr?'on':''}" style="background:${c}" onclick="pickClr(this,'${c}')"></div>`).join('')}
    </div>
    <button class="btn primary" style="width:100%;padding:11px;margin-top:10px" onclick="createLabel()">创建并选中</button>
    <div class="sheet-hint">新标签会保存到仓库标签列表，之后所有 Issue 都可直接选用</div>`);
}
function pickClr(el, c){
  pickedClr = c;
  document.querySelectorAll('#clrRow .clr-swatch').forEach(s=>s.classList.remove('on'));
  el.classList.add('on');
}
function toggleLabel(n){
  const l = REPO_LABELS.find(x=>x.n===n);
  niLabels = niLabels.some(x=>x.n===n) ? niLabels.filter(x=>x.n!==n) : [...niLabels, l];
  refreshLblRow(); openLabelSheet();
}
function createLabel(){
  const name = (document.getElementById('newLblName').value||'').trim();
  if(!name){ toast('请先填写标签名称'); return; }
  if(REPO_LABELS.some(l=>l.n===name)){ toast('标签已存在，已为你选中'); const ex=REPO_LABELS.find(l=>l.n===name); if(!niLabels.some(x=>x.n===name)) niLabels.push(ex); closeSheet(); refreshLblRow(); return; }
  const l = {n:name, c:pickedClr};
  REPO_LABELS.push(l); niLabels.push(l);
  closeSheet(); refreshLblRow();
  toast(`已创建标签 “${name}”`);
}
function createIssue(){
  const t=(document.getElementById('niTitle').value||'').trim()||'新 Issue';
  toast(`已创建 Issue #43 · “${t}”${niLabels.length?` · 标签 ${niLabels.length} 个`:''}`);
  pop();
}
