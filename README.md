# 潮汐电网 · TIDAL GRID

使用 **Godot 4.7** 制作的 2.5D 斜视角智能电网建造经营游戏。以海湾小城为舞台，建设发电与储能设施，铺设电网，管理供需与现金流，并在风暴中恢复供电。

主菜单以「电流的足迹」教学战役为新玩家入口，并提供最近有效进度、经营路线、自由沙盘、设置和退出。暂停菜单支持保存、读取与保存后返回标题；背景展示不会推进游戏或覆盖自动存档。继续入口会检查手动与自动档，跳过损坏候选并保留原文件。

本轮采用精致海湾微缩模型：全部29种设施统一倒角、哑光材质与建筑细节，配有同源图标、十五章缩略图和完整图鉴。标题使用原创海湾插画；设置、章节时间线及各工作台使用原生可操作界面。五首原创循环配乐、环境声、设施声和操作回执已接入，声音只依据公开观测，不泄露未知故障。设计参考与实机资产边界见 [视觉规范](docs/VISUAL_DESIGN.md)。

欢迎页的 **开始运营** 进入循序开放的经营路线：接通工业园、稳住昼夜供需、选择清洁盈利方案、准备并应对首次风暴、逐城开通服务。**自由沙盘** 保留原有完整工具和四项委托；历史战役保持独立进度。经营路线的首次风暴等待玩家确认准备，再给一游戏小时预警。

新版以图解呈现经营判断：顶部供电比例与缺口、地图端点与停电反馈、设施容量条、三方案共轴比较、现场队泳道、收入成本瀑布，以及数字系统就绪条件链。视觉方向和已确认概念见 [设计说明](docs/VISUAL_DESIGN.md)。

欢迎页可进入 **「电流的足迹」全球电力史教学战役**：十五个独立情景，从1882年纽约珍珠街走到当代清洁与智能电网。顺序学习建设、调度、市场、通信、安全和恢复，通关章节可重玩，战役与沙盘分开存档。玩法与史实边界见 [战役指南](docs/CAMPAIGN.md)。

已加入电力交易中心：零售电价、现货购售电、联络站、储能策略、12 小时锁价合约和运营账本。具体玩法见 [电力市场指南](docs/MARKET.md)。

现已加入 **24小时预测与方案推演、停电和完整现金复盘**；研究区域负荷规划后，可逐项投运 **资产寿命与风险检修、双电压输配电、街区光储充电与需求响应、微电网、工程融资、日前购电、备用与政策灾害情景**。用户侧协调还需要SCADA。新功能复用发展、运维和经营三个工作台，旧存档迁移时默认未投运，历史教学保持章节规则。上手与实际模型边界见 [经营扩展指南](docs/EXPANSION.md)。

数字电网包含独立光纤/无线通信、UPS、可信遥测、延迟远程控制、现场巡检和抽象网络安全事件。操作与恢复流程见 [数字电网指南](docs/DIGITAL.md)。

玩法已扩展为 **六代科技、24 项研究、29 种设施**。按 **T** 打开科技与区域规划：可选择爱迪生时代开局，管理核能配套、慢启停、保留电量和可信通信削峰，并主动开启 **48 × 48、八座城市**的动态区域。城市供电、电价、污染影响人口、产业分工与扩张，三类持续运营目标支持长期沙盘。具体边界与组合玩法见 [代际电网与区域指南](docs/GAMEPLAY.md)。

## 启动

在 Godot 4.7 中导入本目录的 `project.godot`，按 **F6** 运行 `scenes/main.tscn`，或按 **F5** 运行项目。

macOS 已安装 Godot 时，也可直接双击 `run_game.command` 启动游戏。

也可从命令行运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## 玩法

1. 查看供需和线路负载，找到城市的瓶颈。
2. 从建造菜单选择设施，左键空地放置。新设施需要连接到电网才能参与供电。
3. 切换电缆工具，依次点击两个建筑创建线路。
4. 组合燃气、风力、光伏和电池，兼顾稳定供电、可再生能源比例和运营成本。
5. 检查过载和故障，派遣维修，建设备用路径；研究遥测与自动化以提高恢复能力。
6. 完成四项运营委托后进入通关面板，可继续自由运营或重新开始。

自由沙盘的首次自然风暴将在第 1 天 14:00 到来，此后每 30 游戏小时一轮，提前 1 小时预警。经营路线在玩家准备后安排首次风暴。昼夜会改变光照与建筑灯光，风暴时出现雨幕。停电会产生每 MWh ¥60 的失供补偿；控制台还会记录累计供电可靠率。

开局可先选择「连线」，连接中央变电站与东侧工业园区，完成「点亮海湾」。更详细的模型和上手说明见 [架构与玩法说明](docs/ARCHITECTURE.md)。

## 界面与信息层级

顶部始终显示供电比例、同标尺供需条和缺口，资金、净收益与时间分组显示。底部「建造」展开五类设施托盘；「经营 M」「运维 N」「发展 T」按经营问题组织入口。地图当前重点卡可直接进入接线或检查，医院与客户的公开供电反馈和已核实故障分别标注。

地图保留当前委托、底部工具栏与经营状态。右侧使用同一个工作区，在「对象」「诊断」「关注」「队列」之间切换：点击供电数字查看缺额、证据与下一步，点击告警定位对象，再查看适用处置。未知故障只显示待核实的原因，不会因打开诊断而被提前揭示。

点击发电、输电、储能、城市或数字分类展开建设托盘，全部 29 种设施使用与实机模型一致的图标。建造悬停预告可建性、费用及失败原因；接线显示候选连接与端点校验，电力线悬停及数字中心的通信报价显示费用。水电、抽蓄的选址范围直接叠在地图上。拆除前确认退款及将移除的线路、通信链路。

**Ctrl+F** 检索设施名称、类型、编号或城市；按可信度、异常及类别筛选，星标设施可固定关注。左侧统计显示有真实游戏时刻的供给、需求、已供电及失供区间；拓扑图可点击定位。远距地图使用设施聚合标记，工具切换自动显示对应电力或通信专题层。

市场、数字电网与科技中心自动暂停时间，可手动推进真实结算。配置区及各设施分别保留草案，切页、关闭重开与提交其他配置不会清空修改；局部重置只影响本区。设施设置的「已排队」与「已生效」分别显示，队列保留近期成功或拒绝回执。读取、重开及切换进度会清除当前会话草案，存在修改时先确认。科技目录支持最多三种设施额定参数对比。

右上菜单与 Esc 打开暂停菜单；主菜单及游戏内共用「画面、声音、操作、界面与辅助、游戏」五页设置。支持窗口/无边框全屏、分辨率、垂直同步、帧率上限、MSAA、五组音量及试听、镜头灵敏度、失焦暂停/静音和自动保存间隔。窗口调整提供15秒确认回退。界面支持 **100% / 125% / 150%** 缩放、高对比和减少装饰动效；个人设置独立于战役及沙盘存档。窗口最低为1280×720，默认1440×900。镜头工作区/全图与手册等操作保留在工作区入口及快捷键。详见 [调度员操作指南](docs/OPERATOR.md)。

## 操作

下表为默认输入。右上菜单的「操作与显示设置」可重绑工具、平移、旋转、暂停、经营中心、手册及存读档键；冲突按键会交换两个操作。Esc 保留用于取消和返回，鼠标操作与 Ctrl+F 为固定输入。手册显示当前绑定。

| 操作 | 输入 |
| --- | --- |
| 选择建筑 / 放置设施 | 左键 |
| 取消当前操作 | 右键 / Esc |
| 选择工具 | 1 |
| 电缆工具 | 2 |
| 维修工具 | 3 |
| 独立通信布线工具 | 4 |
| 平移视角 | WASD / 鼠标中键拖动 |
| 缩放视角 | 鼠标滚轮 |
| 旋转视角 | Q / E |
| 暂停 / 继续 | 空格 |
| 检索设施 / 城市 | Ctrl+F |
| 操作指南 | H |
| 电力交易中心 / 返回电网 | M / Esc |
| 数字电网运行中心 / 返回电网 | N / Esc |
| 代际科技、精细调度与区域沙盘 / 返回 | T / Esc |
| 保存游戏 | F5（运行中的游戏窗口） |
| 读取游戏 | F9 |

点击线路可发送远程开关命令、派现场队、巡检、增容或抢修。远程命令需要研究、两端可信通信和新鲜遥测，并在延迟后重新验证执行；失联时可现场处置。完成第二级研究后，可向可控负荷启动「需求响应」。设施出力、启停与策略设置也需要提交远程命令或派现场队（¥350、约21游戏分钟），排队后才执行。手动存档和每 90 秒的自动存档使用独立文件，保存于 Godot 的 `user://` 数据目录。

市场规划窗口暂停自动时间，可用「推进 1 小时」观察真实结算。字段草案须点击应用才生效，报价刷新不会重复结算。所有价格和资金均为游戏模型。

数字规划窗口同样暂停自动时间，可用「推进 15 分钟」观察测量、命令和恢复。通信线与电缆需分别建设；未知故障不会直接显示精确位置，研究也不能代替有效通信路径。

## 验证与预览

在项目根目录执行以下命令；其他平台可将可执行文件路径替换为 `godot`：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_sim.gd --log-file /tmp/tidal-sim-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_game.gd --log-file /tmp/tidal-game-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_market.gd --log-file /tmp/tidal-market-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_market_game.gd --log-file /tmp/tidal-market-game-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_digital.gd --log-file /tmp/tidal-digital-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_digital_game.gd --log-file /tmp/tidal-digital-game-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_evolution.gd --log-file /tmp/tidal-evolution-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_region.gd --log-file /tmp/tidal-region-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_sandbox.gd --log-file /tmp/tidal-sandbox-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_planning_game.gd --log-file /tmp/tidal-planning-game-test.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/test_dc_solver.gd --log-file /tmp/tidal-dc-solver-test.log
```

新增 `tests/test_hud.gd` 验证情境面板、分类目录、真实键盘输入、经营中心互斥和四种窗口尺寸；`tests/render_ui_matrix.gd` 将 76 个界面与尺寸组合截图保存到 `.godot/ui-qa/`。Windows 可使用安装目录内的 `Godot_v4.7.2-stable_win64_console.exe` 执行相同命令。测试存档使用隔离的 `user://test_*` 路径并在结束时删除。

Windows 可运行 `./tests/run_checks.ps1` 执行全部自动测试，或用 `-GodotPath` 指定 Godot 可执行文件。脚本将进程级 `APPDATA` 隔离到 `.godot/visual-validation/`，记录退出码、检查数量、错误和超时。新专项覆盖经营路线真实通关、存档迁移、视觉数据口径与界面执行闭环；`tests/render_redesign.gd` 生成实际界面、多比例和夜间风暴截图，输出到 `.godot/redesign-qa/`。

本次调度工作流另有 `test_operator_model.gd`（无副作用预览、信息边界与真实回执）、`test_center_drafts.gd`（独立草案、局部提交、切换确认、设施对比与战役提示）、`test_operator_preferences.gd`（设置、重绑及真实时间图表）及 `test_operator_focus.gd`（真实键盘焦点与模态隔离）。`tests/render_operator_workflow.gd` 生成 64 张全场景截图，覆盖最低分辨率下 100% / 125% / 150% 缩放、常规窗口、诊断、检索、队列、对比、拆除及夜间风暴高对比状态，保存到 `.godot/operator-workflow-qa/`。详见 [验证记录](docs/VALIDATION.md)。

仿真测试检查网络功率守恒、环网分流、储能能量、保护和维修、确定性、存档、任务和自动恢复；集成测试实例化真实主场景，验证界面操作、地图建造接线及模型同步。

市场测试另覆盖电价与用户需求、跨区电力交付、储能策略、锁价承诺、结算账本，以及配置草案与预测刷新无副作用。

数字测试覆盖独立通信、UPS、可信观测、在途命令、现场作业、安全演练、隔离修补、故障信息隐藏及队列存档。

- 游戏画面：[docs/screenshots/gameplay.png](docs/screenshots/gameplay.png)。
- 建筑资产总览：[assets/models/art_catalogue.png](assets/models/art_catalogue.png)。
- 海湾地形预览：[assets/models/island_catalogue.png](assets/models/island_catalogue.png)。
- 可单独编辑或复用的建筑场景：`assets/models/*.tscn`；地形场景：`assets/models/bay_island.tscn`。
- 建造菜单的设施图标：`assets/icons/*.png`，由同一组 3D 模型渲染。

重新生成建筑或地形预览需要图形渲染窗口：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . -s scripts/art/art_gallery.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . -s scripts/art/art_gallery.gd -- --island
```

## 项目结构

- `scripts/sim/`：独立于场景渲染的电网、调度、经济、事件与持久化仿真。
- `scripts/art/`：原创程序化低多边形建筑和海湾地形资产。
- `assets/art/`：同源模型渲染的当前封面，以及早期封面与提示词记录。
- `assets/icons/`：与建筑模型一致的设施图标。
- `scenes/`：游戏场景。
- `tests/`：可无图形界面运行的仿真验证。
- `docs/ARCHITECTURE.md`：实现范围、架构、模型和玩法对应关系。
- `docs/MARKET.md`：市场玩法、操作流程、报价与账本说明。
- `docs/DIGITAL.md`：通信、观测、控制队列与网络事件处置。
- `docs/GAMEPLAY.md`：历史开局、代际研究、运行约束、储能组合、动态城市与长期目标。
- `docs/OPERATOR.md`：诊断工作区、建设预览、草案与回执、检索对比及操作显示设置。

电力模型面向玩法：保留拓扑、容量、储能和故障的战略后果，采用简化的电力计算，不作为工程设计工具。

## 美术来源

建筑、设施和地形由项目脚本创建，采用统一微缩模型风格。`assets/art/operator_cover.png`、全部29种设施图标与十五章缩略图由同一组实机模型渲染；可用 `scripts/art/render_operator_cover.gd`、`render_icons.gd`、`render_chapters.gd` 在图形模式重新生成。`assets/models/build_assets.gd` 导出完整29种可编辑设施场景，运行时仍以模型工厂为唯一来源。主菜单背景 `assets/art/title_bay.png` 由内置imagegen原创生成，不包含按钮或文字，来源与提示词见同目录 `title_bay.source.json`。六张视觉参考保存在 `docs/design/visual-refresh-2026-10-30/`。

音频全部由原创旋律与确定性合成制作，没有外部录音或采样包；钢琴为合成音色。制作与验证脚本位于 `tools/audio/`，文件、时长和校验摘要见 `assets/audio/manifest.json`，详见 [声音来源](assets/audio/README.md)。

中文字体为 **Noto Sans CJK SC Regular**，来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk)，按 [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE) 分发；许可证随项目保存在 `assets/fonts/OFL.txt`。

## 跨系统回归

新增五套测试：`test_dispatch_integration.gd`（混合电源、光储来源、孤岛合约与重算守恒）、`test_thermal_integration.gd`（最低负荷、辅机保障、配套与检修）、`test_city_assets.gd`（人工建设归属、拆迁与退款、旧档迁移）、`test_digital_boundaries.gd`（设施命令、观测、历史数字化与攻击边界）、`test_facility_ui.gd`（真实按钮、排队回执与失败反馈）。均可按上面的 Godot `--headless --path . -s tests/<脚本>.gd` 命令运行。当前存档为 schema 8，兼容旧版本；详细验证见 [验证记录](docs/VALIDATION.md)。

战役另有 `test_campaign.gd`（十五关真实操作与途中读档继续）、`test_campaign_boundaries.gd`（年代能力、固定购电、观测与存档边界）、`test_campaign_maps.gd`（地图与城市登记）、`test_campaign_game.gd`（真实界面与顺序解锁）。图形模式运行 `tests/render_campaign.gd` 可在 `.godot/campaign-qa/ui/` 生成四种分辨率的战役截图。
