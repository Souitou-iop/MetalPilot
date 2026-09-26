# Changelog

All notable changes to **MetalPilot** will be documented in this file.

---

## [v4.3.3] - 2026-09-26

### 📦 Release 稳定性迭代 (Release Stability Iteration)
- **版本号迭代**：将当前已验证的超分/补帧自动恢复闭环、捕捉流重建、窗口回退与紧急回退能力打包为新的 `4.3.3` Release 版本。
- **界面修复纳入 Release**：包含快捷场景预设文案放大与调度中心侧边栏图标闪烁修复。
- **签名与兼容性保持**：继续使用 `MacGameToolbox Dev` 对 App 与特权 Helper 签名，保持原 Bundle ID 与用户配置路径不变。

---

## [v4.3.2] - 2026-09-26

### 🐳 修复启动时 Dock 图标闪两次 (Fix Dock Icon Double-Flash on Launch)
- **激活策略启动翻转修复**：`MenuCommandCoordinator` 新增 `hasShownMainWindow` 门控，在主窗口首次显示之前不再执行 `.accessory` 切换。此前启动瞬间 `install()` 中的 `updateDockVisibility()` 在 SwiftUI 主窗口尚未创建时执行，误判"无可见主窗口"而隐藏 Dock 图标，窗口成为 key window 后又切回 `.regular`，表现为 Dock 图标弹出→消失→再弹出共闪两次。
- **权限提示根治部署**：本次部署的 App 未经过 `Scripts/build-release.sh` 签名流程（ad-hoc/linker 签名），每次重建 cdhash 变化导致 macOS TCC 将其视为陌生程序、屏幕录制/辅助功能授权反复失效。现恢复以持久证书 `MacGameToolbox Dev` 签名 App 与特权 Helper，TCC 以证书身份（`com.iven.macgametoolbox` + 证书指纹）匹配，本地重建不再重置授权。
- **超分与补帧自动恢复闭环**：检测 ScreenCaptureKit 捕捉流错误、启动超时、运行中长时间无完整帧、窗口/显示器变化及睡眠唤醒，自动销毁并重建捕捉流，重新匹配目标窗口；连续失败后移除覆盖层并回退到原始画面，同时提供紧急回退快捷键 `⌘⌥⇧Esc`。
- **界面稳定性修复**：放大快捷场景预设文案并保持两列排版；固定导航侧边栏图标样式并禁用切换详情页时的隐式动画，避免图标闪烁。

---

## [v4.3.1] - 2026-09-25

### 🧹 旧品牌内部命名全面清理 (Internal Legacy Naming Cleanup)
- **命名层统一为 MetalPilot**：Swift Package 名、模块与源码目录（`MacGameToolboxCore` → `MetalPilotCore`、`Sources/MacGameToolbox` → `Sources/MetalPilot`）、测试 target（`MetalPilotCoreTests`）、`@main` 结构体（`MetalPilotApp`）与错误类型（`ToolboxError` → `MetalPilotError`）全部更名，纯机械替换无行为变化，`SWIFT_PACKAGE` 门控的全部模块导入同步更新。
- **hosts 托管块标记迁移**：新写入的标记改为 `# BEGIN/END METALPILOT HOYO`，并永久兼容识别旧版本写入的 `MAC GAME TOOLBOX` 标记，确保旧块仍能被精准清理与回滚；同时修复启动检测中硬编码旧标记的重复字面量，改为复用常量并双标记识别。
- **界面与零散清理**：修复中文界面遗留的「工具箱」自称；Helper hosts 临时文件、测试夹具路径、脚本内临时口令与窗口过滤注释同步更名；合并 Helper `main.swift` 中完全重复的 `--install` 参数处理块。
- **兼容身份保持不变**：App Bundle ID（`com.iven.macgametoolbox`）、持久签名证书（`MacGameToolbox Dev`）、旧 helper（`macgametoolbox.helper`）识别与迁移逻辑原样保留，TCC 权限、后台项显示与升级路径不受影响。

---

## [v4.3.0] - 2026-09-25

### 🛠️ 特权辅助服务迁移至新品牌标识 (Privileged Helper Identity Migration)
- **辅助服务标识迁移为 `metalpilot.helper`**：LaunchDaemon Label、MachService 名称、安装路径（`/Library/PrivilegedHelperTools/metalpilot.helper`）与 Helper Bundle ID 统一更新，系统设置「登录项与扩展 > 后台活动」中显示为 `metalpilot.helper`，与 MetalPilot 品牌保持一致。
- **Helper 可执行文件更名**：`MacGameToolboxPrivilegedHelper` 更名为 `MetalPilotPrivilegedHelper`，SwiftPM Target、Xcode 工程、构建与签名脚本（`codesign -i metalpilot.helper`）同步更新。
- **主 App 技术身份保持稳定**：App Bundle ID（`com.iven.macgametoolbox`）、持久签名证书（`MacGameToolbox Dev`）与后台项 `AssociatedBundleIdentifiers` 关联保持不变，TCC 权限与后台活动 App 图标显示不受影响。

### ⚖️ 迁移完全可选，支持双软件共存 (Optional Migration & Side-by-Side Coexistence)
- **启动时自动检测旧服务**：发现旧 `macgametoolbox.helper` 守护进程或残留文件而新版未安装时，弹窗提供三种选择——立即迁移（卸载并清理旧服务，后台仅保留 `metalpilot.helper`，需一次管理员授权）、保留旧服务（双软件共存模式，适合同时保留新旧两个应用的用户）、稍后（下次启动再询问）。
- **共存模式持久化**：选择保留后写入配置（`legacyHelperCoexistence`，旧配置文件自动兼容默认关闭），此后所有安装/修复路径自动附加 `--preserve-legacy`，Helper 安装器不再触碰旧服务文件与守护进程，也不再重复弹窗。
- **共存模式可随时退出**：系统页修复按钮在共存模式下会先询问「仅重新注册（保留旧服务）」或「迁移并清理旧服务」；健康检测横幅同步替换为中性说明，不再显示橙色清理警告。
- **默认升级路径不变**：未选择共存的用户首次迁移仍会自动清理历史残留。

### 📝 文档与发布资料对齐 (Documentation Alignment)
- **三语 README 对齐**：英文与日文 README 重写为与中文版一致的产品叙事结构（Logo 头图、主要能力、界面预览、为什么是 MetalPilot、功能概览、系统要求、权限边界、项目状态），移除过时的 fork 增强清单与上游对比表。
- **修复截图断链**：三份 README 的截图路径由 `docs/` 修正为 `docs/screenshots/`，概览、Metal HUD 与菜单栏三组三语截图全部可正常显示。
- **版本徽章与构建说明修正**：版本徽章统一为 v4.3.0，clone 后目录说明修正为 `cd MetalPilot`。

---

## [v4.2.0] - 2026-09-24

### 🖼️ 三语界面演示与菜单栏 Popover 修复 (Trilingual UI Showcase & Popover Layout Fix)
- **更新中/英/日三语 README 截图**：加入概览、Metal HUD 和菜单栏三组最新演示图，统一展示 MetalPilot 当前界面。
- **修复菜单栏 Popover 上下边缘材质露出**：统一 SwiftUI Hosting View 与 NSPopover 尺寸，并使用窗口内材质混合模式，避免上下出现前景模糊缺失。

### 🎨 品牌重塑为 MetalPilot (Rebranding to MetalPilot)
- **对外品牌统一更名为 MetalPilot**：App 显示名、Xcode target/scheme/工程名、构建与打包脚本、README（中/英/日）、CHANGELOG、AUDIT_REPORT 及发布产物文件名统一改为 MetalPilot。
- **接入全新 App 图标**：使用新的 MetalPilot 图标（火箭 + 蓝色轨道）替换原有工具箱图标，覆盖 macOS 所需全部尺寸（16–1024pt）。
- **保留旧技术标识以保障升级兼容**：App Bundle ID（`com.iven.macgametoolbox`）、特权 Helper Bundle ID（`macgametoolbox.helper`）、LaunchDaemon Label、MachService 名称、Helper 二进制名与内置 plist 文件名均**保持不变**。修改这些标识会导致旧版本升级后权限服务失联、用户数据目录失效或产生残留守护进程，故本次品牌重构仅改用户可见名称，技术标识待独立迁移方案再处理。
- **模块名保持稳定**：Swift Target/模块名（`MacGameToolbox`、`MacGameToolboxCore`、`MacGameToolboxPrivilegedHelper`）与源码目录未改动，避免无关重构。

---

## [v4.1.0] - 2026-08-17

### ⚡ Metal HUD 注入样式精准生效与全界面版本联动 (Metal HUD Injection Style & Dynamic Versioning)
- **彻底修复 Metal HUD 环境变量缺省导致的样式未生效缺陷**：重构环境变量生成器，消除了旧代码在默认值时省略键名的逻辑，确保 `MTL_HUD_SCALE`、`MTL_HUD_OPACITY`、`MTL_HUD_ALIGNMENT` 与 `MTL_HUD_ELEMENTS` 在启动注入与系统级会话中 100% 显式传递生效。
- **强制独立实例启动 (`open -n`)**：在单应用启动器中加入 `-n` 参数，强制系统创建干净且具备完整环境变量的全新子进程空间，杜绝复用后台无环境变量的旧进程。
- **全界面版本号动态同步**：建立统一的 `AppVersion` 动态访问器，菜单栏 Popover、侧边栏、关于面板及系统日志统一由 Bundle 自动派生，彻底消除版本滞后。

---

## [v4.0.9] - 2026-08-16

### 🗑️ 应用启动器删除与预选池管理能力增强 (App Launcher Item Deletion)
- **为游戏选择启动器增加红字删除功能**：在「选择应用启动」二级弹窗的每个游戏行中加入高亮红色文本的「删除」操作按钮，支持一键移除不需要的预选应用；并在顶部操作栏新增「删除所选 (X)」批量移除按钮。

---

## [v4.0.8] - 2026-08-16

### 🎨 按钮文本省略号彻底清理与视觉精细化 (Button Ellipsis Removal & Text Cleanup)
- **全面移除操作按钮末尾的省略号标记**：系统性排查并清除了各功能板块（系统设置、磁盘挂载、缓存清理、进程加速、Metal HUD 及概览面板）所有按钮文案末尾硬编码的省略号（`…` 与 `...`），消除截断歧义，界面视觉更加干净干练。

---

## [v4.0.7] - 2026-08-16

### 🎨 权限检测列表视觉对齐与控件调优 (Permission Health Item Layout Polish)
- **请求授权按钮放大与垂直居中对齐**：优化软件服务与系统权限检测卡片中的列表行布局，将「请求授权」操作按钮尺寸调整为标准尺寸 (`.small`)，整行采用 `HStack(alignment: .center)` 垂直居中与 `Spacer()` 严格右对齐，视觉比例更为舒适自然。

---

## [v4.0.6] - 2026-08-16

### 🎨 界面排版对齐与视觉一致性调优 (UI Alignment & Visual Polish)
- **Metal HUD 全局启用开关右对齐**：重构全局控制卡片中的布局容器，使用 `Spacer()` 将开关组件稳定推至最右侧，与系统级卡片规范保持一致。
- **通用偏好语言选择器右对齐**：调整语言切换菜单项为靠右布局，消除紧靠左侧标签的排版松散感，视觉更为对称优雅。

---

## [v4.0.5] - 2026-08-16

### 🛡️ 彻底根治权限索要与全局卡片布局精简 (Silent Permissions & Clean Layout)
- **彻底杜绝打开菜单栏时的权限弹窗（非侵入式静默设计）**：彻底移除打开菜单栏 Popover 时的被动窗口与屏幕扫描，仅在用户主动点击「启动超分补帧」、「刷新窗口列表」或「请求授权」按钮时才按需触发系统权限申请。
- **全局卡片与选择应用启动合并**：彻底移除独立的单应用卡片，将绿色的「选择应用启动…」按钮直接融入全局 Metal HUD 卡片中，界面更加紧凑纯粹。
- **重构二级选择启动器**：弹窗标题更名为「选择应用启动」，彻底移除各行末尾的三点菜单按钮，仅保留直观的「▶ 启动」按钮，支持自由勾选批量启动或单点极速启动。

---

## [v4.0.4] - 2026-08-16

### 🎨 菜单栏面板越界修复与主界面唤回双重保底 (Popover Sizing & Window Reopen Fix)
- **修复菜单栏超分补帧与面板边缘越界裁剪缺陷**：重构 `StatusBarController` 固定内容尺寸为 `380×500`，移除了 macOS 原生 `GroupBox` 的负外边距冲突，将抗锯齿与补帧模式选择器调整为紧凑下拉 Menu，彻底抚平边缘截断问题。
- **根治窗口关闭后菜单栏打不开主界面问题**：在 SwiftUI 窗口场景中桥接 `OpenWindowAction` 与 AppKit `makeKeyAndOrderFront` 双重保底机制，即使 SwiftUI 彻底销毁窗口实例也能即时重新生成并置顶唤出。
- **完善应用池预选与二次单选/多选/单点启动逻辑**：预选应用池在主卡片和弹窗 Box 中提供双重交互，支持单选、多选与单个极速点选启动，选择状态持久化记忆。

---

## [v4.0.3] - 2026-08-16

### 🎨 菜单栏交互式面板重构与单应用 HUD 体验升级 (Popover & Per-App Injection Polish)
- **现代化菜单栏交互式 Popover 面板**：基于 `NSPopover` 打造原生 SwiftUI 交互式控制面板，提供顶部水平图标分页栏 (⚡超分补帧 / 📊Metal HUD / 🚀游戏加速 / 🕹️快捷启动)、中部卡片控制区与底部对称操作栏 (⚙️打开主界面 / ⏻退出)。
- **修复菜单栏唤回主窗口机制**：采用持久化 `NSWindow` 拦截与多阶段激活序列，确保菜单栏点击打开主界面 100% 稳定置顶显示。
- **重构选择应用 Metal HUD 注入卡片**：卡片更名为「选择应用 Metal HUD 注入启动」，更新图标为 `app.badge.checkmark`，调整卡片排序紧随全局卡片之后，精简全局卡片操作区。
- **预选游戏池单选/多选/单点启动优化**：支持预选管理多款游戏，在弹窗 Box 中自由单选、多选批量启动或直接单点启动，配置与选择状态持久化保留。

---

## [v4.0.2] - 2026-08-16

### 🚀 窗口与 Dock 栏生命周期联动优化 (Dock & Window Lifecycle Optimization)
- **关闭主窗口时自动隐藏 Dock 栏图标**：当主窗口关闭/隐藏时，应用自动转入后台静默辅助模式 (`.accessory`)，**Dock 栏图标自动隐藏**，仅保留顶部菜单栏常驻图标。
- **唤回主窗口时自动恢复 Dock 栏显示**：当从菜单栏点击「显示主窗口」或通过快捷键唤出主界面时，应用自动恢复为常规应用模式 (`.regular`)，**Dock 栏图标即时恢复显示**。

---

## [v4.0.1] - 2026-08-16

### 🐛 修复与稳定性增强 (Bug Fixes & Stability)
- **修复启动时主菜单初始化时序崩溃问题**：修复 `MenuCommandCoordinator` 在 App 初始化早期因主菜单尚未就绪访问导致的隐式解包空指针崩溃，加入安全防御式边界保护与主线程异步调度。
- **优化单应用 HUD 注入与游戏选择启动器**：支持提前添加游戏池，并提供二级弹窗 Box 进行多选/单选一键批量注入启动。
- **系统菜单栏常驻控制器接入**：完整支持三大功能区快捷控制与单应用 HUD 启动。

---

## [v4.0.0] - 2026-08-16

### 🚀 重磅大版本特性：融合 MetalGoose 与 MetalDuck 优势功能 (Scaling & Frame Gen Engine)
- **画质超分与零延迟动态补帧引擎 (Resolution Scaling & Frame Generation Engine)**：
  - **双引擎动态插帧/补帧**：融合 VideoToolbox 媒体引擎 (Media Engine) 硬件运动估计与 Metal 着色器外推，实现 **0 ms 额外输入延迟的前向运动外推 (2x / 3x / 4x 补帧)**，并支持 MetalFX 光流插值。
  - **MetalFX 空间超分辨率**：支持 33%、50%、67%、75% 及原生缩放，大幅降低 3A 大作与兼容层转译游戏的 GPU 渲染负载。
  - **完整后处理画质管线**：内置 **CAS 对比度自适应锐化 (Contrast-Adaptive Sharpening)** 与 **FXAA / SMAA / TAA (时域重投影抗锯齿)** 四重抗锯齿方案，彻底抚平狗牙与高频闪烁。
  - **自适应 6-Sigma 场景剪辑保护 (Scene-Cut Detection)**：基于 64x64 亮度网格与动态 EMA 阈值检测镜头切换，在转场瞬切时自动回退为直通渲染，杜绝画面形变与撕裂。
  - **非侵入式 Metal 覆盖层与高刷合成光标**：支持针对任意游戏或模拟器窗口启动覆盖，并集成 `CGEventTap` 全局鼠标捕获与硬件级合成光标绘制。
  - **全局一键快捷键**：支持全局热键 `⌘⇧T`（一键开启/暂停补帧）与 `⌘⇧C`（鼠标光标约束锁定）。
  - **游戏内浮动性能遥测 HUD**：实时追踪显示 Capture FPS、Generated FPS、Output FPS 以及各类渲染参数。
  - **快捷场景预设**：内置 3A 游戏均衡、极限帧率、原生画质增强与模拟器复古预设。
- **页面排版与交互体验全面升级**：
  - 将「切换到 SteamDeck 主机名模式」迁移至「游戏加速与启动」页面。
  - 「HoYoGames 启动帮助」改造为标准卡片并入概览页面 3×2 对称网格。
  - 科普卡片图标升级为 `bookmark.fill` 并置于设置底部。
  - 系统权限与屏幕录制授权修复为一键主动触发 macOS 授权弹窗并登记系统列表。
  - 全库代码精简与死代码彻底清理，采用 Metal JIT 运行时极速编译。

---

## [v3.1.0] - 2026-08-16

### 🚀 新特性与亮点 (Highlights)
- **侧边栏架构重构 (Native Sidebar UI)**：全面采用 `NavigationSplitView` 与原生 `GroupBox`、`LabeledContent` 控件，告别多层嵌套弹窗，符合 Apple HIG 标准。
- **全套自定义 Metal HUD 调优 (Granular Metal HUD Tuning)**：支持 10%~100% 缩放比例、0~100% 不透明度、屏幕四角方位、23 项精细化监控指标自由勾选（附带数值单位示例）与着色器/编码器时间线追踪。
- **单应用专属 HUD 方案 (Per-App Metal HUD Profiles)**：支持右键最近游戏卡片绑定专属 HUD 配置，启动时自动独立注入。
- **一键性能诊断快照导出 (Performance Diagnostic Snapshot Exporter)**：自动搜集系统版本、Apple Silicon 芯片规格、HUD 参数与 Wine 进程，一键导出结构化 Markdown 报告。
- **冲突进程排查与安全重启 (Interfering Process Manager)**：智能识别先于 HUD 启动的 Steam、CrossOver、Whisky、Wine 容器进程，支持用户自主勾选并安全重启服务。
- **Windows 游戏存档探测与备份 (Save Game Finder & Zip Backup)**：智能扫描 CrossOver、Whisky、Heroic、Wine 容器中的 `AppData/Local`、`Saved Games`、`My Games` 存档目录，支持一键在 Finder 中定位与打包为标准 `.zip` 归档。
- **原生 Caffeinate 游戏专注模式 (Gaming Focus Anti-Sleep Mode)**：内置原生 caffeinate 守护，游戏与着色器编译期间全程防休眠、防息屏与防降频，提供 Game Mode 蓝牙手柄低延迟优化。
- **软件服务与权限状态检测器 (Service & Permission Health Inspector)**：实时检测特权辅助服务通信、系统后台活动权限、Metal HUD 环境与磁盘读写权限，支持一键自动修复与历史残留服务清理。
- **多语言本地化支持 (Multi-Language Localization - ZH / EN / JA)**：完整支持简体中文、English 与日本語，支持跟随系统语言或在通用设置中自由切换，提供专属日文文档 `README_JA.md`。
- **HoYoGames 启动辅助卡片排版修复 (Layout Bug Fix)**：修复分段选择器压缩导致“等待：”竖向折字排版的视觉缺陷。
- **辅助服务精简与 App 图标关联 (Helper Streamlining)**：辅助服务标识符精简为 `macgametoolbox.helper`，在 macOS 系统设置「登录项与扩展」中正确显示主 App 原生图标。
- **纯 ARM64 无损 Zip 发布 (Apple Silicon ARM64 Exclusive & Zip Packaging)**：专为 Apple Silicon M 系列芯片编译优化，发布产物统一采用 `.zip` 格式分发。

---

## [v3.0.7] - 2026-08-12
- HoYoGames 启动帮助部分功能修复。

## [v3.0.6] - 2026-08-10
- 移除默认挂载路径数量限制，支持添加任意数量的默认路径。
- 默认路径保存、重新加载和旧配置导入不再截断为三项。

## [v3.0.5] - 2026-08-08
- 更新应用图标，采用铺满画布的蓝紫色背景。
- 移除磁盘挂载数量限制，支持选择、批量挂载和自动恢复任意数量的磁盘。
- 修复自动恢复将扫描次数误当成秒数的问题，改为按真实经过时间触发。
