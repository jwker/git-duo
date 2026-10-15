/* ══ GitDuo 2.0 原型 · 12 · 我的 / Star 管理 / 设置 ══ */
SCR.me = {
  large:true, render(){
    return `
    <div class="largetitle">我的</div>
    <div class="profile-head">
      <div class="big-avatar" style="background:linear-gradient(135deg,#1f883d,#0969da)">J</div>
      <h2>Jiang Jiang</h2>
      <div class="login">@jiangjiang</div>
      <div class="bio">iOS / SwiftUI 开发者。在做 GitHub 客户端 GitDuo。</div>
      <div class="pstats">
        <div class="pstat"><b>42</b><span>仓库</span></div>
        <div class="pstat" onclick="push('stars')"><b>318</b><span>Star</span></div>
        <div class="pstat"><b>126</b><span>Follower</span></div>
      </div>
    </div>
    <div class="heatmap">
      <div class="row" style="margin-bottom:10px"><span class="t1" style="font-size:14px">1,024 次贡献</span>
      <span class="t3" style="margin-left:auto">过去一年</span></div>
      <div class="hm-grid">${hm()}</div>
    </div>
    <div class="menu-card">
      <div class="menu-item" style="--ic:var(--gold)" onclick="push('stars')">${svg(I.star)} Star 管理<span class="chev">${svg(I.chev)}</span></div>
      <div class="menu-item" style="--ic:var(--link)" onclick="push('folders')">${svg(I.bm)} 我的收藏<span class="chev">${svg(I.chev)}</span></div>
      <div class="menu-item" style="--ic:var(--link)" onclick="push('prDetail',{n:57,t:'我创建的 Pull Request',s:'open'})">${svg(I.pr)} 我的 Pull Request<span class="chev">${svg(I.chev)}</span></div>
      <div class="menu-item" style="--ic:var(--green)" onclick="push('issueDetail',{n:42,t:'我创建的 Issue',s:'open'})">${svg(I.issueO)} 我的 Issue<span class="chev">${svg(I.chev)}</span></div>
    </div>
    <div class="menu-card">
      <div class="menu-item" onclick="push('settings')">${svg(I.gear)} 设置<span class="chev">${svg(I.chev)}</span></div>
    </div>`;
  }
};
function hm(){
  let s='';
  for(let w=0;w<40;w++) for(let d=0;d<7;d++){
    const r=Math.random(), lv=r<.45?0:r<.7?1:r<.87?2:r<.96?3:4;
    s+=`<div class="hm-cell ${lv?'l'+lv:''}"></div>`;
  }
  return s;
}
SCR.stars = {
  inline:()=>'我的 Star', render(){
    return `
    <div class="content">
      ${REPOS.filter(r=>!r.priv).map(r=>`
        <div class="card">
          <div class="row">
            <div class="repo-avatar">${svg(I.repo)}</div>
            <div class="grow" onclick="push('${r.n.startsWith('my-git/')?'repoDetail':'exploreRepoDetail'}',{repo:'${r.n}'})">
              <div class="t1" style="color:var(--link)">${r.n}</div>
              <div class="t3" style="margin-top:3px">${svg(I.star)} ${r.s} · ${r.lang}</div>
            </div>
            <button class="btn ghost" style="padding:7px 12px" onclick="unstar(event,this)">已 Star</button>
          </div>
        </div>`).join('')}
    </div>`;
  }
};
SCR.settings = {
  inline:()=>'设置', render(){
    return `
    <div class="content">
      <div class="section-label">外观</div>
      <div class="menu-card">
        <div class="menu-item">主题<span style="margin-left:auto" class="t3">浅色</span></div>
      </div>
      <div class="section-label">账户</div>
      <div class="menu-card">
        <div class="menu-item">GitHub App · my-git<span style="margin-left:auto" class="t3">已授权</span></div>
        <div class="menu-item" style="color:var(--closed-p)" onclick="openSignOutSheet()">退出登录</div>
      </div>
      <div class="section-label">关于</div>
      <div class="menu-card">
        <div class="menu-item">清除缓存<span style="margin-left:auto" class="t3">12.4 MB</span></div>
        <div class="menu-item">版本<span style="margin-left:auto" class="t3">2.0 (1)</span></div>
      </div>
    </div>`;
  }
};

