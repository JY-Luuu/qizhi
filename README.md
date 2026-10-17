# 栖纸 Qizhi

**JY-Luuu 的 macOS 个人衍生版。基于 [Yuxuan Fu 的 Hang Later](https://github.com/yuxuanfuture/hang-later)，保留原作的界面、纸片交互和功能。**

原作基线：v0.10.0 / [`dc1b93a`](https://github.com/yuxuanfuture/hang-later/commit/dc1b93abc9a6ab6ff845cfa33df309e43694a9cd)。个人版版本：0.1.0。

![栖纸 Qizhi main window](docs/images/qizhi-main-light-zh.png)

<details>
<summary>深色模式 / Dark mode</summary>

![栖纸 Qizhi dark mode](docs/images/qizhi-main-dark-en.png)

</details>

把网页、图片、PDF、App 窗口、想法和提醒挂在桌面晾衣绳上，点击返回来源，完成后收进归档与可旋转的 3D 完成钉。

## 这个版本做了什么

- 保留原作的暖纸纹理、字体、绳子、夹子、卡片动画、深浅模式和中英文界面。
- 使用自己的应用标识、存储目录、Chrome 扩展 ID 和 Native Messaging 主机，可与原版分开保存内容。
- 应用程序名和下载附件为 `Qizhi`，系统显示名称为 **栖纸 Qizhi**。
- 增加个人版身份一致性及浏览器消息端到端检查。
- 增加受限构建环境的 SwiftPM 选项，以及 iconutil 不可用时的原图标 ICNS 生成回退。
- 更新 GitHub Actions 到 macOS 15，提供自动检查和应用构建附件。

原始实现和视觉设计来自上游；个人版差异与来源见 [UPSTREAM.md](docs/UPSTREAM.md)。

## 安装与构建

需要 macOS 14 或以上，以及 Swift 6 的 Xcode / Command Line Tools。

```sh
git clone https://github.com/JY-Luuu/qizhi.git
cd qizhi
bash scripts/build-app.sh release
open build/Qizhi.app
```

构建安装包：

```sh
bash scripts/make-dmg.sh
```

结果位于 `build/releases/Qizhi.dmg` 和 `Qizhi.zip`。GitHub Actions 的成功构建会提供应用附件；正式发布版见 [Releases](https://github.com/JY-Luuu/qizhi/releases)。

当前为本地 ad hoc 签名构建，尚未通过 Apple 公证。首次打开时可能需要通过 macOS 的“隐私与安全性”允许启动。屏幕截图、自动化和通知按实际使用申请系统权限。

在禁止 SwiftPM 嵌套沙箱的执行环境中，可以仅为该次构建设置：

```sh
HANG_LATER_DISABLE_SWIFTPM_SANDBOX=1 bash scripts/build-app.sh debug
```

普通开发环境无需设置这个选项。该选项不会更改 macOS 的系统安全设置。

## 连接 Chrome

1. 打开个人版，选择“连接 Chrome”，安装它自己的本地主机。
2. 打开 `chrome://extensions`，开启开发者模式，加载个人版内的 `ChromeExtension` 文件夹。可在连接引导中显示该文件夹。
3. 固定 **栖纸 Qizhi** 扩展，点击保存当前网页，或右键保存链接。

个人版和原版扩展身份不同；请使用与这个应用配套的扩展。扩展使用 Native Messaging，无需本地 HTTP 服务。关闭 App 后，消息可留在 Inbox，下一次打开再导入。

## 数据与隐私

个人版数据保存到：

```text
~/Library/Application Support/Qizhi/
```

不会自动迁移、清空或覆盖原版的 `HangLater/` 数据。任务、截图和预览保存在本机，没有账号、云同步、统计或遥测。

添加链接时系统 LinkPresentation 可能请求该网页以取得预览；Chrome 扩展只在主动操作时捕捉内容。原生窗口恢复逻辑在用户触发 Chrome 窗口捕捉或恢复时，可能按精确标题查询本地 Chrome 历史副本，或通过 AppleScript 查找标签页。

## 操作

| 动作 | 结果 |
| --- | --- |
| `⌃⌥L` | 展开或收起桌面晾衣绳 |
| `⌘N` | 选择要添加的内容 |
| 点击纸片 | 打开来源；普通任务进入编辑 |
| 拖动纸片 | 自由放置、重叠，并保存位置 |
| 完成 | 进入归档，符合当前工作日条件时出现在完成钉 |
| 关闭主窗口 | 保留菜单栏运行；从菜单栏退出才结束 |

完成钉按任务的**发布时间**筛选当前工作日。普通 App 窗口可能只能唤起 App，不能恢复其内部光标或滚动位置。同时运行原版时，固定全局快捷键可能发生占用；可以使用菜单栏入口。

## 开发与验证

```sh
bash scripts/swift.sh run HangLaterChecks
python3 -m unittest discover -s NativeHost -p 'test_*.py' -v
python3 scripts/verify-personal-identity.py
node --check ChromeExtension/popup.js
node --check ChromeExtension/background.js
```

更多检查和安全样例截图入口见 [VERIFICATION.md](docs/VERIFICATION.md)，首版实际验证记录见 [BUILD_VALIDATION.md](docs/BUILD_VALIDATION.md)。

## 许可与致谢

MIT。原始项目 Copyright © 2026 Yuxuan Fu；个人版修改 Copyright © 2026 JY-Luuu。保留 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。部分浮层、绳子和快捷键实现源自 Alejandro Buján 的 Tendedero。

---

## English

栖纸 Qizhi is JY-Luuu's personal derivative of [Hang Later by Yuxuan Fu](https://github.com/yuxuanfuture/hang-later), based on upstream v0.10.0. It preserves the original native macOS interface and workflow while using independent app, storage and Chrome messaging identities. Original authorship and MIT notices are retained. See [UPSTREAM.md](docs/UPSTREAM.md) for provenance and changes.
