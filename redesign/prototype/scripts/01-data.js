/* ══ GitDuo 2.0 原型 · 01 · 演示数据（置顶 / 最近 / 仓库 / 文件树 / Issue / PR / 探索榜 / Commit） ══ */

/* ============================================================ data */
/* 置顶仓库：只读同步自 GitHub 个人主页置顶（GraphQL viewer.pinnedItems，上限 6 个） */
let PINNED = ['my-git/gitduo','my-git/notes','rust-lang/rust'];
let RECENT = [
  {n:'vercel/next.js',t:'昨天'},
  {n:'my-git/scripts',t:'2 天前'},
  {n:'my-git/gitduo',t:'3 天前'},
];
const REPOS = [
  {n:"my-git/gitduo",d:"GitHub 客户端 · SwiftUI",lang:"Swift",lc:"#f05138",s:"128",f:"12",priv:false},
  {n:"my-git/notes",d:"个人知识库",lang:"Markdown",lc:"#519aba",s:"3",f:"0",priv:true},
  {n:"vercel/next.js",d:"The React Framework",lang:"JavaScript",lc:"#f1e05a",s:"124k",f:"26.8k",priv:false},
  {n:"rust-lang/rust",d:"Empowering everyone to build reliable software",lang:"Rust",lc:"#dea584",s:"98k",f:"12.6k",priv:false},
  {n:"my-git/scripts",d:"日常自动化脚本合集",lang:"Python",lc:"#3572A5",s:"41",f:"5",priv:false},
];
const TREE = {
  "": [
    {n:"GitDuo",msg:"refactor: new tab structure",t:"dir"},
    {n:"Packages",msg:"feat: etag cache layer",t:"dir"},
    {n:"Tests",msg:"test: diff parser edge cases",t:"dir"},
    {n:"README.md",msg:"docs: update roadmap",t:"file"},
    {n:"project.yml",msg:"chore: bump swift version",t:"file"},
  ],
  "GitDuo": [
    {n:"App",msg:"app entry & composition root",t:"dir"},
    {n:"Features",msg:"feat: branch switcher on repo hub",t:"dir"},
    {n:"DesignSystem",msg:"style: card & state components",t:"dir"},
  ],
  "GitDuo/App": [
    {n:"AppEnvironment.swift",msg:"feat: 401 auto sign-out",t:"file"},
    {n:"GitDuoApp.swift",msg:"chore: fix environment injection",t:"file"},
    {n:"RootView.swift",msg:"refactor: root flow",t:"file"},
  ],
  "GitDuo/Features": [
    {n:"Auth",msg:"fix: login button stuck",t:"dir"},
    {n:"Repos",msg:"feat: code browsing",t:"dir"},
    {n:"Notifications",msg:"perf: ETag conditional GET",t:"dir"},
  ],
  "GitDuo/Features/Repos": [
    {n:"RepoListView.swift",msg:"fix: push nav on compact width",t:"file"},
    {n:"RepoDetailView.swift",msg:"feat: four-segment hub",t:"file"},
  ],
  "Packages": [
    {n:"GitDuoKit",msg:"local swift packages",t:"dir"},
  ],
  "Packages/GitDuoKit": [
    {n:"MarkdownRenderer.swift",msg:"feat: block-level markdown",t:"file"},
    {n:"GitHubClient.swift",msg:"feat: auth failure hook",t:"file"},
  ],
  "Tests": [
    {n:"GitDuoKitTests.swift",msg:"test: swift testing suite",t:"file"},
  ],
};
const ISSUES = [
  {n:42,t:"登录按钮在真机上不可点",s:"open",c:"bug · auth",u:"reviewer-a",d:"2 小时前 · 3 条评论"},
  {n:39,t:"仓库列表分页后滚动位置丢失",s:"open",c:"ui",u:"tester-b",d:"昨天 · 1 条评论"},
  {n:35,t:"Markdown 列表渲染缩进错误",s:"closed-i",c:"markdown",u:"reviewer-a",d:"3 天前"},
];
const PRS = [
  {n:57,t:"feat: 仓库详情四分区导航",s:"open",b:"feature/repo-hub → main",u:"dev-j",d:"2 小时前",ds:"+842 −156"},
  {n:55,t:"perf: 头像图片降采样",s:"open",b:"perf/avatar → main",u:"dev-k",d:"昨天",ds:"+96 −41"},
  {n:51,t:"fix: OAuth 回调地址校验",s:"merged",b:"fix/oauth → main",u:"dev-j",d:"3 天前",ds:"+31 −12"},
];
/* 探索数据池：created=创建日 / st=近期新增 Star / pushedM=距最近推送的分钟数（越小越新） */
const TRENDING = [
  {n:"misoge/paneltkit",d:"SwiftUI 自适应布局工具库 · Swift",lang:"Swift",lc:"#f05138",s:"2,341",created:"2026-08-05",st:812,pushedM:120,
   tp:["swiftui","layout","ios"],watch:"45",fork:"88",lic:"MIT",upd:"2 小时前",rel:"v2.1.0",reld:"3 天前",relNote:"新增 Hinge 感知布局容器，修复折叠态尺寸抖动",contrib:23},
  {n:"nicedoc/mdx-engine",d:"高性能 Markdown 渲染引擎",lang:"Rust",lc:"#dea584",s:"5,102",created:"2026-05-20",st:540,pushedM:1440,
   tp:["markdown","parser","wasm"],watch:"78",fork:"201",lic:"Apache-2.0",upd:"昨天",rel:"v0.9.2",reld:"上周",relNote:"表格解析性能提升 40%，支持 GFM 扩展语法",contrib:57},
  {n:"openui/tokens",d:"设计令牌开放标准",lang:"TypeScript",lc:"#3178c6",s:"9,876",created:"2026-01-10",st:321,pushedM:240,
   tp:["design-system","tokens","spec"],watch:"112",fork:"402",lic:"CC-BY-4.0",upd:"4 小时前",rel:"r2026-10",reld:"本月",relNote:"新增动效令牌章节（duration / easing / spring）",contrib:112},
  {n:"zed-flow/agent-kit",d:"终端 AI 编程助手工具链",lang:"Go",lc:"#00ADD8",s:"6,720",created:"2026-09-12",st:480,pushedM:60,
   tp:["ai","cli","agent"],watch:"203",fork:"151",lic:"MIT",upd:"1 小时前",rel:"v0.4.0",reld:"2 天前",relNote:"新增多模型路由与工具调用沙箱",contrib:41},
  {n:"huatu/langx",d:"中文自然语言处理工具包",lang:"Python",lc:"#3572A5",s:"3,180",created:"2026-08-25",st:265,pushedM:480,
   tp:["nlp","chinese","tokenizer"],watch:"66",fork:"94",lic:"Apache-2.0",upd:"8 小时前",rel:"v1.2.0",reld:"本周",relNote:"新增分词器增量训练与词性标注模型",contrib:29},
  {n:"kuda/ui-craft",d:"声明式 UI 组件库",lang:"TypeScript",lc:"#3178c6",s:"11,240",created:"2025-03-02",st:198,pushedM:180,
   tp:["ui","components","design"],watch:"318",fork:"612",lic:"MIT",upd:"3 小时前",rel:"v5.8.1",reld:"上周",relNote:"发布无障碍标注层与 RTL 布局支持",contrib:186},
  {n:"rust-tools/turbo-rs",d:"Rust 增量编译加速器",lang:"Rust",lc:"#dea584",s:"7,905",created:"2026-09-28",st:142,pushedM:30,
   tp:["rust","build","compiler"],watch:"97",fork:"130",lic:"MIT",upd:"30 分钟前",rel:"v0.2.3",reld:"昨天",relNote:"新增编译缓存指纹校验与并行调度",contrib:18},
  {n:"sakura-dev/nihongo",d:"日语文档排版引擎",lang:"Swift",lc:"#f05138",s:"1,460",created:"2026-07-15",st:88,pushedM:2880,
   tp:["japanese","typesetting","swift"],watch:"34",fork:"52",lic:"MIT",upd:"2 天前",rel:"v1.0.0",reld:"本月",relNote:"支持纵排与 Ruby 注音渲染",contrib:12},
];
const COMMITS = [
  {m:"feat: code tree view",u:"dev-j",s:"e4f2a91"},
  {m:"refactor: split RepoDetailStore",u:"dev-j",s:"b19c07d"},
  {m:"test: hub navigation",u:"dev-k",s:"77a2e10"},
];

