/* ══ GitDuo 2.0 原型 · 13 · 登录页 / 授权页 / 退出登录 ══ */
/* ============================================================ 登录页 / 授权页 */
/* 真实链路：GitHub App + PKCE（无后端）→ ASWebAuthenticationSession 打开 github.com 授权页
   → 回调 gitduo://oauth/callback → 换 ghu_ 令牌写 Keychain。原型里授权页用浏览器卡片模拟。 */
const AUTH_PERMS = [
  {t:'仓库内容',d:'读取代码 / 文件树；提交、新建、上传文件（读写）',i:I.repo},
  {t:'Issues',d:'查看、创建、评论、开关（读写）',i:I.issueO},
  {t:'Pull Requests',d:'查看、创建、评论、合并（读写）',i:I.pr},
  {t:'Star 收藏',d:'Star / 取消 Star 仓库，读取 Starred 列表（读写）',i:I.star},
  {t:'关注关系',d:'关注 / 取关用户（读写）',i:I.people},
  {t:'账号基本信息',d:'读取公开资料、贡献数据与关注列表（只读）',i:I.user},
];
let authStep = null;   // null=已登录 · 'login' · 'authorize' · 'granting'
function authHTML(){
  const host = document.getElementById('authFlow');
  host.classList.toggle('on', !!authStep);
  host.innerHTML = authStep ? (authStep==='login' ? authLoginHTML() : authBrowserHTML()) : '';
}
function authLoginHTML(){
  return `
  <div class="authpage">
    <div class="auth-hero">
      <div class="gh-mark">${GH_MARK}</div>
      <h1>GitDuo</h1>
      <div class="tagline">为 iPhone 打造的 GitHub 客户端<br>代码 · Issues · Pull Requests 一站浏览</div>
    </div>
    <div class="auth-permcard">
      <div class="pt">登录后 GitDuo 会申请</div>
      ${AUTH_PERMS.map(p=>`<div class="auth-perm">${svg(I.check)}<span><b>${p.t}</b> · ${p.d}</span></div>`).join('')}
    </div>
    <div class="auth-foot">
      <button class="btn github" onclick="toAuthPage()">${GH_MARK}<span>使用 GitHub 登录</span></button>
      <div class="auth-note">授权在系统浏览器中完成 · 密码不经过 GitDuo<br>令牌存于本机 Keychain，退出登录即同时撤销 GitHub 侧授权<br><b>安装页请选「All repositories（全部仓库）」</b>，否则 GitDuo 只能看到被勾选的那部分仓库</div>
      ${fnote('登录页', [
        '<b>未登录首屏</b>：启动时若 Keychain 无有效令牌，进入本页；底部 4 Tab 此时不可用',
        '<b>权限预告</b>：列出的 6 项即 GitHub App 安装时勾选的范围，与授权页清单一致',
        '<b>登录方式</b>：仅 GitHub 一种，不做账号密码、不做第三方登录',
        '<b>安全</b>：GitHub App + PKCE + 一次性 state 校验；令牌只写 Keychain。客户端内嵌的 secret 属"软机密"（官方要求且不区分客户端类型），**不是防线**',
        '<b>安装范围</b>：GitHub App 令牌可见范围 = 用户权限 ∩ App 权限 ∩ 安装时勾选的仓库；必须引导选 All repositories',
        '<b>退出后</b>：「我的 → 设置 → 退出登录」先撤销 GitHub 侧授权、再清空本机令牌并回到本页（撤销失败仍会登出，仅提示降级）',
      ])}
    </div>
  </div>`;
}
function authBrowserHTML(){
  const busy = authStep === 'granting';
  return `
  <div class="auth-browser">
    <div class="browser-card">
      <div class="browser-bar">
        <button onclick="cancelAuth()">取消</button>
        <div class="url">${svg(I.lock)} github.com</div>
        <button style="visibility:hidden">取消</button>
      </div>
      <div class="browser-body">
        ${busy ? `
          <div class="auth-spin">
            <div class="spinner"></div>
            <div class="st">正在完成授权…</div>
            <div class="ss">已收到回调 gitduo://oauth/callback<br>正在用授权码换取令牌并写入 Keychain</div>
          </div>`
        : `
          <div class="gmark">${GH_MARK}</div>
          <h2>Authorize GitDuo</h2>
          <div class="sub"><b>my-git</b> 想要访问你的 <b>@jiangjiang</b> 账户</div>
          <div class="gh-permbox">
            ${AUTH_PERMS.map(p=>`<div class="gh-perm">${svg(p.i,'pico')}<div><b>${p.t}</b><span>${p.d}</span></div></div>`).join('')}
          </div>
          <div class="gh-secnote">GitDuo 由 my-git 开发，将获得以上权限；你随时可以在 GitHub 设置的 Applications 中撤销访问。取消请点左上角「取消」。</div>
          <button class="btn primary" onclick="approveAuth()">Authorize my-git</button>`}
      </div>
    </div>
  </div>`;
}
function openAuth(){ authStep='login'; authHTML(); }
function toAuthPage(){ authStep='authorize'; authHTML(); }
function cancelAuth(){ authStep='login'; authHTML(); }
function approveAuth(){
  authStep='granting'; authHTML();
  setTimeout(()=>{
    authStep=null; authHTML();
    paintTabbar(); paintTab(true);
    toast('已登录 · 欢迎回来，@jiangjiang');
  }, 900);
}
function openSignOutSheet(){
  openSheet(`
    <div class="sheet-title">退出登录？</div>
    <div class="sheet-hint" style="padding:2px 8px 12px">将清除本机 Keychain 中的访问令牌与缓存，并撤销 GitHub 侧的授权（授权记录不再出现在 GitHub 设置里）。下次使用需要重新授权，但无需重新安装 App。</div>
    <button class="btn primary" style="width:100%;padding:12px;background:var(--closed-p)" onclick="signOut()">退出登录</button>
    <button class="btn ghost" style="width:100%;padding:12px;margin-top:8px" onclick="closeSheet()">取消</button>`);
}
/* 登出 = ① 撤销 GitHub 侧授权（DELETE /applications/{client_id}/grant，TECH_SPEC §3.6）
   → ② 清本地凭据 → ③ 清账号绑定数据 → ④ 重置导航栈。
   撤销失败（离线 / 422 / 网络错误）**不阻塞登出**：仍清空本地，仅把提示降级为
   「已退出登录 · 本机令牌已清除（未能撤销 GitHub 侧授权）」——原型演示成功路径。 */
function signOut(){
  closeSheet();
  authStep='login'; authHTML();
  stacks = {
    home:[{id:'home',params:{}}], repos:[{id:'repos',params:{}}],
    explore:[{id:'explore',params:{}}], me:[{id:'me',params:{}}],
  };
  active='home';
  Object.keys(branchByRepo).forEach(k=>delete branchByRepo[k]);   // 分支记忆属账号绑定数据
  activeRepo = null;
  paintTabbar(); paintTab();
  toast('已退出登录 · 已同时撤销 GitHub 侧授权');
}

