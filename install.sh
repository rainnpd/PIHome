#!/bin/sh
# 一键部署：把程序装到 /usr/local/bin，并写入 labwc / SDDM / sudoers 配置。
# 用法：sudo ./install.sh
set -e
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo ./install.sh 运行"; exit 1; }

TARGET_USER="${TARGET_USER:-${SUDO_USER:-rain}}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
BIN=/usr/local/bin
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 安装程序到 $BIN"
install -m 755 "$SRC_DIR/src/android-home" "$BIN/android-home"
install -m 755 "$SRC_DIR/src/kb-inset" "$BIN/kb-inset"
install -m 755 "$SRC_DIR/scripts/ah-idle" "$BIN/ah-idle"
install -m 755 "$SRC_DIR/scripts/ah-screen-off" "$BIN/ah-screen-off"
install -m 755 "$SRC_DIR/scripts/ah-screen-on" "$BIN/ah-screen-on"

echo "==> 写入 labwc 配置(已存在则保留)"
mkdir -p "$HOME_DIR/.config/labwc"
for f in autostart environment rc.xml; do
    cp -n "$SRC_DIR/config/labwc/$f" "$HOME_DIR/.config/labwc/$f" 2>/dev/null || true
    chown "$TARGET_USER:" "$HOME_DIR/.config/labwc/$f" 2>/dev/null || true
done

echo "==> SDDM 自动登录(默认进 rpd-labwc 会话)"
install -D -m 644 "$SRC_DIR/config/sddm/autologin.conf" /etc/sddm.conf.d/autologin.conf
sed -i "s/^User=.*/User=$TARGET_USER/" /etc/sddm.conf.d/autologin.conf

echo "==> sudo 免密(仅允许熄屏/唤醒脚本)"
cat > /etc/sudoers.d/android-home-power <<EOF
$TARGET_USER ALL=(root) NOPASSWD: $BIN/ah-screen-off, $BIN/ah-screen-on
EOF
chmod 440 /etc/sudoers.d/android-home-power

echo "==> 创建用户配置目录 ~/.config/android-home"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$HOME_DIR/.config/android-home" || true

echo "==> 安装依赖(已安装会自动跳过)"
apt-get install -y python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 libgtk-layer-shell0 \
    uhubctl ddcutil swayidle wlopm fcitx5 fcitx5-chinese-addons squeekboard >/dev/null

cat <<'TIP'
部署完成。还需手工处理：
1) 风扇温度等参数写在 /boot/firmware/config.txt（示例见 README），改完需重启；
2) ah-screen-*.sh 里的 HDMI 输出名、DDC 总线号、HUB 位置按你的硬件用环境变量覆盖；
3) 注销并重新登录（或重启）后生效。
TIP
