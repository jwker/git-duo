/* ══ GitDuo 2.0 原型 · 14 · 渲染外壳（screenHTML / paintTab / paintTabbar / 分段切换） ══ */
/* ============================================================ painting */
const backBtn = `<button class="back" onclick="backOrPop()">${svg(I.back)}返回</button>`;
/* 导航栏右侧的动作位。`SCR.<屏>.action` 可选（字符串或 `p => 字符串`）—— 不写就没有。
   ⚠️ 2026-10-14 新增：代码页那颗「⋯」从**面包屑右侧**搬到了导航栏右上角
      （用户要求与文件页统一）⇒ 外壳需要长出一个右侧槽。
   ⚠️ 目前**只有代码页**用它。别的屏若要加，直接给那份 `SCR` 定义一个 `action` 就行。 */
function navAction(scr, params){
  if(!scr.action) return '';
  const html = typeof scr.action === 'function' ? scr.action(params) : scr.action;
  return html || '';
}
function screenHTML(entry, pos){
  const scr = SCR[entry.id];
  if(!scr) throw new Error('unknown screen: '+entry.id);
  const head = scr.large ? '' : `<div class="navbar">${backBtn}<div class="ntitle">${scr.inline?scr.inline(entry.params):''}</div>${navAction(scr, entry.params)}</div>`;
  const cls = scr.large ? 'screen '+pos : 'screen pushed '+pos;
  const body = scr.large ? `<div class="tabpage">${scr.render(entry.params)}</div>` : scr.render(entry.params);
  return `<div class="${cls}">${head}${body}</div>`;
}
function paintTab(fade){
  const area = document.getElementById('stackArea');
  const st = stacks[active];
  area.innerHTML = st.map((e,i)=>{
    if(i===st.length-1) return screenHTML(e,'top');
    if(i===st.length-2) return screenHTML(e,'under');
    return screenHTML(e,'off');
  }).join('');
  if(fade){ const top=area.lastElementChild; top.style.opacity=0; requestAnimationFrame(()=>{top.style.opacity=1;}); }
  const topEntry = st[st.length-1];
  const topScr = SCR[topEntry.id];
  if(topScr && topScr.after) topScr.after(topEntry.params);
}
function paintTabbar(){
  document.getElementById('tabbar').innerHTML = TABS.map(t=>`
    <div class="tab ${active===t.id?'on':''}" onclick="goTab('${t.id}')">
      ${svg(t.icon)}<span>${t.label}</span>
    </div>`).join('');
}
function segPick(btn){
  [...btn.parentElement.children].forEach(b=>b.classList.remove('on'));
  btn.classList.add('on');
}
function switchPrSeg(btn, seg){
  document.getElementById('prSegBody').innerHTML = prSeg(seg);
  [...btn.parentElement.querySelectorAll('button')].forEach(b=>b.classList.remove('on'));
  btn.classList.add('on');
}
function toggleStar(){
  const b=document.getElementById('starBtn');
  b.classList.toggle('starred');
  b.querySelector('span').textContent = b.classList.contains('starred') ? '已 Star · 129' : 'Star · 128';
}
function fakeSend(){  const e=document.getElementById('sendErr');
  e.style.display='block';
  setTimeout(()=>{ e.style.display='none'; }, 2600);
}
function unstar(ev, btn){
  ev.stopPropagation();
  if(btn.textContent.indexOf('已')===0){ btn.textContent='Star'; }
  else { btn.textContent='已 Star'; }
}

