# PulseOS × EchoLoop · 二合一自用工程（健康分析 + 手表 HRV 表盘 + 英语分段复读）

本工程将 **PulseOS（高集成健康看板 + Apple Watch HRV 5 态表盘皮肤）** 与你刚完成的 **EchoLoop（回声复读 + 45 秒切片离线语音识别字幕）** 无缝整合为同一个 iOS App，专为免费 7 天签名自用设计：**只占 1 个免费 App 槽位、共 3 个 App ID、每周按一次 `Cmd + R` 同步续签全部功能**。

## 底部三栏结构

1. **今日状态**：HRV 实时压力与 30 天基线中枢、显著位置静息 + 活动热量统计、昨晚睡眠与 4 项夜间体征、心肺代谢与日间活动（右上角随时打开「手表表盘皮肤」抽屉）。
2. **趋势复盘**：30 天 `lnSDNN` 对数基线与近期 HRV 波动曲线。
3. **英语复读（原版 EchoLoop）**：顶部切换「播放 / 文件 / 学习统计」，完整保留交互波形、AB 分段复读、离线语音识别生成 `.srt` 字幕、点词查词、跟读录音与后台锁屏播放（切回看健康数据时音频不中断）。

## 快速运行（约 1 分钟）

```bash
chmod +x setup.sh
./setup.sh com.yourname.pulseos
```

1. Xcode 自动打开 `PulseOS.xcodeproj` 后，依次在 `PulseOS`、`PulseOSWatch`、`PulseOSWatchWidget` 三个 Target 的 **Signing & Capabilities** 选中你的免费个人 Apple ID。
2. 连接 iPhone 按 `Cmd + R` 安装（首次运行后可在 `Window → Devices and Simulators` 勾选 **Connect via network** 开启 Wi-Fi 无线续签）。
3. 在 iPhone 的 **Watch App → 模块表盘 → 复杂功能 → PulseOS** 中添加 **「HRV 当前状态」** 或 **「昨晚生命体征」**。
