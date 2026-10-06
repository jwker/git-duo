/* ══ GitDuo 2.0 原型 · 14 · 渲染外壳（screenHTML / paintTab / paintTabbar / 分段切换） ══ */
/* ============================================================ painting */
const backBtn = `<button class="back" onclick="pop()">${svg(I.back)}返回</button>`;
function screenHTML(entry, pos){
  const scr = SCR[entry.id];
  if(!scr) throw new Error('unknown screen: '+entry.id);
  const head = scr.large ? '' : `<div class="navbar">${backBtn}<div class="ntitle">${scr.inline?scr.inline(entry.params):''}</div></div>`;
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
function switchRepoSeg(btn, seg){
  const st = stacks[active];
  const entry = st[st.length-1];
  entry.params.seg = seg;
  document.getElementById('repoSegBody').innerHTML = repoSeg(seg, entry.params);
  [...document.getElementById('repoSegTabs').querySelectorAll('button')].forEach(b=>b.classList.remove('on'));
  btn.classList.add('on');
}
function switchPrSeg(btn, seg){
  document.getElementById('prSegBody').innerHTML = prSeg(seg);
  [...btn.parentElement.querySelectorAll('button')].forEach(b=>b.classList.remove('on'));
  btn.classList.add('on');
}
function navToSub(sub){
  const st=stacks[active];
  for(let i=st.length-1;i>=1;i--){
    const e=st[i];
    if(e.id==='repoDetail' && (e.params.sub||'')===sub){ st.length=i+1; paintTab(); return; }
  }
  const idx=st.map(e=>e.id).lastIndexOf('repoDetail');
  if(idx>=1){
    st.length=idx+1;
    push('repoDetail',{repo:st[idx].params.repo,seg:'code',sub:sub||undefined});
  }
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

