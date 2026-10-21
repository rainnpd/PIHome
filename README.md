# android-home：树莓派 5 安卓风格触摸桌面

在 Raspberry Pi OS（labwc / Wayland）上实现一个类似 Android 的主屏：按分类分页的应用图标、全屏左右滑动翻页、底部常显 dock、触摸设置面板，以及自动熄屏/唤醒。

主屏本身是 GTK3 + gtk-layer-shell 程序，运行在 layer-shell 的 background 层，始终位于普通窗口之下；配合 labwc 的三指上滑（ToggleShowDesktop）实现「回到主屏」。

## 硬件与系统

- Raspberry Pi 5 + Raspberry Pi OS trixie（labwc 会话 `rpd-labwc`，SDDM）
- 触摸屏：HDMI 输出 `HDMI-A-1`（本项目默认 2048×1536，scale 1.5），触摸走 USB
- 外置 USB HUB：触摸控制器挂在其下游端口，可用 `uhubctl` 单独断电
- 屏幕支持 DDC/CI：可下发 DPM Off 让其真正待机（不止断信号）

## 目录结构

```
src/android-home      主屏程序（GTK3 / layer-shell）
src/kb-inset          虚拟键盘弹出时调整窗口最大化的守护进程
scripts/ah-idle       读取配置后启动 swayidle
scripts/ah-screen-off 关屏：DDC 待机 + 关 HDMI + 断 HUB 供电
scripts/ah-screen-on  开屏：恢复 HUB 供电 + 开 HDMI + DDC 唤醒 + 重建主屏
config/labwc/*        labwc autostart / environment / rc.xml
config/sddm/autologin.conf  SDDM 自动登录配置
install.sh            一键部署脚本
```

## 安装

```sh
git clone git@github.com:<你的账号>/android-home.git
cd android-home
sudo ./install.sh
sudo reboot
```

`install.sh` 会安装程序到 `/usr/local/bin`、写入 labwc 配置与 SDDM 自动登录、配置熄屏脚本的 sudo 免密规则，并安装依赖。

## 使用

- 左右滑动切换分类页，底部圆点显示页数；轻点图标启动应用，同一应用 2 秒内重复点击会被忽略
- 图标上长按 0.8 秒、或用鼠标右键点图标，弹出「更多」菜单：打开 / 应用信息
- 在空白处（图标网格之外的顶部区域等）点鼠标右键，弹出「设置 / 更换壁纸」菜单
- 底部 dock 常显常用应用，最右侧齿轮打开设置面板
- 设置面板包含：背景图片（系统壁纸缩略图）、熄屏时间（1/2/5/10 分钟、永不）、桌面图标字体大小（11/13/15/17px）
- 配置文件（改完 2 秒内热生效）：

| 文件 | 内容 |
| --- | --- |
| `~/.config/android-home/wallpaper` | 壁纸图片路径（一行） |
| `~/.config/android-home/font-size` | 图标字体像素值 |
| `~/.config/android-home/idle-timeout` | 无操作熄屏秒数，0 = 永不 |
| `~/.config/android-home/recent.json` | 常用页排序 |

## 熄屏与唤醒

`swayidle` 到点后调用 `ah-screen-off`：

1. `ddcutil setvcp d6 04` 让面板进入 DPM Off（背光熄灭）
2. `wlopm --off HDMI-A-1` 停止输出
3. `uhubctl -l <HUB> -a off -f` 断触摸控制器供电

唤醒时反序恢复。注意两个已知行为：

- 面板经 DDC 待机后 GTK layer-shell 表面会失效，所以唤醒脚本会在视频恢复后重启主屏进程，屏幕上会有约 1.5 秒黑底
- 触摸控制器断电期间无法用触摸唤醒，需要键盘或鼠标；若希望触摸唤醒，可去掉 `uhubctl` 那一步

硬件相关的默认值（输出名、DDC 总线、HUB 位置）可在脚本里用 `AH_OUTPUT`、`AH_DDC_BUS`、`AH_HUB` 环境变量覆盖。

## 风扇温度（可选）

默认 50/60/67.5/75°C 起转，可整体下调 10°C。在 `/boot/firmware/config.txt` 的 `[all]` 段加入：

```
dtparam=fan_temp0=40000
dtparam=fan_temp0_hyst=5000
dtparam=fan_temp1=50000
dtparam=fan_temp2=57500
dtparam=fan_temp3=65000
```

改完需重启；运行中无法热改。

## 说明

- 程序里 `/usr/share/rpd-wallpaper` 是 Raspberry Pi OS 自带壁纸目录，非该系统需自行修改
- `config/labwc/rc.xml` 与 `autostart` 是按本项目环境裁剪过的版本，合并前请先备份原文件
