# vRemoter

vRemoter 是一个 macOS 蓝牙语音遥控器工具：把遥控器语音键映射为输入法语音触发，把遥控器麦克风与 MacBook 麦克风混合成 `vRemoteDr 2ch`，并提供按型号保存的按键映射。

已接入的遥控器：

- Google Chromecast Remote（VID `0x18D1` / PID `0x9450`）

当前版本：`1.2.3`

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
- `Design/`：冻结 UI 与 Logo 的 Figma 源稿。

## 文档

- [CHANGELOG.md](CHANGELOG.md)
- [第三方许可说明](THIRD_PARTY_NOTICES.md)
- [音频驱动说明](Driver/README.md)
