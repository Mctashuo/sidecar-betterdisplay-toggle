# Sidecar Toggle with BetterDisplay

这组脚本用于在 macOS 上自动协调 Sidecar 随航、真实外接显示器和 BetterDisplay 虚拟显示器。

核心目标：

- 没有真实外接显示器时，打开随航前先连接 BetterDisplay 虚拟屏。
- 有真实外接显示器时，自动断开 BetterDisplay 虚拟屏，避免多余显示器占用布局。
- 如果随航正在使用真实外接显示器镜像，之后真实外接显示器断开，则自动打开虚拟屏并重新连接随航。
- 如果之前没有打开随航，真实外接显示器断开时不会主动打开虚拟屏，也不会启动随航。

## 文件说明

- `sidecar-toggle.sh`
  - 主逻辑脚本。
  - 支持 `toggle` 和 `sync` 两个命令。
- `install-sidecar-toggle-launchagent.sh`
  - 安装脚本。
  - 会复制主脚本到 `~/.local/bin/sidecar-toggle.sh`。
  - 会安装两个 LaunchAgent。
- `uninstall-sidecar-toggle-launchagent.sh`
  - 卸载脚本。
  - 会移除两个 LaunchAgent。
- `tests/sidecar-toggle-tests.zsh`
  - 本地行为测试。

## 依赖

### BetterDisplay

脚本直接调用 BetterDisplay App 内部 binary：

```bash
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
```

虚拟屏默认使用：

```text
tagID=16
```

对应命令是：

```bash
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set --tagID=16 --connected=on
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set --tagID=16 --connected=off
```

### SidecarLauncher

脚本需要：

```bash
~/.local/bin/SidecarLauncher
```

连接设备优先级保存在本机私有配置文件中：

```text
~/.config/sidecar-toggle/devices.txt
```

每行一个设备名，顺序就是连接优先级。这个文件由安装脚本生成，不需要提交到 Git。

脚本会先执行：

```bash
~/.local/bin/SidecarLauncher devices list
```

然后按私有配置里的顺序选择可连接设备。

## 安装

在当前目录执行：

```bash
./install-sidecar-toggle-launchagent.sh
```

安装脚本会先扫描当前可连接的 Sidecar 设备，并要求输入连接优先级。例如：

```text
Available Sidecar devices:
  1) Desk iPad
  2) Living Room iPad

Enter device numbers in connection priority order (for example: 2 1): 1 2
```

如果没有检测到任何可连接设备，安装会中止。先确认 iPad 在 SidecarLauncher 中可见，再重新运行安装脚本。

安装后会创建：

```text
~/.local/bin/sidecar-toggle.sh
~/.config/sidecar-toggle/devices.txt
~/Library/LaunchAgents/local.sidecar-toggle.plist
~/Library/LaunchAgents/local.sidecar-display-sync.plist
~/.sidecar-toggle-trigger
```

并加载两个 LaunchAgent：

- `local.sidecar-toggle`
  - 监听 `~/.sidecar-toggle-trigger`。
  - 用于手动切换随航。
- `local.sidecar-display-sync`
  - 每 10 秒执行一次后台同步。
  - 用于自动处理真实外接显示器和虚拟显示器之间的状态。

安装脚本不会反复重写 `~/.sidecar-toggle-trigger`，避免重装时误触发 toggle。

## 通过 iPad 触发

当前的手动触发方式是：iPad 通过 SSH 连到 Mac，然后在 Mac 上写入 `~/.sidecar-toggle-trigger`。触发文件可以包含发起请求的 iPad 名称，Mac 会优先连接这个名称对应的设备。

### Mac 端配置

在 Mac 上打开远程登录：

1. 打开 `系统设置`。
2. 进入 `通用` > `共享`。
3. 打开 `远程登录`。
4. 在 `允许访问` 中选择允许登录的本地用户，建议只放行当前登录账户。

如果你打算用 SSH key 登录，还需要把 iPad 上生成的公钥加入 Mac 上这个用户的 `authorized_keys`：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

把上面那行 `ssh-ed25519 ...` 换成你 iPad SSH 客户端里导出的公钥内容。这里追加的是公钥，不是私钥。

如果你已经把公钥存成一个文件，也可以直接追加：

```bash
cat ~/Downloads/ipad.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

如果你想从 iPad 直接连到 Mac，可以先在 Mac 上查看本机局域网地址：

```bash
ipconfig getifaddr en0
```

如果你是有线网络或 `en0` 没有地址，也可以改用 `en1` 或在共享页面里查看当前网络地址。

### iPad 端配置

在 iPad 上用 `快捷指令` 做一个动作，自动把本机名称写到 Mac 的触发文件里。

1. 打开 `快捷指令`，点右上角 `+` 新建快捷指令。
2. 添加动作 `获取设备详细信息`。
3. 把详细信息设成 `设备名称`。
4. 添加动作 `通过 SSH 运行脚本`。
5. 在 SSH 动作里填入 Mac 的 `主机`、`用户名`、`端口` 和认证方式。
6. 在脚本框里输入：

```bash
printf '%s\n' "设备名称" > ~/.sidecar-toggle-trigger
```

7. 把上一步的 `设备名称` 变量插入到双引号中间。

这个快捷指令运行后，会把这台 iPad 的名称写进 Mac 的 `~/.sidecar-toggle-trigger`。Mac 会优先连接这个名字对应的设备。

如果你希望手工核对设备名，也可以先在 Mac 上运行：

```bash
~/.local/bin/SidecarLauncher devices list
```

然后确保 iPad 快捷指令里写入的名称和列表里的设备名完全一致。

如果选择 SSH key，先把 iPad 里生成的公钥加入 Mac 的 `~/.ssh/authorized_keys`，再在 iPad 快捷指令里选择对应的私钥。

快捷指令也可以保存成主屏幕图标或 Siri 命令，这样每台 iPad 都能有自己的触发入口。

## 使用方法

### 手动切换随航

执行：

```bash
touch ~/.sidecar-toggle-trigger
```

这会按默认优先级触发：

```bash
~/.local/bin/sidecar-toggle.sh toggle
```

行为如下：

1. 如果当前随航已经连接：
   - 断开随航。
   - 清除随航状态记录。
2. 如果当前随航未连接，且检测到真实外接显示器：
   - 断开 BetterDisplay 虚拟屏 `tagID=16`。
   - 连接随航。
   - 记录“外接屏期间随航是打开的”。
3. 如果当前随航未连接，且没有真实外接显示器：
   - 连接 BetterDisplay 虚拟屏 `tagID=16`。
   - 等待 2 秒让显示器拓扑刷新。
   - 连接随航。
   - 记录为已恢复状态，避免后台 sync 重复操作。

也可以直接运行：

```bash
~/.local/bin/sidecar-toggle.sh toggle
```

### 手动执行一次后台同步

执行：

```bash
~/.local/bin/sidecar-toggle.sh sync
```

正常情况下不需要手动执行，安装后的 LaunchAgent 会每 10 秒自动执行一次。

## 后台同步逻辑

后台同步由：

```text
local.sidecar-display-sync
```

每 10 秒触发一次。

### 检测到真实外接显示器

脚本会：

1. 检测随航是否连接。
2. 如果随航已连接，写入状态：

   ```text
   ~/.sidecar-toggle-state = external-sidecar
   ```

3. 如果随航未连接，清除状态文件。
4. 断开 BetterDisplay 虚拟屏：

   ```bash
   BetterDisplay set --tagID=16 --connected=off
   ```

### 真实外接显示器断开

如果没有检测到真实外接显示器，脚本会检查状态文件。

如果状态是：

```text
external-sidecar
```

说明之前是在“真实外接显示器 + 随航已打开”的状态下工作。此时脚本会：

1. 打开 BetterDisplay 虚拟屏：

   ```bash
   BetterDisplay set --tagID=16 --connected=on
   ```

2. 等待 2 秒。
3. 如果随航仍在线，先断开随航。
4. 再重新连接随航。
5. 将状态写为：

   ```text
   recovered
   ```

这样可以避免每 10 秒重复重启随航。

如果没有 `external-sidecar` 状态，脚本不会打开虚拟屏，也不会启动随航。

## 外接显示器检测

脚本优先使用：

```bash
system_profiler SPDisplaysDataType
```

支持类似这样的输出：

```text
Displays:
  MAG 272U X24:
    Online: Yes
  虚拟 16:12:
    Online: Yes
  Sidecar Display:
    Connection Type: AirPlay
    Virtual Device: Yes
```

其中：

- `MAG 272U X24` 会被识别为真实外接显示器。
- `虚拟 16:12` 会被排除。
- `Sidecar Display` 会被排除。
- `Virtual Device: Yes` 会被排除。
- `Connection Type: AirPlay` 会被排除。
- 内建屏会被排除。

如果 `system_profiler` 没有返回显示器明细，脚本会 fallback 到：

```bash
ioreg -lw0 -r -c IOMobileFramebuffer
```

通过真实硬件显示器的 `DisplayAttributes`、`Transport` 和 `external = Yes` 判断外接屏。

## 状态文件

脚本使用：

```text
~/.sidecar-toggle-state
~/.sidecar-toggle-virtual-state
```

`~/.sidecar-toggle-state` 记录 Sidecar 恢复流程状态，可能内容：

- `external-sidecar`
  - 表示上一次检测到“真实外接显示器存在，并且随航已连接”。
  - 如果之后真实外接显示器断开，脚本会打开虚拟屏并重启随航。
- `recovered`
  - 表示已经从真实外接屏断开场景恢复过一次。
  - 防止后台 sync 每 10 秒重复重启随航。

手动断开随航时会清除状态文件。

`~/.sidecar-toggle-virtual-state` 记录 BetterDisplay 虚拟屏目标状态，可能内容：

- `on`
  - 表示脚本最近一次希望虚拟屏保持连接。
- `off`
  - 表示脚本最近一次希望虚拟屏保持断开。

## 日志

主日志：

```bash
~/Library/Logs/sidecar-toggle.log
```

LaunchAgent stderr：

```bash
~/Library/Logs/sidecar-toggle.launchd.err.log
~/Library/Logs/sidecar-display-sync.launchd.err.log
```

查看最近日志：

```bash
tail -n 80 ~/Library/Logs/sidecar-toggle.log
```

常见日志含义：

```text
External display detected during sync; disconnecting BetterDisplay virtual display
```

检测到真实外接显示器，正在断开 BetterDisplay 虚拟屏。

```text
External display and Sidecar detected during sync; remembering Sidecar state
```

当前是真实外接显示器 + 随航已连接，已记录状态。之后如果外接显示器断开，会自动恢复到虚拟屏 + 随航。

```text
External display disappeared after Sidecar was active; reconnecting virtual display and restarting Sidecar
```

之前随航处于打开状态，现在真实外接显示器断开，脚本正在打开虚拟屏并重启随航。

## 卸载

执行：

```bash
./uninstall-sidecar-toggle-launchagent.sh
```

会卸载：

```text
local.sidecar-toggle
local.sidecar-display-sync
```

并删除：

```text
~/Library/LaunchAgents/local.sidecar-toggle.plist
~/Library/LaunchAgents/local.sidecar-display-sync.plist
```

卸载脚本不会删除：

```text
~/.local/bin/sidecar-toggle.sh
~/.config/sidecar-toggle/devices.txt
~/.sidecar-toggle-trigger
~/.sidecar-toggle-state
~/Library/Logs/sidecar-toggle.log
```

如需清理这些文件，可以手动删除。

## 测试

在当前目录执行：

```bash
tests/sidecar-toggle-tests.zsh
tests/install-launchagent-tests.zsh
```

语法检查：

```bash
zsh -n sidecar-toggle.sh
zsh -n install-sidecar-toggle-launchagent.sh
zsh -n uninstall-sidecar-toggle-launchagent.sh
zsh -n tests/sidecar-toggle-tests.zsh
zsh -n tests/install-launchagent-tests.zsh
```

## 可配置项

主脚本支持用环境变量覆盖默认值。

### BetterDisplay 路径

```bash
SIDECAR_TOGGLE_BETTERDISPLAY="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
```

### BetterDisplay 虚拟屏 tagID

默认：

```bash
SIDECAR_TOGGLE_VIRTUAL_TAG_ID=16
```

### 虚拟屏连接后的等待时间

默认 2 秒：

```bash
SIDECAR_TOGGLE_VIRTUAL_DISPLAY_SETTLE_SECONDS=2
```

### 日志文件

```bash
SIDECAR_TOGGLE_LOG_FILE="$HOME/Library/Logs/sidecar-toggle.log"
```

### 状态文件

```bash
SIDECAR_TOGGLE_STATE_FILE="$HOME/.sidecar-toggle-state"
SIDECAR_TOGGLE_VIRTUAL_STATE_FILE="$HOME/.sidecar-toggle-virtual-state"
```

### 设备优先级配置文件

默认：

```bash
SIDECAR_TOGGLE_DEVICES_FILE="$HOME/.config/sidecar-toggle/devices.txt"
```

### 锁目录

```bash
SIDECAR_TOGGLE_LOCK_DIR="/tmp/sidecar-toggle.${UID}.lock"
```

## 排障

### 虚拟屏没有被断开

先看日志：

```bash
tail -n 80 ~/Library/Logs/sidecar-toggle.log
```

确认是否出现：

```text
External display detected during sync
```

如果没有，检查系统显示器输出：

```bash
system_profiler SPDisplaysDataType
```

以及 fallback 数据：

```bash
ioreg -lw0 -r -c IOMobileFramebuffer
```

### 随航没有连接

检查 SidecarLauncher 是否可执行：

```bash
ls -l ~/.local/bin/SidecarLauncher
```

检查设备是否可见：

```bash
~/.local/bin/SidecarLauncher devices list
```

设备名必须匹配 `~/.config/sidecar-toggle/devices.txt` 里的配置。需要调整优先级时，重新运行安装脚本并重新输入编号，或直接编辑这个文件。

### BetterDisplay 命令失败

检查 BetterDisplay binary：

```bash
ls -l /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
```

手动测试：

```bash
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set --tagID=16 --connected=off
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set --tagID=16 --connected=on
```

### 查看 LaunchAgent 状态

```bash
launchctl print "gui/$(id -u)/local.sidecar-toggle"
launchctl print "gui/$(id -u)/local.sidecar-display-sync"
```
