# 图标显示流程与新应用分页规则

本文说明 `android-home` 主屏从启动到把应用图标画到桌面上的完整链路，以及新安装的应用是如何被判定到某个分类页的。

## 目录

- [一、一个图标显示到桌面的完整流程](#一一个图标显示到桌面的完整流程)
- [二、新装应用如何确定分页](#二新装应用如何确定分页)
- [三、常见异常对照](#三常见异常对照)
- [四、相关代码位置](#四相关代码位置)

## 一、一个图标显示到桌面的完整流程

```
lwrespawn 启动 /usr/local/bin/android-home
        ↓
load_apps()            枚举 .desktop，过滤 + 排序
        ↓
category_of()          按 Categories= 判定分类
        ↓
group_apps()           按分类分组
        ↓
_reflow()              算列数/行数/每页容量 → _make_pages() 切页
        ↓
_build_pages()         每页 Gtk.Grid：取图标 → 缩放 → 放标签
        ↓
_build_dots() / _build_dock()   底部圆点 + 常显 dock
        ↓
点击 → _tap_at() → _on_app_clicked() → 启动并写入 recent.json
```

1. **进程启动**
   `lwrespawn` 拉起主屏进程（autostart 中会先等顶部面板出现），窗口建在 layer-shell 的 `BOTTOM` 层，全屏且位于普通窗口之下。

2. **枚举应用**
   `load_apps()` 遍历 `Gio.AppInfo.get_all()`，只保留 `DesktopAppInfo`；
   用 `should_show()` 排除 `NoDisplay=true` / `Hidden=true`，以及没有显示名的条目；
   最后按显示名排序。

3. **判定分类**
   `category_of()` 读取 `.desktop` 的 `Categories=`，与规则表求交集，
   **按规则表顺序第一个命中的生效**（网络类已并入多媒体），全部不命中则落到「系统」。

4. **分组与分页**
   `group_apps()` 先按分类分桶；`_reflow()` 用窗口尺寸计算：

   | 参数 | 计算方式 | 当前值（1365×972） |
   | --- | --- | --- |
   | 列数 `cols` | `clamp(宽 / 185, 3, 6)` | 6 |
   | 行数 `rows` | `clamp((高 − 150) / 158, 2, 5)` | 5 |
   | 每页容量 `per` | `cols × rows` | 30 |

   `_make_pages()` 先插入「常用」页（来自 `recent.json`），再把每个分类按 `per` 切片；超出容量自动续页，页标题仍为同一个分类名。

5. **构建图标**
   `_build_pages()` 每页一个 `Gtk.Grid`，按 `idx % cols` / `idx // cols` 计算行列；
   图标尺寸取 `min(格宽 × 0.52, 格高 × 0.56, 116)`；
   图标由 `IconCache.for_app()` 按 `FORCE_SIZE` 从当前图标主题查找，找不到回退到 `application-x-executable`；
   标签统一挂 `.ah-label` 类，字号来自 `~/.config/android-home/font-size`。

6. **页面摆放与装饰**
   所有页放进同一个 `Gtk.Fixed`，按 `(页号 − 当前页) × 页宽` 定位；
   拖动时只移动当前页与相邻两页（避免整屏重排造成卡顿）。
   底部圆点由 `_build_dots()` 生成；dock 固定为 `DOCK_IDS` 加 home / 键盘 / 设置齿轮，由 `_build_dock()` 构建，不来源于应用列表。

7. **点击启动**
   `_tap_at()` 命中格子后调用 `_on_app_clicked()`，通过 `Gio.AppInfo.launch()` 启动；
   同时 `_remember()` 把该应用挪到 `recent.json` 最前（最多保留一页的量）；
   同一应用 2 秒内重复点击会被防抖忽略。

8. **热更新范围**
   壁纸、字号、熄屏时长每 2 秒轮询配置文件，改动即时生效；
   **应用列表只在进程启动时读取一次**，因此新装应用后必须重启主屏进程。

## 二、新装应用如何确定分页

分页完全由 `.desktop` 文件内容决定，不需要手动配置。

### 1. 文件位置

- 系统级：`/usr/share/applications/xxx.desktop`
- 用户级：`~/.local/share/applications/xxx.desktop`

安装后建议执行一次 `sudo update-desktop-database`，确保菜单缓存可见。

### 2. 关键字段

```ini
[Desktop Entry]
Type=Application
Name=MyApp
Categories=AudioVideo;Player;      # 决定分页
Icon=myapp                          # 决定桌面图标
Exec=/usr/bin/myapp %U
NoDisplay=false                     # 为 true 则桌面不显示
```

### 3. 分页规则（顺序即优先级）

| 分类页 | 命中的 Categories 标记 |
| --- | --- |
| 多媒体 | `Network` `WebBrowser` `Email` `RemoteAccess` `InstantMessaging` `AudioVideo` `Audio` `Video` `Player` `Graphics` `Photography` 等 |
| 办公 | `Office` `WordProcessor` `Spreadsheet` `Presentation` `Database` `Document` 等 |
| 开发 | `Development` `IDE` `Electronics` `Science` |
| 游戏 | `Game` |
| 工具 | `Utility` `TextEditor` `Archiving` `FileManager` `Calculator` |
| 系统 | `System` `Settings` `PackageManager` `TerminalEmulator` `Security` `Core` 等，以及所有未命中的应用（兜底） |

### 4. 页内位置

同一分类内按 `Name` 排序，每页最多 `cols × rows`（目前 30）个；超过就自动生成下一页，页标题重复。

### 5. 让新应用立刻出现

```sh
pkill -f '^python3 /usr/local/bin/android-home'   # lwrespawn 会自动拉起
```

### 6. 核对归类是否正确

在树莓派上执行（只读，不影响桌面）：

```sh
python3 - <<'PY'
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ah", "/usr/local/bin/android-home").load_module()
for name, apps in m.group_apps(m.load_apps()):
    print(name, len(apps), ":", ", ".join(a.get_display_name() for a in apps))
PY
```

如果某个应用分错页，改它的 `.desktop` 里 `Categories=` 即可。例如把 `Categories=Utility;` 改成 `Categories=AudioVideo;Player;`，就会从工具页移到多媒体页。

## 三、常见异常对照

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 装完不出现 | 应用列表只在启动时读取 | 重启主屏进程 |
| 图标空白 / 默认方块 | 图标主题缺 `Icon=` 指定的图标 | 改为主题中已有的图标名 |
| 完全看不到 | `NoDisplay=true`、`Hidden=true` 或无 `Name` | 修改 desktop 文件 |
| 分错页 | `Categories=` 命中了更靠前的规则 | 调整 `Categories=` 顺序/内容 |

## 四、相关代码位置

| 功能 | 代码位置 |
| --- | --- |
| 分类规则表 | `src/android-home` 中的 `CATEGORY_RULES` / `CATEGORY_ORDER` |
| 应用枚举 | `load_apps()` |
| 分类判定 | `category_of()` |
| 分类分组 | `group_apps()` |
| 分页计算 | `_reflow()` / `_make_pages()` |
| 图标与标签构建 | `_build_pages()` / `IconCache.for_app()` |
| 页面摆放 | `_position_pages()` / `_slide_pages()` |
| 圆点与 dock | `_build_dots()` / `_build_dock()` |
| 启动与「常用」维护 | `_tap_at()` / `_on_app_clicked()` / `_remember()` |
