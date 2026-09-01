对。**如果目标明确是 Hero Siege / Diablo / PoE 这一类“高密度战斗 + 随机装备 + Build + 长线内容”的 2D 刷宝游戏，那么研究 Hero Siege 的技术史，比研究一般 Godot 2D Demo 有价值很多。**

Hero Siege 最值得我们学习的地方，甚至不是它“怎么实现”，而是：

> **它用了十几年，反复暴露了这个品类真正会把工程拖垮的系统。**

而且它至今仍然运行在 GameMaker 系技术栈上。SteamDB 在 2026 年 8 月底的构建仍检测到 GameMaker Engine，同时还有 Easy Anti-Cheat、Epic Online Services、cURL 等。([SteamDB][1])

## Hero Siege 的技术演化，其实可以分成 6 个阶段

| 阶段        | Hero Siege 做了什么                        | 暴露的问题                    | 对我们的意义                              |
| --------- | -------------------------------------- | ------------------------ | ----------------------------------- |
| 2013–2014 | GameMaker/GML，小型 Roguelike / wave game | 架构按“小游戏”设计               | **不要按照 Demo 架构做刷宝游戏**               |
| 2014–2018 | 不断加入职业、物品、Act、多人                       | 多人 Bug、系统互相耦合            | 核心系统边界必须早建                          |
| 2019      | GMS → GMS2，近乎完整重写                      | “新系统叠旧系统”，逻辑散落           | 数据驱动、单一规则源非常重要                      |
| 2020      | 战斗、职业、物品、攻击系统继续重构                      | damage/proc/element 组合爆炸 | 战斗计算必须是一条统一 Pipeline                |
| 2022–2023 | Hero Siege 2.0，游戏级别大重制                 | 数据结构无法兼容旧存档，直接 wipe      | Save Schema 必须版本化                   |
| 2025–2026 | Server Authority、AI/碰撞/渲染/Zone 再重写     | 作弊、复制、怪物密度、Projectile 性能 | 网络 Authority 和 Combat Perf 是最终 Boss |

早期 Hero Siege 本身非常简单。官方工作室回顾说，他们最初从移动小游戏开始，Hero Siege 后来才逐渐成长成远超过原始规模的项目；2014 年发布时用的是 GameMaker/GML。([Panic Art Studios][2])

到了 2015 年，多人游戏已经成为典型技术债。主程序当时写到自己几乎一整年都在处理 online multiplayer，并长期被“玩家出生即死亡”“玩家状态串到另一个玩家”等问题困扰。([Panic Art Studios][3])

真正经典的是 **2019 年那次重写**。他们从 GameMaker Studio 迁移到 GMS2 时，官方直接承认：开发 6 年后，代码已经变成“一层系统叠一层系统”，很多逻辑在多个地方重复；平衡一次东西甚至要改四五个 script。于是目标直接变成重新统一 multiplayer、balance、item 和 content architecture。

这其实已经把我们最重要的教训说完了：

> **刷宝游戏最大的问题不是代码量，而是 Rule Duplication。**

---

# Hero Siege 真正被什么东西拖垮了

很多人第一反应会认为是：

> 怪太多，2D 引擎性能不行。

其实只对了一半。

真正的复杂度更接近：

```text
Monster Density
       ×
Projectile Density
       ×
Hit Frequency
       ×
Damage Modifiers
       ×
Status Effects
       ×
Proc Effects
       ×
Loot
       ×
Network Replication
```

假设：

```text
100 enemies
30 projectiles
10 hits/sec
```

表面上只是：

```text
3000 collision checks
```

但一次 Hit 后可能发生：

```text
Hit
 ↓
Crit?
 ↓
Damage conversion
 ↓
Resistance
 ↓
Armor
 ↓
Penetration
 ↓
Life steal
 ↓
On Hit
 ↓
On Crit
 ↓
On Kill
 ↓
Chain
 ↓
Explosion
 ↓
Poison
 ↓
Burn
 ↓
Summon
 ↓
Item proc
 ↓
Talent proc
 ↓
Buff update
 ↓
Combat text
 ↓
Network sync
```

于是一个 projectile 命中根本不是“一次碰撞”。

它是一个 **事件扩散树**。

这也是为什么 Hero Siege 到 2026 年 Season 10 还在专门重写：

> monster AI
> skill data handling
> monster collision
> zone generation

官方称这些重构让 combat FPS 大幅提高。几天后的 7.0.5 又继续优化 multiplier 获取、projectile collision、combat text layering。([Steam Community][4])

所以这是我们第一优先级：

# Combat Pipeline 必须从 Day 1 正确

我不希望看到这种东西：

```gdscript
Enemy.gd
Player.gd
Sword.gd
Fireball.gd
FireSword.gd
PoisonSword.gd
Talent.gd
```

每个自己算：

```gdscript
damage *= crit
damage *= resistance
damage += weapon_damage
```

这就是 Hero Siege 2019 年所描述的那种未来。

我们的结构应该更接近：

```text
Attack
   │
   ▼
DamageContext
   │
   ├ attacker
   ├ target
   ├ source
   ├ tags
   ├ damage_types
   ├ crit
   └ modifiers
   │
   ▼
DamagePipeline
   │
   ├ Base
   ├ Flat
   ├ Increased
   ├ More
   ├ Conversion
   ├ Crit
   ├ Defense
   ├ Resistance
   ├ Penetration
   └ Final
   │
   ▼
DamageResult
   │
   ▼
Effect Pipeline
```

所有职业：

```text
Barbarian
Mage
Necromancer
Paladin
```

所有装备：

```text
Sword
Unique
Runeword
Set
```

都不允许自己计算 damage。

只能给 Pipeline 添加：

```text
Modifier
Tag
Effect
```

这个决定我认为比“Godot 还是 Unity”重要一个数量级。

---

# 第二个 Boss 是 Stat System

Hero Siege 在 2020 年就因为 basic attack 无法正确支持多个 damage type，而不得不重新编程整个攻击系统，并因此推迟赛季。

这个事情非常典型。

刷宝游戏很快就会出现：

```text
+20 fire damage
+12% fire damage
+40% elemental damage

15% physical → fire
20% fire → chaos

+2 skill level
30% crit multiplier

On Crit:
  20% ignite

Against burning:
  +35% damage
```

如果底层模型不正确，后面基本救不回来。

所以我们的 Stat System 应该从一开始就定义清楚 modifier semantics，例如：

```text
BASE
FLAT
ADDITIVE
MULTIPLICATIVE
OVERRIDE
CONVERSION
CAP
```

类似：

```text
final =
(
  base
  + flat
)
×
(
  1 + Σ increased
)
×
Π more
```

并且 modifier 是数据：

```text
Modifier {
    stat_id
    operation
    value
    condition
    source
}
```

而不是：

```gdscript
if item == "SwordOfGod":
    damage *= 1.25
```

否则做 500 件 Unique 之后必死。

---

# 第三个 Boss 是 Item System

Hero Siege 2.0 在 2023 年把整个：

```text
Items
Inventory
Stats
Skills
Relics
Combat
Map generation
AI
```

大量重构。

结果是什么？

**旧存档全部 wipe。**

官方解释得非常清楚：data structure 已经发生重大改变，与旧存档会冲突，所以不得不从头开始。

对于赛季制 ARPG 来说 wipe 没那么致命。

但这是非常昂贵的信号。

所以我会把我们的装备分成：

```text
ItemDefinition
        │
        │ immutable
        ▼
res://data/items/sword.tres

        +

ItemInstance
        │
        ├ unique_id
        ├ definition_id
        ├ item_level
        ├ rarity
        ├ affixes[]
        ├ sockets[]
        ├ rolls[]
        └ metadata
```

非常重要：

> **Resource 是 Definition，不是玩家拥有的具体 Item。**

比如：

```text
Excalibur.tres
```

定义的是：

> 世界上什么叫 Excalibur。

玩家掉出来的是：

```text
ItemInstance {
    definition = "unique.excalibur"
    ilvl = 83
    rolls = [...]
    uid = ...
}
```

这两个不能混在一起。

---

# Save 也不能直接 serialize Scene Tree

我甚至建议从第一版就：

```text
SaveData
schema_version: 1
```

然后：

```text
v1 → v2
v2 → v3
v3 → v4
```

始终存在：

```text
Migration
```

例如：

```text
Save v12

CharacterData
InventoryData
ProgressionData
WorldData
SettingsData
```

Scene Tree 永远不是 Save Schema。

这样以后：

```text
Sword.damage
```

改成：

```text
Weapon.base_damage
```

也不会直接摧毁存档。

---

# 第四个 Boss：PROC 爆炸

这一点我认为 Hero Siege、PoE、Last Epoch 这种游戏最终都会遇到。

比如装备：

> 击杀敌人时 20% 概率爆炸。

另一个：

> Explosion kill 可以触发 Poison Nova。

另一个：

> Poisoned enemy death triggers Corpse Explosion.

那么：

```text
Enemy dies
 ↓
Explosion
 ↓
kills 5 enemies
 ↓
5 × proc
 ↓
25 enemies
 ↓
...
```

这就是所谓的 proc chain。

如果没有统一 Event Context，很容易：

```text
递归
重复 proc
无限循环
服务器不同步
伤害重复计算
```

所以我们应该天然有：

```text
CombatEvent
```

例如：

```text
HIT
CRIT
DAMAGE
KILL
CAST
BLOCK
DODGE
STATUS_APPLIED
ITEM_DROPPED
```

同时事件带：

```text
source
origin
depth
tags
chain_id
```

例如：

```text
tags:
  PROJECTILE
  SPELL
  FIRE
  AREA

depth: 3
```

才能控制：

```text
trigger_from_trigger = false
```

或者：

```text
max_proc_depth = 8
```

---

# 第五个 Boss：性能不是 Sprite，而是 Game Logic

这正是 Hero Siege 最近几年还持续遭遇的问题。

2026 Season 9 官方专门做了：

```text
texture optimization
new drawing system
delta timing
```

Season 10 又继续：

```text
monster AI rewrite
skill/collision backend rewrite
zone generation optimization
```

甚至 Patch 7.0.5 仍然单独优化 projectile collision 和 multiplier fetching。([Steam Community][5])

所以我们的 Godot 项目不能简单：

```text
1000 projectile
=
1000 Area2D

500 monsters
=
500 CharacterBody2D
```

然后认为 Godot Physics 会解决一切。

最早 Demo 可以这么做。

正式 Combat Core 我会逐渐往：

```text
Render ≠ Simulation
```

演进。

比如怪物：

```text
Enemy Visual
     │
     ▼
Sprite2D

Enemy Simulation
     │
     ├ position
     ├ velocity
     ├ hp
     ├ state
     └ target
```

Projectile 更应该考虑：

```text
ProjectileSystem

Typed Array
  position[]
  velocity[]
  lifetime[]
  radius[]
  damage_source[]
```

而不是：

```text
每颗子弹一个复杂 Scene
```

低密度 projectile 仍然可以 Node。

高密度 projectile 则走专门系统。

---

# Godot 在这里反而比 Hero Siege 的历史路线舒服

Hero Siege 当初成长的轨迹是：

```text
small GameMaker game

↓ keep adding features

ARPG

↓ keep adding

multiplayer

↓ keep adding

seasons

↓ keep adding

economy

↓ keep adding

thousands of passive nodes

↓
technical debt
```

现在 Hero Siege 已经发展到：

```text
1600+ Incarnation nodes
400+ Ether nodes
player marketplace
server-authoritative items/gold
crossplay
large monster density
huge item system
```

这已经完全不是 2014 年的游戏了。([Steam Community][5])

我们的优势在于：

**我们一开始就知道最终要做什么。**

所以不需要走：

```text
小游戏
↓
慢慢长成 ARPG
```

这条路线。

可以一开始就是：

```text
ARPG Kernel
↓
Small Content
```

这两个概念差别巨大。

---

# 所以我对我们第一阶段的定义会发生改变

不是：

> 先做一个 Hero Siege clone。

而是：

> **先做一个足以承载 Hero Siege 十年内容增长的 ARPG Kernel。**

然后内容可以非常少：

```text
1 Character
3 Skills
10 Monsters
1 Boss
50 Items
20 Affixes
1 Map
```

但是底层已经存在：

```text
Combat Pipeline
Stat System
Effect System
Item System
Loot System
Ability System
Entity System
World Generation
Save Schema
RNG
Input
UI boundary
```

这就是 vertical slice。

---

# 而且 Agent 会让这套路线特别有价值

因为 Agent 特别擅长：

```text
制造内容
```

比如未来告诉 Agent：

> 给 Fire Mage 增加 12 个 Unique。

如果架构正确，它应该只生成：

```text
12 × ItemDefinition
```

而不是修改：

```text
Player.gd
Damage.gd
Fireball.gd
Enemy.gd
Inventory.gd
```

同理：

> 增加一个 Frost Nova。

Agent 应该：

```text
AbilityDefinition
EffectGraph
VFX
Animation
```

而不是重新写 combat logic。

这就是：

> **Architecture constrains Agent creativity.**

恰恰非常适合我们现在的开发方式。

---

# 我甚至会专门做一个 Combat Simulator

这一点 Hero Siege 当年没有 Agent，我们今天非常值得利用。

把核心 combat 尽量写成：

```text
Godot Scene
      ↓
Combat Core
      ↑
Headless Simulator
```

例如 CLI：

```bash
godot --headless \
  --script simulate.gd \
  --build fire_mage.json \
  --monster inferno_boss.json \
  --duration 60
```

输出：

```text
DPS                 1,842,332
crit rate              47.2%
fire damage             71%
poison damage           12%
proc/sec               18.3
kills/sec              24.1

frame simulation
P50                    1.2ms
P95                    2.8ms
P99                    4.1ms
```

然后 Codex 可以自己做：

```text
修改 Build
↓
运行 10000 场
↓
统计
↓
发现异常 Build
↓
定位 modifier
```

这样以后做：

```text
1000 passive nodes
500 uniques
20 classes
```

才真的可能靠小团队管理。

---

# 多人这一点，需要现在就做一个战略决定

Hero Siege 给我们的另一个巨大教训是：

> **online economy 和普通 co-op 完全不是一回事。**

他们直到 2026 Season 9 才宣布把：

```text
items
gold
```

100% 放到 server authority，目的就是彻底解决 cheating / duping；开发者在 2025 年也明确说作弊已经影响赛季和商业生态。([Steam Community][6])

所以我们的路线如果只是：

```text
4 Player Co-op
friends only
```

可以：

```text
Host Authority
```

简单很多。

但如果未来想做：

```text
Marketplace
Trading
Season Ladder
Competitive Economy
```

那从第一天就要认为：

```text
Client
=
untrusted
```

掉落：

```text
Server decides
```

物品：

```text
Server creates UID
```

交易：

```text
Server validates
```

金币：

```text
Server ledger
```

这件事情不应该到第 5 年再补。

---

# 我们真正应该吸取 Hero Siege 的 5 个教训

我把它压缩成一句工程原则：

> **数据驱动、统一计算、模拟与表现分离、存档版本化、预留 Authority。**

换成我们的 Godot 架构就是：

```text
                    Game
                     │
       ┌─────────────┼──────────────┐
       │             │              │
       ▼             ▼              ▼
   Simulation      Content      Presentation
       │             │              │
       │        .tres / data       Scene
       │                            VFX
       │                            UI
       │
 ┌─────┼────────────┐
 │     │            │
 ▼     ▼            ▼
Stat Combat       Effect
 │     │            │
 └─────┴─────┬──────┘
             ▼
          Events
             │
             ▼
         Game State
             │
       ┌─────┴─────┐
       ▼           ▼
      Save       Network
```

然后最核心的一条：

```text
Presentation
```

绝对不能成为：

```text
Game State
```

---

## 因此，我现在比上一轮更坚定地认为：Godot 4.7.2 很适合我们

但不是因为：

> Godot 很适合做 Pixel Game。

这是很浅的一层。

真正原因是它允许我们把整个游戏构造成：

```text
Resources   → Content
RefCounted  → Simulation objects
Nodes       → Presentation / lifecycle
Scenes      → Composition
GDScript    → Rules
Headless    → Simulation / Tests
MCP         → Agent visual/runtime verification
```

而不是所有东西都是 Scene/Node。

**这才是我们避免 Hero Siege 2019 年那次“六年技术债大清算”的关键。**

Hero Siege 已经帮我们踩过最昂贵的坑了。

如果现在正式开始这个项目，我会把第一份文档直接定义为 **`ARPG_KERNEL_SPEC.md`**，而不是 GDD：先把 **Stat / Modifier / Damage / Effect / Ability / Item / Loot / Entity / Save / RNG / Network Boundary** 这十个底层协议设计清楚，再让 Agent 开始大量生产玩法和内容。这样做出来的东西才有机会真正从“一个好玩的 Demo”长成 Hero Siege 这种可以跑十年、持续加职业和装备的刷宝游戏。

[1]: https://steamdb.info/app/269210/depots/?utm_source=chatgpt.com "Hero Siege Depots · SteamDB"
[2]: https://www.panicartstudios.com/?utm_source=chatgpt.com "Panic Art Studios"
[3]: https://panicartstudios.blogspot.com/?utm_source=chatgpt.com "Panic Art Studios Devlog"
[4]: https://steamcommunity.com/app/269210/announcements?utm_source=chatgpt.com "Steam Community :: Hero Siege"
[5]: https://steamcommunity.com/app/269210/announcements/?utm_source=chatgpt.com "Steam Community :: Hero Siege"
[6]: https://steamcommunity.com/app/269210/eventcomments/594037025395454442/?utm_source=chatgpt.com "Incarnation Tree Progress for Season 9 :: Hero Siege Events & Announcements"
