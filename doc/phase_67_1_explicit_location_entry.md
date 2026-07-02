# v67.1 明确入口入场规则

v67.1 修复的是地点切换的底层规则：玩家进入任何 location 时，必须知道自己从哪个入口进入。缺入口、入口不存在、入口不可站，都必须失败，不能再用默认入口、地图中心、第一个可站格或左上角继续运行。

## 已真实接入

- `SceneLoader.load_location(scene_path, entrance_id)` 不再接受空入口。
- `WorldLocationGraph` 验证世界数据必须有 `start_spawn_id`，每个 spawn 必须有明确 `entrance_id`。
- `WorldTransitionService` 删除 start 时选择第一个 spawn 的兜底；进入地点前会验证目标 spawn 的入口存在且可站。
- `LocationRoot` 不再读取旧默认入口字段作为玩家出生兜底；场景初始化时会验证当前 `entrance_id`。
- 旧的非世界 `target_scene_path` 转移如果没有 `target_entrance_id` 会失败。
- 位置对象和地面出口仍然需要玩家按 `E/Enter` 交互，不通过踩上去自动切换。
- generated_wild 的入口由世界 spawn / 边关系传入的显式入口提示编译而来。

## 野外入口生成

`WildTerrainGenerator` 仍然可以输出 `spawn_candidates`，但这些候选只表示“可站点”。它们不再自动变成入口。

`WildLocationCompiler` 现在只会根据显式入口提示创建入口：

```text
++ 可站点候选：说明哪里能站人
++ 入口提示：说明哪个 world spawn 要落到哪里
```

边的反向入口仍优先贴近对应出口创建。起始地点没有反向边，因此世界生成器会给 start spawn 写入稳定派生的边位提示，例如 north/east/south/west。

## 删除的旧路径

- 删除世界启动时“没有 start_spawn_id 就拿第一个 spawn”的兜底。
- 删除 `spawn_spec` 没有 `entrance_id` 时用 `spawn_id` 冒充入口的兜底。
- 删除 `LocationRoot` 空入口时读取旧默认入口字段的兜底。
- 删除 wild compiler 用 `spawn_candidates[0]` 创建默认入口的路径。
- 删除 v62 smoke 中“所有出口必须从第一个出生候选可达”的错误断言。

## 已删除的旧字段

旧默认入口字段已经从静态地点、室内生成数据、野外编译数据和烟测数据中移除。v67.1 后，如果某个系统需要进入地点，必须通过 world spawn 或显式 `entrance_id` 传入。

## 未支持

- v67.1 不做浅水/深水比例重分层。
- v67.1 不保证两个入口之间互相可达。
- v67.1 不做跨地点边缘无缝拼接。

## 仍存风险

- 旧静态数据不再声明默认入口字段；如果后续发现新增数据重新引入，应视为入口规则回退并删除。
- 旧非世界场景路径仍存在于测试和历史数据中，但空目标入口会明确失败。
- 野外多入口落点目前按入口提示评分选择可站格，后续可以让入口与跨节点河流、道路、海岸线进一步对齐。

## 验证

新增 `scripts/tests/v67_1_explicit_location_entry_smoke.gd`，验证：

- 空入口加载失败；
- 世界缺 `start_spawn_id` 失败；
- spawn 缺 `entrance_id` 失败；
- generated_wild 缺显式入口提示失败；
- 世界 start spawn 会编译为真实可站入口；
- 世界边 target spawn 会编译为真实可站入口；
- LocationRoot 运行加载后，玩家出生在请求的入口格。
