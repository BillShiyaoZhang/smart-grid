# 潮汐电网 · TIDAL GRID

使用 **Godot 4.7** 制作的 2.5D 斜视角智能电网建造经营游戏。以海湾小城为舞台，建设发电与储能设施，铺设电网，管理供需与现金流，并在风暴中恢复供电。

已加入电力交易中心：零售电价、现货购售电、联络站、储能策略、12 小时锁价合约和运营账本。具体玩法见 [电力市场指南](docs/MARKET.md)。

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

首次自然风暴将在第 1 天 14:00 到来，此后每 30 游戏小时一轮，提前 1 小时预警。昼夜会改变光照与建筑灯光，风暴时出现雨幕。停电会产生每 MWh ¥60 的失供补偿；控制台还会记录累计供电可靠率。

开局可先选择「连线」，连接中央变电站与东侧工业园区，完成「点亮海湾」。更详细的模型和上手说明见 [架构与玩法说明](docs/ARCHITECTURE.md)。

## 操作

以下快捷键由主程序实现；若修改输入逻辑，请同步本表。

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
| 操作指南 | H |
| 电力交易中心 / 返回电网 | M / Esc |
| 数字电网运行中心 / 返回电网 | N / Esc |
| 代际科技、精细调度与区域沙盘 / 返回 | T / Esc |
| 保存游戏 | F5（运行中的游戏窗口） |
| 读取游戏 | F9 |

点击线路可发送远程开关命令、派现场队、巡检、增容或抢修。远程命令需要研究、两端可信通信和新鲜遥测，并在延迟后重新验证执行；失联时可现场处置。完成第二级研究后，可向可控负荷启动「需求响应」。手动存档和每 90 秒的自动存档使用独立文件，保存于 Godot 的 `user://` 数据目录。

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
- `assets/art/`：内置 image_gen 生成的原创封面及提示词记录。
- `assets/icons/`：与建筑模型一致的设施图标。
- `scenes/`：游戏场景。
- `tests/`：可无图形界面运行的仿真验证。
- `docs/ARCHITECTURE.md`：实现范围、架构、模型和玩法对应关系。
- `docs/MARKET.md`：市场玩法、操作流程、报价与账本说明。
- `docs/DIGITAL.md`：通信、观测、控制队列与网络事件处置。
- `docs/GAMEPLAY.md`：历史开局、代际研究、运行约束、储能组合、动态城市与长期目标。

电力模型面向玩法：保留拓扑、容量、储能和故障的战略后果，采用简化的电力计算，不作为工程设计工具。

## 美术来源

建筑、设施和地形由项目脚本创建，采用统一低多边形风格。封面 `assets/art/bay_cover.png` 使用内置 image_gen 工具原创生成，完整提示词见 `assets/art/PROMPT.md`。

中文字体为 **Noto Sans CJK SC Regular**，来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk)，按 [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE) 分发；许可证随项目保存在 `assets/fonts/OFL.txt`。
