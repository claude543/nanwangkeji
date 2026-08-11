# 暑期南网科技项目｜V4 板端 AGC 调用、JSON、状态初始化与 Candidate-Commit 彻底理解版

> 依据：`V4.0-shadow_板端AGC需求_20260807_FINAL`、`V4.0版20260807`、冻结的 `agc_controller.c/.h` 及当前 V3.2 安全状态机。  
> 目标：把 V4 要求中最容易看不懂的程序术语和状态管理逻辑讲清楚，而不是只记代码。
>
> **先记住一句总原则：**
>
> > **V4 不是“板端算出命令就算成功”，而是要严格区分：数据读到了没有 → 算法有没有产生新结果 → 结果是否合法 → 能不能编码 → FC16 是否真正写成功 → 成功以后才允许把这次算法历史记成“正式发生过”。**
>
> 这就是 V4 中 `candidate_state → successful commit` 设计的核心。

---

# 0. 先看一眼 V4 整体流程

当前 V4 是 **shadow（影子）模式**：

```text
RT-LAB
40101～40116真实状态
        ↓
     FC03读取
        ↓
板端 V3.2 安全检查
        ↓
     形成 snapshot
        ↓
  C版 AGC 计算
        ↓
 40001～40009候选结果
        ↓
加入40010～40012管理量
        ↓
       FC16
        ↓
写回 RT-LAB 寄存器
```

但是当前 V4：

```text
40001～40006
还不接六台设备 Pref
```

所以它是：

> **真实读、真实算、真实写，但暂时不真正接管六台逆变器。**

V5 才会把：

```text
40001～40006
→ 安全门
→ 六台 Pref
```

真正接到设备。

---

# 1. 先建立一张“英文术语翻译表”

| 英文/代码名 | 中文直译 | 在 V4 中真正代表什么 |
|---|---|---|
| `main program` | 主程序 | 板端最外层程序，负责通信、安全状态机、调度、调用AGC、FC16、日志 |
| `AGC` | Automatic Generation Control | 当前基础有功协调算法 |
| `AgcState` | AGC状态 | AGC内部“记忆”，保存上一次资源命令、时间、状态等历史 |
| `AgcInputs` | AGC输入 | 本次调用AGC使用的PCC、PVmax、SOC、time、enable等 |
| `AgcOutputs` | AGC输出 | 六路命令、status、dP、remain等 |
| `reset` | 重置 | 把AGC状态标成“尚未初始化”，清除旧程序历史 |
| `init` | 初始化 | 用第一批可信数据建立AGC正式初始状态 |
| `step` | 执行一步 | 用当前输入把AGC推进一个控制周期或保持不变 |
| `enable` | 使能 | 本次AGC是否允许真正推进 |
| `JSON` | 配置文件格式 | 把目标值、增益、SOC边界、开关等放在程序外配置 |
| `snapshot` | 快照 | 同一次FC03得到的一整套同一时刻数据 |
| `candidate` | 候选 | 已经算出来，但还不能认为正式成功的状态/命令 |
| `commit` | 提交 | 确认FC16成功后，把候选状态正式写成AGC历史 |
| `committed` | 已提交 | 已经被确认成功发布的正式状态/命令 |
| `UPDATED` | 已更新 | 本次AGC真正产生了新的候选历史和命令 |
| `HELD` | 保持 | 本次没有产生新AGC历史，继续使用上次已提交结果 |
| `ERROR` | 错误 | 本次算法输入/参数/计算无效，不能发布 |
| `finite` | 有限数 | 不是 `NaN`、`+Inf`、`-Inf` |
| `range` | 范围 | 输出必须落在PV/ESS/EV等合法上下限内 |
| `encode` | 编码 | 把AGC工程量/pu输出转成Modbus raw整数 |
| `FC03` | Read Holding Registers | 板端一次读取40101～40116 |
| `FC16` | Write Multiple Registers | 板端一次写40001～40012 |
| `CMD_SEQ` | Command Sequence | 成功提交的新AGC状态序号 |
| `candidate_cmd_seq` | 候选序号 | 这次候选结果若成功将使用的下一序号 |
| `committed_cmd_seq` | 已提交序号 | 最后一次真正成功提交的序号 |

---

# 2. 问题1：`enable` 为什么由 `agc_enable` 和 V3.2 安全状态产生？

需求写的是：

```text
enable：
由主程序根据 agc_enable 和 V3.2 安全状态产生
```

这里有三个非常容易混淆的“使能”。

---

## 2.1 `external_enable_request`

来自 JSON。

它属于：

```text
V3.2安全层
```

它回答：

> **“我是否申请让外部控制链取得安全资格？”**

如果：

```text
external_enable_request = false
```

那么即使网络完全正常：

```text
V3.2也不能进入 ENABLED
```

---

## 2.2 `agc_enable`

也来自 JSON。

它属于：

```text
V4算法层
```

它回答：

> **“通信已经安全了以后，我现在要不要真正运行C版AGC？”**

所以可以出现：

```text
V3.2状态 = ENABLED
但 agc_enable = false
```

此时：

```text
通信和数据都安全
但故意不运行AGC
```

---

## 2.3 `enable` —— 真正送进 `agc_controller_step()` 的算法输入

在 `AgcInputs` 中有：

```c
bool enable;
```

它不是单纯读取 JSON 的 `agc_enable`。

主程序需要综合判断：

```text
agc_enable
+
V3.2当前是否处于ENABLED
```

再形成：

```text
inputs.enable
```

概念上：

```text
enable
=
agc_enable
AND
(V3.2_state == ENABLED)
```

同时，主程序只有在：

```text
FC03成功
核心数据有效
有新的完整snapshot
调度时间允许
```

时才真正调用AGC。

所以 `enable` 可以理解为：

> **“算法本身现在是否允许推进历史状态”的最后一道软件使能。**

---

# 3. 为什么不能只用一个 enable？

因为这几层回答的问题不同：

```text
external_enable_request
↓
“我要不要申请进入外部控制安全状态？”


V3.2 ENABLED
↓
“通信、心跳、模型状态、数据有效性是否真的已经证明安全？”


agc_enable
↓
“安全以后，我要不要运行AGC算法？”


inputs.enable
↓
“本次具体调用AGC时，算法到底允许不允许推进？”
```

如果全部混成一个开关，出现异常时就不知道：

```text
是用户没申请？
是通信不安全？
还是算法被人为关闭？
```

所以必须分层。

---

# 4. `40101、40105～40108` 为什么叫“动态测量输入”？

当前基础 C AGC 真正使用的测量只有：

```text
40101 PCC_P
40105 PV1_P_MAX
40106 PV2_P_MAX
40107 ESS1_SOC
40108 ESS2_SOC
```

它们都来自 RT-LAB 的真实系统状态，而且会随时间变化。

所以叫：

```text
dynamic measurement inputs
动态测量输入
```

---

## 4.1 `40101 PCC_P`

告诉AGC：

> **“整个微网现在PCC实际是多少kW？”**

AGC用它计算：

```text
dP
=
Ptarget - Ppcc
```

---

## 4.2 `40105 / 40106 PV_MAX`

告诉AGC：

> **“两台PV当前最多能发到多少kW？”**

例如：

```text
AGC想让PV1从40增加到80 kW

但当前PV1_MAX只有65 kW
```

那么算法最多只能分到：

```text
65 kW
```

---

## 4.3 `40107 / 40108 SOC`

告诉AGC：

> **“ESS当前还有没有资格继续充/放电？”**

当前AGC内部边界：

```text
SOC_min = 0.2
SOC_max = 0.9
```

例如：

```text
SOC <= 0.2
→ 不允许继续放电

SOC >= 0.9
→ 不允许继续充电
```

---

# 5. 为什么 `time_s` 和 `enable` 叫“算法调度输入”？

它们不是物理测量。

它们不回答：

```text
PCC多少？
PVmax多少？
SOC多少？
```

而是在回答：

```text
“这一次算法该不该真正更新？”
“距离上一次更新够不够1秒？”
```

因此叫：

```text
scheduling inputs
调度输入
```

---

## 5.1 `time_s`

来源：

```text
板端 monotonic clock
单调时钟
```

不是：

```text
401xx寄存器
```

也不是系统日期时间。

为什么用单调时钟？

AGC真正关心：

```text
距离上一次执行过去了多久？
```

而不是：

```text
现在是15:30还是15:31？
```

系统日期时间可能被：

```text
NTP校时
人工修改
时区修改
```

而突然跳变。

单调时钟只会：

```text
0 → 1 → 2 → 3 ...
```

向前走。

因此更适合判断：

```text
time_s - last_time_s >= ts_agc_s
```

---

## 5.2 `enable`

告诉算法：

```text
“即使时间到了，现在是否真的允许推进？”
```

所以：

```text
time_s
= 什么时候可以算

enable
= 现在有没有资格算
```

---

# 6. 40115 / 40116 为什么不是 AGC 输入，但又很重要？

```text
40115 MODEL_STATUS
40116 RTLAB_HEARTBEAT
```

它们不是用来决定：

```text
PV该加多少
ESS该放多少
```

而是用来决定：

```text
“这批测量到底能不能信？”
```

因此它们属于：

```text
V3.2安全状态机
```

不属于：

```text
C版AGC数学输入
```

可以记成：

```text
40101、40105～08
→ 决定“怎么控制”

40115、40116
→ 决定“有没有资格控制”
```

---

# 7. 问题2：JSON 到底是什么？为什么 V4 要用 JSON？

JSON 全称：

```text
JavaScript Object Notation
```

但在这里不用管 JavaScript。

你只需要把它理解成：

> **一种结构化的文本配置文件。**

例如：

```json
{
  "agc_enable": true,
  "p_target_kw": -100.0,
  "p_unit_kw": 100.0,
  "soc_min": 0.2,
  "soc_max": 0.9
}
```

人可以直接看懂：

```text
AGC开
目标-100 kW
1 pu = 100 kW
SOC范围0.2～0.9
```

程序启动时读取这些值。

---

# 8. 为什么不把这些参数直接写死在 `.c` 代码里？

假设把目标功率写死：

```c
p_target_kw = -100.0;
```

以后你想改成：

```text
-80 kW
```

就必须：

```text
改C源码
→ 重新编译
→ 再部署
```

如果放 JSON：

```json
"p_target_kw": -80.0
```

只改配置文件即可。

因此 JSON 的作用是：

> **把“经常需要调整的运行参数”和“应该冻结不动的算法核心代码”分开。**

这非常重要。

---

# 9. 当前 V4 JSON 每个参数是什么意思

当前正式基线：

```json
{
  "algorithm_mode": "agc_shadow",
  "test_mode": false,
  "external_enable_request": true,
  "agc_enable": true,
  "p_target_kw": -100.0,
  "pcc_sign_gain": -1.0,
  "p_unit_kw": 100.0,
  "p_dead_kw": 2.0,
  "soc_min": 0.2,
  "soc_max": 0.9,
  "ts_agc_s": 1.0,
  "pv_init_kw": 0.0,
  "ev_init_kw": 60.0,
  "agc_reset_on_reconnect": false,
  "agc_csv_enable": true
}
```

---

## `algorithm_mode = "agc_shadow"`

意思：

```text
当前运行V4影子AGC
```

告诉主程序：

> 当前不是V3.2固定测试模式，也不是V5真实接管模式。

---

## `test_mode = false`

V3.2时：

```text
40001～40009可以使用固定测试值
```

V4：

```text
false
```

表示：

> 40001～40009应该来自真实C AGC结果，而不是测试Constant。

---

## `external_enable_request = true`

申请 V3.2 允许进入：

```text
ENABLED
```

它是安全层开关。

---

## `agc_enable = true`

允许主程序调用：

```text
C版AGC
```

它是算法层开关。

---

## `p_target_kw = -100`

AGC目标：

```text
PCC = -100 kW
```

当前算法方向：

```text
正 = 向上级送电
负 = 从上级购电
```

所以：

```text
-100 kW
= 目标购电100 kW
```

---

## `pcc_sign_gain = -1.0`

这是：

```text
协议方向
→
算法方向
```

的转换系数。

当前 Modbus 40101：

```text
购电为正
```

例如：

```text
+120 kW
```

而 C AGC：

```text
购电为负
```

所以：

```text
+120 × (-1)
= -120 kW
```

注意：

> 这不是控制增益，只是符号适配参数。

---

## `p_unit_kw = 100`

表示：

```text
1 pu = 100 kW
```

例如：

```text
EV输出 -0.6 pu
= -60 kW
```

---

## `p_dead_kw = 2`

AGC死区：

```text
|dP| <= 2 kW
```

时认为：

```text
偏差已经足够小
```

不需要为了1～2 kW的小波动不断调资源。

---

## `soc_min = 0.2`
## `soc_max = 0.9`

ESS充放电控制边界。

注意它们不是：

```text
V3.2通信有效范围
```

V3.2通信只要求SOC数据本身合理，例如0～1。

而：

```text
0.2～0.9
```

是 AGC 的运行约束。

---

## `ts_agc_s = 1.0`

AGC最小更新周期：

```text
1秒
```

不是：

```text
RT-LAB的100 μs基本步长
```

也不是：

```text
网络延时
```

---

## `pv_init_kw = 0`

AGC刚初始化时：

```text
两台PV内部命令从0 kW开始
```

但还要受：

```text
当前PV_MAX
```

限制。

---

## `ev_init_kw = 60`

AGC内部保存：

```text
EV充电幅值 = +60 kW
```

但对外命令是：

```text
-0.60 pu
```

因为当前统一规定：

```text
EV充电为负
```

---

## `agc_reset_on_reconnect = false`

普通 Modbus 断线重连：

```text
不清空AGC历史
```

而是：

```text
暂停
→ 保留正式状态
→ 恢复后从原状态继续
```

---

## `agc_csv_enable = true`

允许记录板端：

```text
逐周期AGC CSV日志
```

用于以后对比：

```text
板端读到什么
算了什么
FC16成功没有
最终commit了什么
```

---

# 10. 问题3：为什么要“在候选 AgcState 上调用一次 step”？

需求：

```text
条件满足时
→ 在 candidate_state 上调用一次 agc_controller_step()
```

先理解：

```text
AgcState
```

到底是什么。

---

# 11. `AgcState` 是什么？

它不是单个“状态码”。

它是 AGC 的**内部记忆包**。

冻结C代码中主要记着：

```text
pv_kw[2]
→ 当前算法认为两台PV命令历史是多少

ess_kw[2]
→ 当前算法认为两台ESS命令历史是多少

ev_charge_kw[2]
→ 当前算法认为两台EV充电幅值历史是多少

last_time_s
→ 上一次AGC真正更新时间

status
→ AGC状态

last_dp_kw
→ 上一次功率偏差

last_remain_kw
→ 上一次未分配量

initialized
→ 是否已经初始化
```

所以：

> **`AgcState` 就是“控制器脑子里认为自己目前走到哪一步”的完整历史。**

---

# 12. 为什么 AGC 必须保存历史状态？

当前基础AGC不是每次都从零算。

例如上一拍：

```text
PV1 = 20 kW
PV2 = 20 kW
EV1 = -60 kW
EV2 = -60 kW
```

下一拍如果还差：

```text
+10 kW
```

AGC是从：

```text
当前内部20 kW
```

继续往上分。

不是重新：

```text
从PV=0开始
```

所以必须记住历史。

---

# 13. `candidate_state` 是什么？

代码：

```c
AgcState candidate_state = agc_state;
```

意思：

```text
正式状态 agc_state
复制一份
→ candidate_state
```

可以把它理解成：

> **“草稿状态”或“试算状态”。**

真正的 `agc_state`：

```text
已经确认成功发布过的正式历史
```

`candidate_state`：

```text
本次准备尝试的新历史
但还没得到FC16成功确认
```

---

# 14. 为什么不能直接在正式 `agc_state` 上计算？

这是 V4 最关键的问题。

假设正式状态：

```text
PV1 = 20 kW
```

本次AGC算出：

```text
PV1应该变成30 kW
```

如果你直接：

```text
agc_state
20 → 30
```

然后 FC16 网络写失败：

```text
RT-LAB根本没有收到30 kW
```

但板端AGC脑子里已经认为：

```text
“我已经把PV1调到30 kW了。”
```

于是发生：

```text
控制器内部状态 = 30
实际成功发布状态 = 20
```

这就是：

> **内部状态提前前进。**

正是我们前期下行中断试验暴露的问题之一。

---

# 15. candidate 的作用就是“先试算，别急着承认发生过”

正确：

```text
正式状态 = 20
↓复制
候选状态 = 20
↓在候选上算
候选状态 = 30
```

此时：

```text
正式状态仍然 = 20
```

接下来：

```text
30 kW结果
→ 编码
→ FC16
```

只有 FC16 真成功：

```text
agc_state = candidate_state
```

才正式变成：

```text
30
```

所以这套机制相当于：

> **“命令真正发成功以后，控制器才允许自己相信它已经发生。”**

---

# 16. 为什么同一次 snapshot 只能调用一次 AGC？

要求：

```text
同一批FC03数据
最多调用一次agc_controller_step()
```

假设：

```text
PCC = -120 kW
```

这一批数据没变。

如果错误地调用两次：

```text
第一次：
PV +10

第二次：
还拿同一个旧PCC=-120
又PV +10
```

控制器可能在没有新物理反馈的情况下连续推进两次。

这相当于：

```text
用一张旧照片连续做两次控制决策
```

会人为制造命令积累。

正确：

```text
一张新snapshot
→ 最多一次AGC决策
```

---

# 17. 什么条件满足才允许调用 AGC？

正式要求同时满足：

```text
1. agc_enable = true
2. V3.2状态 = ENABLED
3. 本周期 FC03 成功
4. 核心测量有效
5. 本周期有一份新的完整 snapshot
6. 主程序调度允许
```

缺一不可。

---

# 18. 为什么必须先检查 `finite`？

`finite` 意思：

```text
有限实数
```

不能出现：

```text
NaN
+Inf
-Inf
```

例如：

```text
0/0
→ NaN

1/0
→ Inf
```

这种数一旦进入：

```text
寄存器编码
```

根本没有合理物理意义。

所以要先问：

```text
“算法输出是不是一个正常实数？”
```

---

# 19. 为什么还要检查范围？

即使是有限数：

```text
PV = 5.7 pu
```

也仍然是非法的。

V4输出要求：

```text
PV：0 ～ 1 pu
ESS：-1 ～ 1 pu
EV：-1 ～ 0 pu
AGC_STATUS：-2 ～ 2
remain >= 0
```

所以需要两层：

```text
finite
→ 数学上是否正常

range
→ 物理/协议上是否合理
```

---

# 20. 为什么输出合法以后还不能直接 FC16？

因为 C AGC 输出的还是：

```text
pu
kW
状态量
```

而 Modbus 需要：

```text
16位 raw 整数
```

所以必须：

```text
AGC工程量
→ encode
→ 40001～40009 raw
```

例如：

```text
PV1 = +0.30 pu
```

点表：

```text
0.0001 pu/count
```

则：

```text
0.30 / 0.0001
= 3000 count
```

再转成：

```text
INT16 raw = 3000
```

这就叫：

```text
encode
编码
```

---

# 21. `encode_ok` 是什么意思？

就是：

> **这次AGC输出能不能按照V3.1/V3.2点表规则正确转换成合法40001～40009。**

可能失败的原因例如：

```text
输出越界
类型不合法
转换异常
```

所以：

```text
算法算对
≠
一定能合法发布到Modbus
```

---

# 22. 问题4：为什么启动要 `reset → init → step`？

正式要求：

```c
agc_controller_reset(&agc_state);

第一批FC03成功
且核心测量有效以后

agc_controller_init(...);

以后周期调用
agc_controller_step(...);
```

三个函数作用完全不同。

---

# 23. `agc_controller_reset()` 是什么？

`reset`：

```text
重置
```

冻结C代码中主要效果：

```text
清空AgcState
last_time_s = -1
initialized = false
```

它的目的不是：

```text
“根据真实系统初始化”
```

而是：

> **告诉程序：这是一次新的板端程序启动，以前内存中的AGC历史全部不可信。**

---

# 24. 为什么程序一启动必须 reset？

因为内存里不能假设：

```text
上一轮程序留下的数字
就是这次真实系统状态
```

程序重启就是一个全新的控制器生命周期。

所以先：

```text
清空旧历史
```

---

# 25. `agc_controller_init()` 是什么？

`init`：

```text
initialize
初始化
```

它会真正建立当前AGC的初始资源状态。

当前规则：

```text
PV：
= pv_init_kw
但不得超过当前PV_MAX和p_unit

ESS：
= 0

EV：
内部保存正充电幅值 ev_init_kw
当前 = 60 kW

对外EV输出：
= -0.60 pu

status = 0
dP = 0
remain = 0
```

---

# 26. 为什么不能程序一启动立刻 init？

因为初始化 PV 需要：

```text
当前真实 PV_MAX
```

例如 JSON：

```text
pv_init_kw = 30
```

但当前天气下：

```text
PV_MAX = 20
```

那么初始化不能设：

```text
30
```

而要受到：

```text
PV_MAX
```

限制。

所以必须：

```text
先FC03
→ 拿到真实PV_MAX/SOC/PCC
→ 证明核心测量可信
→ 再init
```

这就是“第一批成功且有效 FC03 后再 init”的原因。

---

# 27. `agc_controller_step()` 是什么？

`step`：

```text
推进一步
```

它是以后正常运行时反复调用的函数。

输入：

```text
当前 snapshot
当前 time_s
当前 enable
当前 params
当前 AgcState
```

输出：

```text
新的候选状态
六路命令
status
dP
remain
以及 UPDATED/HELD/ERROR
```

---

# 28. 为什么 C 代码本身支持自动 init，但 V4 仍要求显式 init？

冻结C模块中：

```text
如果 state 还没有 initialized
step() 可以自动 init
```

这是算法模块自身的保护能力。

但是正式 V4 主程序要求更严格：

```text
程序启动
→ reset
→ 第一批有效FC03
→ 显式init
→ 后续step
```

原因：

> 主程序应该明确知道“什么时候初始化是安全的”，而不是把初始化时机完全交给算法模块内部兜底。

因此：

```text
auto-init
= 保护机制

显式 init
= 正式工程流程
```

---

# 29. 为什么普通 Modbus 重连不能 reset / init？

假设：

```text
AGC已经运行30秒
当前正式PV命令 = 40 kW
```

网络断1秒又恢复。

如果重新：

```text
reset
init
```

可能突然回到：

```text
PV = 0
EV = -60
ESS = 0
```

等于人为制造一次巨大控制跳变。

正确做法：

```text
断线
→ 暂停AGC
→ 保留最后正式AgcState
→ 40010=0

恢复
→ 重新通过V3.2连续3周期
→ 从原正式状态继续
```

所以：

> **只有板端程序真正重启才 reset；普通通信重连不 reset。**

---

# 30. 问题5：Candidate-State / Successful-Commit 到底怎么工作？

这是 V4 最核心部分。

先记住两个状态：

```text
agc_state
= 正式历史

candidate_state
= 本次试算草稿
```

再记住两个序号：

```text
committed_cmd_seq
= 最后正式成功提交的序号

candidate_cmd_seq
= 本次若成功将使用的新序号
```

---

# 31. `committed` 到底是什么意思？

`commit`：

```text
提交
确认落地
```

在 V4 中：

```text
FC16成功
```

表示：

> **这组命令已经成功写进RT-LAB的40001～40012寄存器。**

因此板端才允许说：

```text
“这次结果已经成功发布。”
```

注意：

> V4是shadow，所以“成功发布”还不等于“六台设备已经实际执行”。

V4解决的是：

```text
u_calc
vs
u_commit
```

即：

```text
算出来
vs
成功发布
```

V5以后才进一步研究：

```text
u_commit
vs
Pmeas / 实际执行
```

---

# 32. `AGC_STEP_UPDATED` 是什么意思？

`UPDATED`：

```text
更新了
```

表示这次 `step()`：

```text
满足enable
满足时间调度
真正推进了AGC内部历史
并生成了一组新的候选命令
```

此时还只是：

```text
candidate
```

不能马上变成正式状态。

---

# 33. UPDATED 后为什么 `candidate_cmd_seq = committed_cmd_seq + 1`？

因为：

```text
CMD_SEQ
```

在 V4 中代表：

> **成功提交的新AGC状态序号。**

例如最后正式成功的是：

```text
committed_cmd_seq = 15
```

现在新算出一份候选：

```text
candidate_cmd_seq = 16
```

如果最终FC16成功：

```text
正式序号变16
```

如果失败：

```text
正式仍然15
```

所以：

```text
candidate_cmd_seq
```

只是“准备成为下一个序号”。

---

# 34. UPDATED 的完整正确流程

```text
正式 agc_state
        ↓ copy
candidate_state
        ↓
agc_controller_step(candidate)
        ↓
AGC_STEP_UPDATED
        ↓
candidate_cmd_seq
= committed_cmd_seq + 1
        ↓
检查 outputs finite
        ↓
检查 outputs range
        ↓
编码 candidate_regs_40001_40009
        ↓
构造 FC16：
40001～40009候选结果
40010～40012管理量
candidate_cmd_seq
        ↓
发送 FC16
```

然后分成两条。

---

# 35. FC16 成功时发生什么？

只有成功以后：

```c
agc_state = candidate_state;
committed_cmd_seq = candidate_cmd_seq;
```

还要保存：

```text
committed_regs_40001_40009
```

作为最新正式成功发布结果。

这一步才叫：

```text
commit
```

---

# 36. 为什么 FC16 成功以后要同时提交“状态”和“序号”？

不能：

```text
状态已经30 kW
但CMD_SEQ仍15
```

也不能：

```text
CMD_SEQ已经16
但状态仍20 kW
```

二者必须对应同一次成功发布。

所以必须：

```text
state
+
seq
+
committed registers
```

作为一个逻辑整体同时更新。

---

# 37. FC16 失败以后为什么不能重新调用 AGC？

假设同一份 snapshot：

```text
PCC = -120 kW
```

第一次调用：

```text
候选PV = 30 kW
candidate_seq = 16
```

FC16因为网络瞬时问题失败。

如果重试前又重新调用 AGC：

```text
同一个旧PCC=-120
又把PV继续推进
→ 40 kW
candidate_seq又可能17
```

这不是“网络重试”。

这已经变成：

> **在没有任何新测量的情况下，算法又执行了一次新控制决策。**

所以重试必须：

```text
完全重发同一个候选报文
同一个candidate_cmd_seq
```

不能重新算。

---

# 38. `retry` 是什么意思？

`retry`：

```text
重试发送
```

它应该是：

```text
同一组 40001～40012 raw
同一个 candidate_cmd_seq
同一个候选结果
```

再次尝试 FC16。

它不是：

```text
重新跑AGC
```

---

# 39. FC16 最终失败后为什么丢弃 candidate_state？

因为实际：

```text
这组新命令从未成功发布
```

所以控制器不应该把它记进正式历史。

因此：

```text
candidate_state
→ 丢弃

agc_state
→ 保持原值

committed_cmd_seq
→ 保持原值
```

这是最关键的“认知一致性”。

---

# 40. 用一个数字例子彻底理解 UPDATED + FC16失败

当前正式状态：

```text
PV1 = 20 kW
PV2 = 20 kW
committed_cmd_seq = 15
```

本次PCC偏差要求增加20 kW。

候选计算：

```text
candidate PV1 = 30
candidate PV2 = 30
candidate_cmd_seq = 16
```

### 情况A：FC16成功

```text
RT-LAB真正收到新命令
```

于是：

```text
agc_state:
20/20 → 30/30

committed_seq:
15 → 16
```

合理。

### 情况B：FC16失败

RT-LAB仍然只知道旧结果。

所以必须：

```text
agc_state仍 = 20/20
committed_seq仍 = 15
```

候选30/30被丢弃。

如果错误保留30/30：

```text
板端认为：我已经做到30/30
RT-LAB实际：最后成功还是20/20
```

控制器和真实发布状态立刻分叉。

---

# 41. `AGC_STEP_HELD` 到底是什么意思？

`HELD`：

```text
保持
```

它不是错误。

它表示：

> **这次调用没有产生新的AGC历史更新。**

可能原因例如：

```text
还没到 ts_agc_s
```

或者算法当前没有执行更新条件。

此时：

```text
不产生新的 candidate_cmd_seq
不推进正式AgcState
```

---

# 42. HELD 为什么还要继续发送旧 40001～40009？

因为：

```text
“这一次没有新命令”
```

不等于：

```text
“以前成功命令失效了”
```

例如最后正式命令：

```text
PV1 = 30
PV2 = 30
CMD_SEQ = 16
```

本周期 HELD。

正确：

```text
继续发送：
PV1 = 30
PV2 = 30
CMD_SEQ = 16
```

也就是继续确认：

> **“当前正式有效结果还是这一份。”**

---

# 43. 为什么 HELD 不能增加 CMD_SEQ？

因为 V4 的 CMD_SEQ 已经定义成：

> **新AGC状态成功提交序号。**

HELD 没有新状态。

所以：

```text
命令值没更新
AGC历史没推进
```

就不能：

```text
CMD_SEQ + 1
```

否则序号会误导为：

```text
“又成功提交了一份新的AGC状态”
```

实际上并没有。

---

# 44. HELD 和“FC16重复发送”是什么关系？

HELD 可以：

```text
再次 FC16 发送最近一次 committed_regs
```

但：

```text
committed_cmd_seq不变
```

所以：

```text
报文又发了一次
≠
新的AGC状态产生了一次
```

---

# 45. `AGC_STEP_ERROR` 是什么意思？

`ERROR`：

```text
算法本次计算不能被信任
```

可能包括：

```text
空指针
输入不是finite
参数不是finite
算法内部异常
```

此时必须：

```text
不commit candidate
不增加CMD_SEQ
40010 = 0
记录错误
```

---

# 46. 为什么 ERROR 时 40010 必须为0？

V4的 40010 不再只是：

```text
“网络正常”
```

而表示：

> **“板端当前存在安全、有效、已经成功发布的AGC结果。”**

当前周期算法都 ERROR 了，就不能继续声称：

```text
外部AGC结果有效
```

所以：

```text
40010 = 0
```

---

# 47. 为什么“输出无效/编码失败”也和 ERROR 类似处理？

可能出现：

```text
AGC函数返回 UPDATED
```

但是后检查发现：

```text
某输出NaN
或
PV=1.5 pu
或
编码失败
```

说明：

```text
算法虽然走完
但这份结果不能安全发布
```

所以：

```text
不能commit
不能CMD_SEQ+1
40010应失效
```

---

# 48. 为什么禁止“正式状态先执行，再FC16失败后保留已经前进的状态”？

错误流程：

```text
agc_controller_step(&agc_state)
↓
正式状态已经改变
↓
FC16
↓
失败
↓
但agc_state已经回不去了
```

结果：

```text
控制器内部认为：
“新命令发生过”

实际通信：
“新命令根本没成功发布”
```

这就是 V4 明确禁止的做法。

---

# 49. 为什么这种设计像数据库“事务”？

可以把一次AGC更新理解成银行转账。

错误做法：

```text
先把你账户扣100元
↓
再尝试转给对方
↓
转账失败
↓
但你的账户已经少100
```

正确做法：

```text
先准备一笔候选交易
↓
所有检查通过
↓
真正转账成功
↓
双方记录一起正式生效
```

这就是：

```text
candidate
→ commit
```

---

# 50. V4 中“三种成功”不能混

## FC03成功

代表：

```text
数据读到了
```

## `AGC_STEP_UPDATED`

代表：

```text
算法算出了一份新的候选状态
```

## FC16成功

代表：

```text
这份候选寄存器真正成功写到了RT-LAB
```

最终新状态真正成功必须：

```text
FC03成功
+
安全有效
+
UPDATED
+
输出finite/range合法
+
编码成功
+
FC16成功
+
commit
```

---

# 51. 为什么 V4 这样设计对论文也有意义？

V4 工程上先解决：

```text
u_calc
≠
u_commit
```

也就是：

```text
算法算了什么
vs
真正成功发布了什么
```

Candidate-commit保证：

> **AGC内部历史只跟“成功发布”的命令同步。**

但是 V4 还没有解决：

```text
u_commit
≠
Pmeas
```

即：

```text
成功发布
不等于
设备真实执行已经完成
```

这个更深的问题正是未来论文改进策略2/7要研究的方向。

---

# 52. 把一次完整 V4 周期从头走到底

每个通信周期可以理解成以下12步：

```text
1. FC03
   读取40101～40116

2. Decode
   raw → 工程量

3. V3.2安全检查
   MODEL_STATUS
   heartbeat
   range

4. 更新状态机
   DISCONNECTED / WAIT_VALID / ENABLED

5. 固定 snapshot
   这次PCC/PVmax/SOC锁定为同一批

6. 判断AGC执行条件
   agc_enable?
   ENABLED?
   新snapshot?
   时间到了?

7. 复制正式状态
   candidate_state = agc_state

8. step(candidate)
   → UPDATED / HELD / ERROR

9. 如果UPDATED
   检查finite/range
   → encode 40001～40009
   → candidate_cmd_seq

10. 生成40010～40012
    构造完整FC16

11. FC16
    成功 → commit
    失败 → 同报文retry
    最终失败 → 丢candidate

12. 写CSV
    记录这整个过程
```

这就是 V4 主程序真正的骨架。

---

# 53. 一张图理解 UPDATED / HELD / ERROR

```text
                  agc_controller_step()
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
       UPDATED           HELD             ERROR
          │                │                │
    新候选状态          没有新状态        算法异常
          │                │                │
   candidate_seq+1       seq不变          seq不变
          │                │                │
   检查+编码             使用旧正式结果    40010=0
          │                │                │
        FC16              FC16可重发        不提交
          │
   ┌──────┴──────┐
   │             │
 成功           失败
   │             │
 commit      retry同报文
 state+seq       │
                 └→最终失败
                   丢candidate
                   正式state/seq不变
```

---

# 54. 四种“状态/命令”以后一定要分清

```text
u_calc
= 算法当前算出的候选命令

candidate_state
= 算出这个命令以后对应的候选内部历史

u_commit
= FC16成功后被正式承认的命令

agc_state
= 与u_commit对应的正式控制器历史
```

未来 V5 / 论文还要再增加：

```text
u_applied
= 设备实际采用的设定

Pmeas
= 设备真实物理功率
```

---

# 55. 最终最通俗的理解

把板端AGC想成一个发指令的调度员。

错误调度员：

```text
我在纸上写：
“PV增加20 kW”
↓
还没确认电话有没有打通
↓
我就在自己的账本写：
“PV已经增加20 kW”
```

电话如果断了：

```text
账本和现场马上不一致
```

V4正确调度员：

```text
先在草稿纸写：
“准备让PV增加20 kW”
↓
检查命令有没有问题
↓
编码
↓
电话真正打通并确认送达
↓
才在正式账本写：
“这条命令已经成功发布”
```

如果电话没打通：

```text
草稿扔掉
正式账本不变
```

这就是：

```text
candidate_state
→ FC16成功
→ commit
```

---

# 56. 最后只需要记住这十句话

1. `40101、40105～40108` 是“系统现在怎样”的动态测量。
2. `time_s` 和 `enable` 是“现在该不该推进AGC”的调度输入。
3. `JSON` 是程序外配置文件，用来改参数而不改C算法源码。
4. `reset` 是清除旧程序历史，`init` 是用第一批可信真实数据建立初始状态，`step` 是以后周期推进。
5. `AgcState` 是AGC内部记忆，不是一个简单状态码。
6. `candidate_state` 是本次试算草稿，FC16成功以前不能成为正式历史。
7. `UPDATED` = 产生新候选；`HELD` = 没新状态、沿用旧正式结果；`ERROR` = 本周期无效。
8. CMD_SEQ 只在“新状态 + 输出有效 + 编码成功 + FC16成功”以后才增加。
9. FC16重试只能重发同一候选报文，绝不能拿同一批旧测量重新调用AGC。
10. V4首先保证“控制器内部历史 = 最后成功发布的命令历史”；V5和论文以后再进一步解决“成功发布 ≠ 设备真实执行”的问题。
