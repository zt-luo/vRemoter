# vRemoter

vRemoter 是一个 macOS 蓝牙语音遥控器工具：把遥控器语音键映射为微信输入法语音触发，把遥控器麦克风与 MacBook 麦克风混合成 `vRemoteDr 2ch`，并提供按型号保存的按键映射。

支持的遥控器：

- Google Chromecast Remote（VID `0x18D1` / PID `0x9450`）

当前版本：`1.2.3`

## 语音输入

- 「按键映射」页里的「语音输入与触发键」可以选择语音输入软件。当前支持微信输入法；菜单里的「更多语音输入软件（即将支持）」暂为禁用占位，后续按 app 扩展。
- 按住说话和点按切换两套快捷键**并列保存**，不做模式切换：
  - **按住说话（PTT）**：默认右 Option，长按遥控器语音键使用。
  - **点按切换（Toggle）**：默认左 Option，短按遥控器语音键使用。
- 两套快捷键都支持修饰键、单键和组合键，并且**不能相同**；每个输入法分别保存自己的快捷键。
- 菜单栏的「状态」下方有「启用遥控器连接」开关。取消勾选会断开 vRemoter 的 BLE/HID 连接以减少遥控器耗电；重新勾选即可恢复，设置会保存到下次启动。
- 遥控器只发出一个语音键：**短按优先使用点按切换，长按优先使用按住说话**；如果微信输入法没有响应所选快捷键，会自动回退到另一种模式。
- 短按遥控器语音键后会保持录音，**短按遥控器任意其他按键停止录音**，停止键不会触发它原本的映射。
  - 任意键停止依赖该遥控器的「按键映射」已开启（按键映射开启时 HID 被独占，按键才能被吞掉）。
- 微信输入法 → 语音输入 → 麦克风必须选择 `vRemoteDr 2ch`。

## 构建

```bash
./Scripts/run-self-tests.sh
./Scripts/package-app.sh
./Scripts/build-pkg.sh
./Scripts/build-dmg.sh
```

- `PKG`：首次安装或音频驱动发生变化时使用，包含 APP 与驱动。
- `DMG`：仅更新 APP，适合已安装过驱动且本次驱动未变化的用户。

当前发布包尚未完成 Developer ID 签名与 notarization；正式分发前需要补齐。

## 更新

APP 从本仓库的 GitHub Releases 读取版本清单：

`https://api.github.com/repos/zt-luo/vRemoter/releases`

- 普通 APP 更新优先下载 DMG。
- 驱动更新时使用 PKG（Release 中标记 `driver_update_required`）。

## 目录

- `Sources/vRemote/`：APP 主程序、BLE/ATVV、双麦混音与 UI。
- `Driver/`：`vRemoteDriver.driver` 的构建脚本与说明。
- `Packaging/`：APP 元数据、本地化与 PKG 安装脚本。
- `Resources/`：权限向导与遥控器图片。
- `SelfTests/`：硬件协议与更新配置回归数据。
- `Design/`：Logo 与 Figma 源稿。

## 文档

- [CHANGELOG.md](CHANGELOG.md)
- [第三方许可说明](THIRD_PARTY_NOTICES.md)
- [音频驱动说明](Driver/README.md)
