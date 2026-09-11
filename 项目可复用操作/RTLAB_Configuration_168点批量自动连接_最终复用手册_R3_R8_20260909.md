# RT-LAB Configuration 批量自动连接最终复用手册
## BOARD15 168 点实战：140 点 Alias 自动连接 + 28 点真实端点自动连接

> 适用平台：RT-LAB v2024.1.1.38  
> 项目案例：K26_V5 / BOARD15 / Modbus Slave / Holding Registers  
> 最终结果：168 个点全部完成 Configuration（配置映射）连接。  
> 本文是最终版经验总结，覆盖 R1 → R8 的失败原因、最终正确方法、复用条件和标准执行流程。

---

# 1. 最终结论

本次 BOARD15 共完成：

| 区域 | 数量 | 方向 |
|---|---:|---|
| 40001～40064 | 64 | Board → Model |
| 40101～40124 | 24 | Model → Board |
| 40201～40280 | 80 | Model → Board |
| **总计** | **168** | — |

最终采用两种自动连接方式：

```text
新140点
→ Alias（别名）精确连接
→ BOARD15_RTLAB_AUTO_CONNECT_R3.py

旧28点
→ RT-LAB真实模型端点路径精确连接
→ BOARD15_RTLAB_CONNECT_OLD28_R8.py
```

最终规则：

```text
Board → Model 的 OpInput：
<模型根>/SM_Master/<OpInput块名>/In1/Value

Model → Board 的 OpOutput：
<模型根>/SM_Master/.../<OpOutput块名>/OpOutput/port1
```

其中：

```text
OpInput/port1
```

不是 Configuration 输入端点，不能拿来连接 `From master`。

---

# 2. 当前 GUI 如何判断为正确

在 RT-LAB：

```text
Configuration
→ Aliases
→ OpInputs & OpOutputs
```

应看到：

```text
模型接口名
⇐ / ⇒
Modbus Slave/Slave_1/Holding registers/同名寄存器
```

例如：

```text
BOARD_HEARTBEAT_raw
CMD_SEQ_raw
EXT_AGC_ENABLE_raw
Modbus_4001_raw
...
Op40013_PV1_QREF_raw
...
```

均有对应 Modbus Holding Register 路径。

对于本项目，判断 Configuration 层完成需要同时满足：

```text
1. R3：140 / 140 自动连接成功
2. R8：旧28点自动连接成功
3. R8 POST VERIFY：168 / 168
4. GUI显示168个接口全部存在连接
```

满足以上条件后，Configuration 静态连接层可以冻结。

---

# 3. 这次自动化到底自动化了什么

自动化的是：

```text
Simulink / RT-LAB 模型接口
          ↕
RT-LAB Configuration
          ↕
I/O Interfaces / Modbus Slave / Holding Registers
```

不包括：

```text
创建模型 OpInput / OpOutput
创建 Holding Registers
设置寄存器地址
设置 INT16 / UINT16
修改 Modbus TCP 参数
Build
Load
Execute
板端程序
控制算法
```

因此正确顺序始终是：

```text
模型接口完成
↓
I/O Interfaces 点表完成
↓
Configuration 自动连接
↓
连接验证
↓
Build
```

---

# 4. 方法 A：新接口优先使用 Alias 自动连接

## 4.1 适用条件

当新建接口满足：

```text
Model Alias
=
I/O datapoint Name
=
点表名称
```

例如：

```text
Op40013_PV1_QREF_raw
```

三处完全一致时，最推荐使用 Alias。

BOARD15 新140点就是这种情况。

---

## 4.2 为什么 Alias 方法最好

优点：

```text
不依赖模型层级路径
模型内部移动块影响较小
脚本短
易审计
名称与正式点表一致
```

因此以后新建 RT-LAB 接口时，应主动为自动化设计：

```text
create_alias = on
统一 identifier / alias
I/O Name 与 Alias 同名
```

---

# 5. 方法 B：旧接口使用真实端点路径

旧 V3/V4 接口没有统一 Alias 暴露，因此需要使用 RT-LAB 的真实模型端点。

最终最重要的规律是下面两条。

---

# 6. OpInput 的正确 Configuration 端点

## 正确

```text
<OpInput块>/In1/Value
```

例如：

```text
K26.../SM_Master/Modbus_4001_raw/In1/Value
```

---

## 错误

```text
K26.../SM_Master/Modbus_4001_raw/OpInput/port1
```

后者虽然出现在：

```python
GetSignalsDescription()
```

中，但它代表的是：

```text
OpInput块输出到模型内部的动态信号
```

不是外部 I/O 写入 OpInput 的入口。

---

# 7. R7 的关键失败经验

R7 曾尝试：

```text
Modbus Slave / From master
        ↔
.../Modbus_4001_raw/OpInput/port1
```

RT-LAB 明确报：

```text
Both data points have the same direction (in / out)
```

原因：

```text
From master
= I/O向模型输出

OpInput/port1
= OpInput块向模型输出
```

两端都是同方向，因此不能连接。

最终修正为：

```text
From master
        ↔
<OpInput>/In1/Value
```

方向才互补。

---

# 8. OpOutput 的正确 Configuration 端点

对于 Model → Board：

```text
<OpOutput块>/OpOutput/port1
```

例如：

```text
K26.../SM_Master/V31_RTLAB_To_Board_Test16/Op40101/OpOutput/port1
```

以及：

```text
.../MODEL_STATUS_raw/OpOutput/port1
.../RTLAB_HEARTBEAT_raw/OpOutput/port1
```

这些是真正应该连接 Holding Register `From model` 的模型端点。

---

# 9. 不要绕过 OpInput / OpOutput 接上游计算块

例如：

```text
V4_CAST_40101_INT16
→ Op40101
```

Configuration 应连接：

```text
Holding Register
↔ Op40101/OpOutput/port1
```

而不是：

```text
Holding Register
↔ V4_CAST_40101_INT16/port1
```

原因：

```text
OpInput / OpOutput 是正式 RT-LAB I/O 边界
上游计算块只是模型内部实现
```

绕过接口会破坏架构边界，也不利于后续维护。

---

# 10. R1 → R8 的完整经验

## R1：错误假设 API 返回 tuple

问题：

```python
list(item)
```

实际 RT-LAB 2024.1 返回：

```python
dict
```

导致：

```text
name='name'
type='type'
subsystem='subsystem'
```

读取的是 key 而不是 value。

### 固定经验

所有 RT-LAB API parser 应兼容：

```text
dict
tuple/list
object attribute
```

---

## R2：字段存在不代表字段有值

可能出现：

```python
{
    "uiName": "",
    "name": "Op40274_EV2_EXPECT_TAU_MS_raw"
}
```

脚本如果只判断：

```text
uiName字段是否存在
```

会错误返回空字符串。

### 固定经验

必须寻找：

```text
第一个非空有效字段
```

而不是：

```text
第一个存在字段
```

---

## R3：新140点成功

采用：

```text
精确名称
↓
规范化名称
↓
寄存器号唯一fallback
```

并要求：

```text
targets = 140
matched = 140
missing = 0
duplicates = 0
```

才允许 CreateConnection。

---

## R4：旧28点裸 Alias 失败

错误：

```text
CreateConnection("Modbus_4001_raw", ...)
```

RT-LAB：

```text
Unable to get node associated to path "Modbus_4001_raw"
```

说明：

```text
块名存在
≠
RT-LAB已注册可直接寻址Alias
```

---

## R5：寻找错了旧401xx对象

R5一度寻找：

```text
V4_CAST_40101_INT16
```

但真正接口是：

```text
Op40101/OpOutput/port1
```

### 固定经验

Configuration 连接应首先寻找：

```text
正式 OpInput / OpOutput 边界
```

而不是模型内部上游计算信号。

---

## R6：确认26个真实端点

R6最终确认绝大多数旧接口确实存在真实模型路径。

这一步证明：

```text
自动连接能力没有问题
问题只是端点类型和方向识别
```

---

## R7：方向错误

使用：

```text
OpInput/port1
```

导致：

```text
Both data points have the same direction
```

这是最重要的经验之一。

---

## R8：最终成功

Board → Model：

```text
<OpInput>/In1/Value
```

Model → Board：

```text
<OpOutput>/OpOutput/port1
```

并使用 canary（单点试连）先验证：

```text
Modbus_4001_raw
```

成功后再批量连接其余点。

最终：

```text
168 / 168
```

---

# 11. 为什么 Canary 很重要

对于第一次使用新的端点规则，不应直接批量写 28～200 个点。

先选一个代表点：

```text
Modbus_4001_raw
```

执行：

```text
PRE backup
↓
CreateConnection 单点
↓
ExportConnections
↓
确认该点存在
↓
CANARY PASS
↓
再批量
```

如果 canary 失败：

```text
立即rollback
不碰剩余点
```

这比一次性试整个列表更安全。

---

# 12. 自动连接脚本必须具备的安全结构

任何正式脚本建议固定包含：

```text
1. OpenProject
2. GetIOInterfaces
3. 唯一选定I/O
4. GetConnectionPointsForIO
5. target预检查
6. model endpoint预检查
7. ExportConnections PRE
8. 检查已有连接
9. Canary（新规则第一次使用时）
10. CreateConnection
11. ExportConnections POST
12. POST完整性验证
13. 失败自动ImportConnections PRE
```

---

# 13. Preflight 原则

任何写入前：

```text
target数量
=
唯一I/O点数量
=
唯一模型端点数量
```

只要：

```text
missing > 0
duplicates > 0
方向不确定
```

都必须：

```text
NO WRITE
```

---

# 14. Rollback 原则

任何写入前先：

```python
RtlabApi.ExportConnections(...)
```

保存：

```text
PRE_connections.csv
```

失败后：

```python
RtlabApi.ImportConnections(
    PRE,
    delete_connections=True,
    ...
)
```

恢复。

本项目多轮实际验证：

```text
ROLLBACK PASS
```

有效。

---

# 15. POST Verify 原则

不能把：

```text
CreateConnection没有抛异常
```

等同于：

```text
连接全部正确
```

必须：

```text
CreateConnection
↓
ExportConnections POST
↓
检查所有目标都存在
↓
missing = 0
↓
PASS
```

---

# 16. Partial Run / 幂等原则

脚本需要识别：

```text
already present
to create
```

只补缺失项。

这样即使：

```text
已经手工连接若干条
脚本重复运行
中途断开后再次运行
```

都不会轻易造成重复连接。

---

# 17. 以后如何让项目天然适合自动连接

新项目从一开始统一：

```text
Register Address
I/O Name
Model Alias
变量语义
方向
数据类型
```

推荐命名：

```text
Op<5位寄存器号>_<语义>_raw
```

例如：

```text
Op40280_CONTROLLER_RESET_SEQ_raw
```

避免：

```text
I/O叫A
模型块叫B
Alias叫C
点表叫D
```

这种后期难维护设计。

---

# 18. 什么时候用 Alias，什么时候用真实路径

## 优先 Alias

满足：

```text
Alias唯一
名称稳定
点表与模型同名
```

时：

```text
CreateConnection(alias, io_path)
```

最简单。

---

## 使用真实路径

当：

```text
legacy接口
Alias未注册
Alias不唯一
```

时：

```text
OpInput：
<block>/In1/Value

OpOutput：
<block>/OpOutput/port1
```

---

# 19. 不要把 GetSignalsDescription 返回的所有 port1 都当 Configuration 端点

这是本轮非常关键的认识。

`GetSignalsDescription()` 返回：

```text
模型动态信号
```

其中：

```text
OpInput/port1
```

表示模型内部输出。

它存在并不代表它适合作为 Configuration I/O 入口。

因此：

```text
“API能看到”
≠
“Configuration应该接这里”
```

必须结合端点方向和正式接口语义判断。

---

# 20. BOARD15 最终可复用资产

建议正式保留：

```text
BOARD15_RTLAB_AUTO_CONNECT_R3.py
```

用途：

```text
新增140点Alias自动连接
```

以及：

```text
BOARD15_RTLAB_CONNECT_OLD28_R8.py
```

用途：

```text
旧28点正式端点自动连接
```

并保存：

```text
最终 PRE connections CSV
最终 POST connections CSV
I/O Interfaces .rios
```

形成：

```text
脚本
+
I/O配置
+
Configuration配置
```

三层恢复资产。

---

# 21. 最终验收口径

Configuration 连接层的 PASS：

```text
40001～40064 = 64 / 64
40101～40124 = 24 / 24
40201～40280 = 80 / 80

TOTAL = 168 / 168
```

且代表点方向正确：

```text
400xx
Board → Model
From master → OpInput / In1/Value

401xx、402xx
Model → Board
OpOutput / OpOutput/port1 → From model
```

---

# 22. Configuration PASS 不等于整个板端联调 PASS

必须严格区分：

```text
168/168 Configuration正确
```

只证明：

```text
模型接口 ↔ RT-LAB Modbus I/O
静态映射完成
```

还不等于：

```text
Modbus TCP实际通信PASS
板端读写PASS
INT16/UINT16解释PASS
心跳PASS
CMD_SEQ PASS
BOARD15控制输出PASS
真实设备响应PASS
策略验收PASS
```

后续仍需逐层验证。

---

# 23. 最终标准 SOP

以后再遇到 RT-LAB 上百点 Configuration：

```text
[ ] 模型OpInput/OpOutput已经完成
[ ] I/O Interfaces点表已经完成
[ ] 地址、类型、方向已经冻结
[ ] 优先统一Model Alias = I/O Name
[ ] GetIOInterfaces找到唯一目标I/O
[ ] GetConnectionPointsForIO能完整枚举
[ ] target数量正确
[ ] missing=0
[ ] duplicate=0
[ ] 明确每类模型端点的真实方向
[ ] OpInput使用 /In1/Value
[ ] OpOutput使用 /OpOutput/port1
[ ] ExportConnections PRE
[ ] 第一次使用新端点规则先Canary
[ ] Canary PASS
[ ] 批量CreateConnection
[ ] ExportConnections POST
[ ] POST missing=0
[ ] GUI抽查首/中/尾
[ ] 保存POST CSV
[ ] 导出.rios
[ ] 冻结Configuration
[ ] 再进入Build
```

---

# 24. 一句话记忆

> **RT-LAB批量连接的关键不是“知道块名”，而是识别真正的 Configuration 端点：新接口优先用唯一 Alias；旧接口中 OpInput 接 `/In1/Value`，OpOutput 接 `/OpOutput/port1`。写入前全量预检查，第一次先 Canary，写入后 POST 验证，任何失败都恢复 PRE。**
