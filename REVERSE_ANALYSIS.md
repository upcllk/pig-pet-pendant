# 逆向记录 | zhuzhu-p_main.exe

## 输入文件

- 原文件：用户上传 `zhuzhu-p_main.exe`
- SHA-256：`0fbdb94563a4cc7edc89a9b28045d02dd2b02a71fa49c41ffc7726c902c8b110`
- 体积：843,776 bytes（约 824 KiB）
- 格式：PE32 / Intel i386 / .NET assembly（静态检查，未运行）

## 静态提取

原程序内有资源清单 `scpm-package version="3"`，资源包括 `assets/000__1.png`、三个 UI PNG、内嵌 Windows 指针包，以及 `preview.xml`。`assets/000__1.png` 是原版粉色猪，尺寸 227×199，32-bit RGBA；在本工程内以 `PigPendant/Resources/pig.png` 存放。

已验证的 `preview.xml` 设置：

| XML 字段 | 数值 |
|---|---|
| WindowTitle | 猪猪挂件 |
| ProjectType | Pendant |
| ImageSize | 48 |
| RopeLength | 140 |
| RopeSegments | 4 |
| RopeColorHex | 464646 |
| RopeAnchorOffsetX | 4 |
| RopeAnchorOffsetY | 6 |
| CursorAnchorRatioX | 0.59375 |
| CursorAnchorRatioY | 0.8125 |
| PendantAnchorRatioX | 0.5 |
| PendantAnchorRatioY | 0.5 |
| Gravity | 11000 |
| SpringK | 760 |
| SpringDamp | 28 |
| MassBall | 19.2 |
| AnimationLoopEnabled | false |

静态字符串还能识别出 `SimpleCursorPendantLoader`、`UpdatePhysicsEngine1`、`UpdatePhysicsEngine2`、`UpdatePhysicsEngine3`、`IntegratePhysicsEngine2Points`、`IntegratePhysicsEngine3Points`、`ApplyVerletLengthConstraint`、`SolvePhysicsEngine3Constraints`、`MouseHookCallback` 等托管符号。这些证明程序含多个物理求解方法，但**不能仅凭方法名还原各方法的计算细节，也无法仅靠配置判断实际使用哪个引擎**。

## Mac 移植

Mac 版采用 AppKit、透明 NSPanel、NSEvent.mouseLocation 和 Verlet/XPBD 弹性绳。初版采用 4 段；针对绳子生硬及重物拖拽感的用户反馈，当前采用 12 段、单向弹性拉伸约束及平滑曲线，允许松弛与最多 12% 额外伸长，可调末端质量。其重力、阻尼、质量和顺应度等为视觉适配值，**不是原项目的源码或完整反编译结果**。无需运行未知来源 Windows 文件；不会修改系统指针、不会发送网络请求。

后续在保留原向下绳子挂件的基础上，增加可切换的气球模式：独立使用用户参考图中提取的圆形猪气球，向上浮力驱动、单进程多气球、共用鼠标锚点，采用独立绳索、错落尺寸及侧向气流。模式切换、气球素材、数量、浮力方向和底部绳结均是 Mac 版的新需求，不属于 Windows 原版的逆向证据；原始捆绑小猪 PNG 保持不变且仅用于绳子模式。

原始工程创建时仅做过 `swiftc -frontend -parse` 语法检查，当时的容器不是 macOS。2026-10-24 已在 Apple M5 / macOS 26.6 上完成真实 AppKit 编译、物理自检、GUI 冒烟检查及应用启动检查，详情见 `README.md`。这不改变上述逆向证据的可信度，也不代表已还原原版物理引擎。
