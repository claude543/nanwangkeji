# BOARD15 内部设计04｜最终 Modbus 点表与 Runtime Config 架构 V0.1
## ——在现有 V3.2 / V4 / V5 点表上最小扩展，支持15项功能真实板端闭环

> **日期**：2026-08-18  
> **性质**：内部拟冻结设计，不直接作为工程开发方最终版本要求。  
> **前置基线**：
> - 现有 V3.2 / V4：`40101～40116` 为 RT-LAB→Board 测量/管理块；
> - 现有 V3.2 / V4 / V5：`40001～40012` 为 Board→RT-LAB 控制/管理块；
> - BOARD15 正式基础周期：`100 ms`；
> - 仲裁型基础 AGC：`1 s`；
> - 目标范围：只服务《智能微电网高级应用仿真模型及算法介绍》中已经具体实现的15项功能、最终CHIL以及后续控制算法模块升级。
>
> **唯一设计原则**：
>
> > **旧点位能保留就保留；新增点位只增加真正需要的量；正常100 ms周期尽量只执行一次FC03和一次FC16；运行时配置只有发生变化时才额外读取。**

---

# 1. 先给最终建议

BOARD15 最终把 Modbus Holding Register（保持寄存器）逻辑上分成三个块：

```text
A. Fast Measurement Block
   快速测量块
   40101～40124
   RT-LAB → Board
   每100 ms一次FC03

B. Runtime Config Block
   运行时配置块
   40201～40264
   RT-LAB → Board
   只有CONFIG_SEQ变化时额外FC03读取

C. Command Frame Block
   完整控制命令帧
   40001～40040
   Board → RT-LAB
   每100 ms一次FC16
```

正常运行时：

```text
每100 ms：

FC03 offset=100, quantity=24
读取40101～40124
        ↓
Board计算
        ↓
FC16 offset=0, quantity=40
写40001～40040
```

只有：

```text
CONFIG_SEQ变化
```

时，本周期额外：

```text
FC03 offset=200, quantity=64
读取40201～40264
```

因此正常状态下仍然保持：

> **一次读取 + 一次写入。**

---

# 2. 为什么沿用400xx / 401xx / 402xx三块

现有程序已经稳定使用：

```text
40101～40116
RT-LAB测量 → Board

40001～40012
Board控制 → RT-LAB
```

因此BOARD15不重新换地址体系。

只做：

```text
40001～40012
原地址原语义尽量保留
↓
向后扩展到40040

40101～40116
原地址原语义保留
↓
向后扩展到40124

40201～
新建运行时配置块
```

这样工程开发方可以最大程度复用现有：

```text
decode
encode
FC03
FC16
JSON
状态机
```

程序结构。

---

# 3. A块：Fast Measurement Block
# 40101～40124

## 3.1 原40101～40116全部保留

| 地址 | 名称 | 类型 | 缩放 | 单位 | 说明 |
|---:|---|---|---:|---|---|
| 40101 | `PCC_P` | INT16 | 0.1 | kW | PCC有功；**线上继续沿用旧符号：正=购电，负=外送** |
| 40102 | `PCC_Q` | INT16 | 0.1 | kvar | PCC无功 |
| 40103 | `PCC_V` | UINT16 | 1 | V | PCC线电压有效值 |
| 40104 | `PCC_F` | UINT16 | 0.01 | Hz | PCC频率 |
| 40105 | `PV1_P_MAX` | UINT16 | 0.1 | kW | PV1最大可用有功 |
| 40106 | `PV2_P_MAX` | UINT16 | 0.1 | kW | PV2最大可用有功 |
| 40107 | `ESS1_SOC` | UINT16 | 0.0001 | p.u. | ESS1 SOC |
| 40108 | `ESS2_SOC` | UINT16 | 0.0001 | p.u. | ESS2 SOC |
| 40109 | `PV1_P_MEAS` | INT16 | 0.1 | kW | PV1实测有功 |
| 40110 | `PV2_P_MEAS` | INT16 | 0.1 | kW | PV2实测有功 |
| 40111 | `ESS1_P_MEAS` | INT16 | 0.1 | kW | ESS1实测有功 |
| 40112 | `ESS2_P_MEAS` | INT16 | 0.1 | kW | ESS2实测有功 |
| 40113 | `EV1_P_MEAS` | INT16 | 0.1 | kW | EV1实测有功 |
| 40114 | `EV2_P_MEAS` | INT16 | 0.1 | kW | EV2实测有功 |
| 40115 | `MODEL_STATUS` | UINT16 | 1 | bitfield | 沿用V3.2模型状态字 |
| 40116 | `RTLAB_HEARTBEAT` | UINT16 | 1 | count | RT-LAB心跳；BOARD15阶段建议改为每100 ms新快照递增 |

### 重要：PCC符号不要改通信点表

现有通信历史：

```text
40101：
正 = 从主网购电
负 = 向主网外送
```

当前 LOCAL15 控制算法冻结语义：

```text
PCC > 0 = 微电网向主网外送
PCC < 0 = 微电网从主网进口
```

因此继续采用V4已经验证过的做法：

```text
Modbus decode
↓
I/O Adapter做一次符号转换
↓
ControllerInput.pcc_p_kw

算法内部统一：
正=外送
负=进口
```

不为了BOARD15破坏旧40101点位。

---

## 3.2 新增40117～40124

| 地址 | 名称 | 类型 | 缩放 | 单位 | 作用 |
|---:|---|---|---:|---|---|
| 40117 | `PCC_PHASE` | INT16 | 0.01 | deg | PCC相角，范围建议[-180,180]° |
| 40118 | `GRID_V` | UINT16 | 1 | V | 上级电网侧线电压有效值 |
| 40119 | `GRID_F` | UINT16 | 0.01 | Hz | 上级电网频率 |
| 40120 | `GRID_PHASE` | INT16 | 0.01 | deg | 上级电网相角 |
| 40121 | `PHASE_VALID` | UINT16 | 1 | bool | Grid/PCC相角估计是否有效 |
| 40122 | `EXEC_MODE_STATUS` | UINT16 | 1 | bitfield | RT-LAB最终实际模式执行状态摘要 |
| 40123 | `EXEC_SYSTEM_MODE` | UINT16 | 1 | enum | RT-LAB最终实际系统模式 |
| 40124 | `CONFIG_SEQ` | UINT16 | 1 | count | 当前运行时配置版本号 |

---

# 4. `EXEC_MODE_STATUS` 为什么是必要新增量

S14黑启动和S15并离网/重同步已经不是普通Pref控制。

Board需要知道：

> **RT-LAB最后实际保持在哪一种Breaker / GridOn / Droop状态。**

否则出现：

```text
Board认为已经切换
↓
但RT-LAB最终安全路由没有采用
```

以后，Board恢复通信时就可能从错误状态继续。

因此增加一个16位紧凑状态字，不增加逐设备ACK系统。

推荐位定义：

| bit | 含义 |
|---:|---|
| 0 | `PCC_BREAKER_CLOSED`，1=最终PCC断路器闭合 |
| 1 | PV1 final GridOn |
| 2 | PV2 final GridOn |
| 3 | ESS1 final GridOn |
| 4 | ESS2 final GridOn |
| 5 | EV1 final GridOn |
| 6 | EV2 final GridOn |
| 7 | PV1 final Droop |
| 8 | PV2 final Droop |
| 9 | ESS1 final Droop |
| 10 | ESS2 final Droop |
| 11 | EV1 final Droop |
| 12 | EV2 final Droop |
| 13～14 | final master：0=无，1=ESS1，2=ESS2 |
| 15 | `BOARD15_ROUTE_VALID`：RT-LAB当前最终执行路由是否允许Board控制 |

这样只用：

```text
1个寄存器
```

就足以确认项目最重要的模式执行状态。

---

# 5. 为什么不新增六设备`u_applied`命令回显

不建议把：

```text
六路实际Pref命令回显
```

直接作为Board算法输入。

原因：

1. 项目15策略并不需要逐设备命令ACK才能工作；
2. RT-LAB已经有六路Pmeas，真实物理响应更有价值；
3. 后续执行状态判断本来就需要：
   ```text
   u_commit + Pmeas
   ```
   而不是直接告诉Board执行故障真值；
4. 避免点表和工程逻辑不必要复杂化。

所以：

```text
模式/Breaker执行状态
→ 必要，因此回传

六设备有功实际采用命令
→ 不作为Board真值回传
```

---

# 6. B块：Runtime Config Block
# 40201～40264

## 6.1 为什么单独建立配置块

如果所有参数继续只放：

```text
Board JSON
```

那么每次测试：

```text
改策略
改目标
改阈值
改S15恢复请求
```

都需要：

```text
改JSON
重启Board程序
```

不利于最终项目验证和自动化测试。

因此：

```text
静态启动参数
→ JSON

动态试验/运行参数
→ RT-LAB Runtime Config
```

---

# 7. Runtime Config读取机制

正常每100 ms的Fast Measurement Block只带：

```text
40124 CONFIG_SEQ
```

Board维护：

```text
last_applied_config_seq
```

如果：

```text
CONFIG_SEQ没变化
```

则：

```text
不读取402xx
```

如果：

```text
CONFIG_SEQ变化
```

才额外：

```text
FC03 offset=200
quantity=64
读取40201～40264
```

Board：

```text
读取完整配置
↓
检查40201 CONFIG_SEQ_ECHO
↓
解码
↓
合法性检查
↓
下一100 ms周期边界一次性应用
↓
40025 CONFIG_APPLIED_SEQ = 新seq
```

若配置非法：

```text
保持上一份正式配置
CONFIG_APPLIED_SEQ不变
CONFIG_STATUS = -1
日志打印原因
```

---

# 8. 配置更新时的原子性规则

RT-LAB / Python以后修改配置时必须：

```text
先改所有具体参数
↓
最后修改CONFIG_SEQ
```

例如：

```text
P_OBJECTIVE_MODE
TIE_TARGET
S7_ENABLE
...
先全部更新

最后：
CONFIG_SEQ 12 → 13
```

因此Board看到：

```text
13
```

以后才去读取完整配置块。

这样不用增加：

```text
CONFIG_APPLY脉冲
复杂双缓冲协议
```

一条`CONFIG_SEQ`就够。

---

# 9. 40201～40220：框架和基础AGC配置

| 地址 | 名称 | 类型 | 缩放 | 单位/说明 |
|---:|---|---|---:|---|
| 40201 | `CONFIG_SEQ_ECHO` | UINT16 | 1 | 与40124一致 |
| 40202 | `ALGORITHM_MODE` | UINT16 | 1 | 0=PROJECT15，其它预留 |
| 40203 | `STRATEGY_ENABLE_MASK` | UINT16 | 1 | bit0～14分别S1～S15 |
| 40204 | `P_OBJECTIVE_MODE` | UINT16 | 1 | 0=S7,1=S9,2=S10,3=S12,4=S13 |
| 40205 | `MASTER_ENABLE` | UINT16 | 1 | BOARD15总策略使能 |
| 40206 | `AGC_ENABLE` | UINT16 | 1 | 仲裁型基础AGC使能 |
| 40207 | `MODE_ACTUATION_ENABLE` | UINT16 | 1 | 模式命令真实执行允许 |
| 40208 | `PCC_BREAKER_ACTUATION_ENABLE` | UINT16 | 1 | PCC断路器真实执行允许 |
| 40209 | `BLACKSTART_PREF_SEQUENCE_ENABLE` | UINT16 | 1 | 黑启动Pref阶段门控允许 |
| 40210 | `BLACKSTART_MASTER` | UINT16 | 1 | 1=ESS1，2=ESS2 |
| 40211 | `ISLAND_MASTER` | UINT16 | 1 | 1=ESS1，2=ESS2 |
| 40212 | `RECOVERY_REQUEST` | UINT16 | 1 | S15恢复/重同步请求 |
| 40213 | `Q_SIGN_GAIN` | INT16 | 1 | 当前基线+1，支持±1 |
| 40214 | `P_UNIT_KW` | UINT16 | 0.1 | kW |
| 40215 | `P_DEAD_KW` | UINT16 | 0.1 | kW |
| 40216 | `SOC_MIN` | UINT16 | 0.0001 | p.u. |
| 40217 | `SOC_MAX` | UINT16 | 0.0001 | p.u. |
| 40218 | `TS_AGC_MS` | UINT16 | 1 | ms，项目基线1000 |
| 40219 | `PV_INIT_KW` | INT16 | 0.1 | kW |
| 40220 | `EV_INIT_KW` | UINT16 | 0.1 | kW，内部充电幅值 |

---

# 10. 40221～40248：15策略已有参数

这部分不重新发明新算法参数，只映射当前15策略已经存在的`CFG_AA_*`。

| 地址 | 参数名 | 类型 | 缩放 | 单位 |
|---:|---|---|---:|---|
| 40221 | `DEMAND_WINDOW_S` | UINT16 | 1 | s |
| 40222 | `DEMAND_LIMIT_KW` | INT16 | 0.1 | kW |
| 40223 | `AGC_ERROR_BAND_PCT` | UINT16 | 0.01 | % |
| 40224 | `V_NOM_V` | UINT16 | 1 | V |
| 40225 | `AVC_V_DEADBAND_PU` | UINT16 | 0.0001 | p.u. |
| 40226 | `AVC_Q_LIMIT_KVAR` | UINT16 | 0.1 | kvar |
| 40227 | `ANTI_REVERSE_LIMIT_KW` | INT16 | 0.1 | kW |
| 40228 | `ANTI_REVERSE_DEADBAND_KW` | UINT16 | 0.1 | kW |
| 40229 | `ISLAND_FREQ_DEV_HZ` | UINT16 | 0.01 | Hz |
| 40230 | `ISLAND_V_DEV_PU` | UINT16 | 0.0001 | p.u. |
| 40231 | `SMOOTH_RATE_LIMIT_PCT_PER_MIN` | UINT16 | 0.01 | %/min |
| 40232 | `PV_FLUCT_TRIGGER_PCT` | UINT16 | 0.01 | % |
| 40233 | `TIE_TARGET_KW` | INT16 | 0.1 | kW，算法内部统一正=外送 |
| 40234 | `UV_THRESHOLD_PU` | UINT16 | 0.0001 | p.u. |
| 40235 | `UF_THRESHOLD_HZ` | UINT16 | 0.01 | Hz |
| 40236 | `LOAD_SHED_STEP_KW` | UINT16 | 0.1 | kW |
| 40237 | `PEAK_THRESHOLD_KW` | INT16 | 0.1 | kW |
| 40238 | `VALLEY_THRESHOLD_KW` | INT16 | 0.1 | kW |
| 40239 | `PLAN_INTERVAL_S` | UINT16 | 1 | s |
| 40240 | `EXPORT_LIMIT_KW` | INT16 | 0.1 | kW |
| 40241 | `RENEWABLE_TARGET_PCT` | UINT16 | 0.01 | % |
| 40242 | `BLACKSTART_ENABLE` | UINT16 | 1 | bool |
| 40243 | `SWITCH_ENABLE` | UINT16 | 1 | bool |
| 40244 | `OPT_WEIGHT_COST` | UINT16 | 0.0001 | p.u. |
| 40245 | `OPT_WEIGHT_CARBON` | UINT16 | 0.0001 | p.u. |
| 40246 | `OPT_WEIGHT_RENEWABLE` | UINT16 | 0.0001 | p.u. |
| 40247 | `OPT_WEIGHT_TIE` | UINT16 | 0.0001 | p.u. |
| 40248 | `OPT_WEIGHT_SOC` | UINT16 | 0.0001 | p.u. |

---

# 11. 40249～40256：S15重同步参数

| 地址 | 名称 | 类型 | 缩放 | 单位 |
|---:|---|---|---:|---|
| 40249 | `SYNC_DV_MAX_PU` | UINT16 | 0.0001 | p.u. |
| 40250 | `SYNC_DF_MAX_HZ` | UINT16 | 0.001 | Hz |
| 40251 | `SYNC_DTHETA_MAX_DEG` | UINT16 | 0.01 | deg |
| 40252 | `SYNC_STABLE_MS` | UINT16 | 1 | ms |
| 40253 | `RECLOSE_HOLD_MS` | UINT16 | 1 | ms |
| 40254 | `FREF_KTHETA_HZ_PER_DEG` | UINT16 | 0.0001 | Hz/deg |
| 40255 | `FREF_KDF` | UINT16 | 0.0001 | dimensionless |
| 40256 | `FREF_TRIM_MAX_HZ` | UINT16 | 0.001 | Hz |

当前LOCAL15已验证默认量级：

```text
ΔV ≤ 0.10 pu
Δf ≤ 0.20 Hz
Δθ ≤ 10 deg
stable = 0.50 s
reclose hold = 0.20 s
Ktheta = 0.005 Hz/deg
Kdf = 0.50
trim max = 0.20 Hz
```

具体正式默认值在最终C/工程版本要求里再和冻结模型逐项核对。

---

# 12. 40257～40264：8个扩展配置槽

```text
EXT_CONFIG_01
...
EXT_CONFIG_08
```

类型：

```text
INT16 raw
```

当前PROJECT15默认：

```text
不使用 / 置0
```

存在目的只有一个：

> **以后增加一个新的算法模块时，如果只多几个阈值或时间参数，不需要再次修改整个Modbus寄存器区域。**

不再预留更多，避免过度设计。

---

# 13. C块：Command Frame Block
# 40001～40040

## 13.1 40001～40012全部保留

| 地址 | 名称 | 类型 | 缩放 | 说明 |
|---:|---|---|---:|---|
| 40001 | `PV1_PREF` | INT16 | 0.0001 pu | 保留 |
| 40002 | `PV2_PREF` | INT16 | 0.0001 pu | 保留 |
| 40003 | `ESS1_PREF` | INT16 | 0.0001 pu | 保留 |
| 40004 | `ESS2_PREF` | INT16 | 0.0001 pu | 保留 |
| 40005 | `EV1_PREF` | INT16 | 0.0001 pu | 保留 |
| 40006 | `EV2_PREF` | INT16 | 0.0001 pu | 保留 |
| 40007 | `AGC_STATUS` | INT16 | 1 | 仲裁型基础AGC状态 |
| 40008 | `AGC_DP_KW` | INT16 | 0.1 kW | 当前AGC dP |
| 40009 | `AGC_REMAIN_KW` | UINT16 | 0.1 kW | 未满足调节量 |
| 40010 | `EXT_CONTROL_ENABLE` | UINT16 | 1 | 地址保留；旧名`EXT_AGC_ENABLE`，语义升级为完整Board控制有效 |
| 40011 | `CMD_SEQ` | UINT16 | 1 | 成功发布的新控制命令版本号 |
| 40012 | `BOARD_HEARTBEAT` | UINT16 | 1 | 每100 ms通信循环更新 |

---

# 14. 40013～40018：六路Qref

| 地址 | 名称 | 类型 | 缩放 |
|---:|---|---|---:|
| 40013 | `PV1_QREF` | INT16 | 0.0001 pu |
| 40014 | `PV2_QREF` | INT16 | 0.0001 pu |
| 40015 | `ESS1_QREF` | INT16 | 0.0001 pu |
| 40016 | `ESS2_QREF` | INT16 | 0.0001 pu |
| 40017 | `EV1_QREF` | INT16 | 0.0001 pu |
| 40018 | `EV2_QREF` | INT16 | 0.0001 pu |

这6个量直接服务：

```text
S3 AVC
↓
Q Allocator
↓
六设备Qref
```

所以属于完整15策略闭环的必要新增。

---

# 15. 40019～40024：模式、断路器和重同步

| 地址 | 名称 | 类型 | 缩放 | 含义 |
|---:|---|---|---:|---|
| 40019 | `GRIDON_MASK` | UINT16 | 1 | bits0～5对应PV1、PV2、ESS1、ESS2、EV1、EV2 |
| 40020 | `DROOP_MASK` | UINT16 | 1 | bits0～5对应六设备Droop使能 |
| 40021 | `PCC_BREAKER_REQUEST_CLOSE` | UINT16 | 1 | 0=请求断开，1=请求闭合 |
| 40022 | `FREF_TRIM_HZ` | INT16 | 0.001 | Hz，S15频率参考修正 |
| 40023 | `SYSTEM_MODE` | UINT16 | 1 | 使用当前LOCAL15冻结模式枚举 |
| 40024 | `SELECTED_MASTER` | UINT16 | 1 | 0=无，1=ESS1，2=ESS2 |

### 为什么用mask而不是12个寄存器

六个GridOn：

```text
只需要6个bit
```

六个Droop：

```text
只需要6个bit
```

因此分别用一个UINT16：

```text
40019
40020
```

即可。

这样：

```text
12个离散命令
只占2个寄存器
```

而且现有程序已经使用`MODEL_STATUS` bitfield，工程实现方式并不陌生。

---

# 16. 40025～40029：配置和关键诊断

| 地址 | 名称 | 类型 | 含义 |
|---:|---|---|---|
| 40025 | `CONFIG_APPLIED_SEQ` | UINT16 | Board当前已成功应用的配置版本 |
| 40026 | `CONFIG_STATUS` | INT16 | 0=无新配置，1=新配置已应用，-1=新配置非法/拒绝 |
| 40027 | `ALGORITHM_MODE_STATUS` | UINT16 | Board当前实际运行的算法模式 |
| 40028 | `STRATEGY_ACTIVE_MASK` | UINT16 | bit0～14表示S1～S15当前执行权/活动状态 |
| 40029 | `DOMAIN_VALID_MASK` | UINT16 | bit0=P，bit1=Q，bit2=MODE，bit3=SYNC |

这些量不是为了“显示好看”。

它们直接用于：

```text
确认Board真正用了哪份配置
确认当前哪些策略实际参与控制
确认某个控制域为什么没有动作
```

对最终15策略联合验证非常有用。

---

# 17. 40030～40040：11个扩展诊断槽

```text
EXT_DIAG_01
...
EXT_DIAG_11
```

统一定义：

```text
INT16 raw
```

当前PROJECT15可以选择映射少量真正需要在RT-LAB MAT里同步记录的算法内部量。

大量普通调试信息仍然：

```text
写Board CSV
```

不用全部占Modbus。

为什么预留11个：

> 后续如果增加新的控制算法，可能需要把少量内部状态同步送到RT-LAB记录；预留11个槽已经足够承担“关键诊断”，又不会把正常100 ms FC16块扩大得过分。

---

# 18. 为什么整个Command Frame固定为40个寄存器

最终：

```text
40001～40040
```

全部一次FC16写入。

这样可以保证：

```text
Pref
Qref
Mode
Breaker
Fref
status
```

属于同一个逻辑快照。

避免：

```text
P是新一拍
Q是旧一拍
Breaker又是另一拍
```

造成系统状态混杂。

---

# 19. CMD_SEQ的新精确定义

`CMD_SEQ`不能变成：

```text
100 ms循环计数器
```

它仍然表示：

> **成功发布的新“控制内容版本”。**

即：

```text
如果本周期：
Pref/Qref/GridOn/Droop/Breaker/Fref/SystemMode等
任何真正控制内容发生变化

↓
形成candidate_cmd_seq = current + 1

↓
FC16成功

↓
commit
CMD_SEQ正式+1
```

如果只是：

```text
BOARD_HEARTBEAT变化
CONFIG_STATUS变化
EXT_DIAG变化
```

而真正控制内容没有变化：

```text
CMD_SEQ不增加
```

这保留V4的命令版本语义。

---

# 20. BOARD_HEARTBEAT和CMD_SEQ必须继续分开

```text
BOARD_HEARTBEAT
= 板端程序/通信循环还活着
```

每100 ms更新。

```text
CMD_SEQ
= 控制命令内容真正产生了新版本
```

只有新控制命令成功发布才更新。

因此完全允许：

```text
BOARD_HEARTBEAT：
100
101
102
103
104

CMD_SEQ：
25
25
25
26
26
```

这是正常状态。

---

# 21. 40010为什么保留原地址但升级语义

以前：

```text
40010 EXT_AGC_ENABLE
```

只服务于六路基础AGC Pref。

BOARD15以后真正控制：

```text
P
Q
Mode
Breaker
Fref
```

所以逻辑语义需要升级为：

```text
EXT_CONTROL_ENABLE
```

表示：

> **Board当前整体控制链具备有效资格。**

但地址仍然：

```text
40010
```

避免破坏现有V3.2/V4/V5模型和程序的大量既有连接。

---

# 22. Domain Validity怎么使用，但不让RT-LAB安全逻辑复杂化

Board内部计算：

```text
P_DOMAIN_VALID
Q_DOMAIN_VALID
MODE_DOMAIN_VALID
SYNC_DOMAIN_VALID
```

但不建议RT-LAB根据四个位分别重新实现一套复杂控制器。

Board自己负责：

```text
Q域失效
→ Q保持/安全处理

SYNC域失效
→ sync_timer清零
→ 禁止reclose

P域失效
→ 不更新P闭环
```

`40029 DOMAIN_VALID_MASK`主要用于：

```text
诊断
MAT记录
问题定位
```

而RT-LAB最后一层仍主要看：

```text
40010 EXT_CONTROL_ENABLE
+
BOARD_HEARTBEAT freshness
+
CONTROL_SOURCE
```

决定是否接受Board控制。

这样安全结构不会被点表复杂化。

---

# 23. RT-LAB模型需要的最小改造

## M1. Fast Measurement Pack

把现有：

```text
40101～40116
```

扩展成：

```text
40101～40124
```

新增：

```text
PCC phase
Grid V/f/phase
phase valid
final mode status
config seq
```

---

## M2. RTLAB_HEARTBEAT刷新

当前历史基线：

```text
约1 s递增
```

BOARD15阶段建议：

```text
每100 ms快测量快照递增
```

这样不必额外增加MEAS_SEQ。

---

## M3. Runtime Config Pack

新增：

```text
40201～40264
```

这些量全部来自：

```text
RT-LAB Tunable Parameters
```

方便Variables Table / Python在线修改。

---

## M4. Board Command Decode

把现有：

```text
40001～40012
```

扩展到：

```text
40001～40040
```

完成：

```text
INT16/UINT16
scale
bit mask
enum
```

解码。

---

## M5. BOARD15 Source Router真实启用

当前模型已经预留：

```text
CONTROL_SOURCE = 2
BOARD15
```

后续把这条路真正接通到：

```text
P
Q
GridOn
Droop
Breaker
Fref
```

---

## M6. RT-LAB最后安全层继续保留

RT-LAB仍然独立判断：

```text
40010有效
+
Board heartbeat fresh
+
BOARD15 route enabled
```

才接受新的Board命令。

Board完全掉线：

```text
RT-LAB自己安全保持
```

不依赖Board发送“我掉线了”。

---

## M7. `EXEC_MODE_STATUS / EXEC_SYSTEM_MODE`从最终执行端反馈

40122/40123不能取：

```text
Board原始请求
```

必须取：

```text
RT-LAB最终安全路由以后
真正送向Plant的模式/Breaker状态
```

这样Board读回去才有意义。

---

# 24. 为什么暂时不增加`BOARD_FRAME_ACCEPTED_SEQ`

前一轮曾考虑过增加：

```text
RT-LAB回显Board最后接受的CMD_SEQ
```

本轮按“只做必要设计”重新判断后：

> **暂时不增加。**

因为S14/S15已经可以利用：

```text
40122 EXEC_MODE_STATUS
40123 EXEC_SYSTEM_MODE
+
新的PCC/Grid测量
```

确认模式和Breaker实际状态。

如果后续真正联调证明：

```text
无法可靠判断一帧是否被最终路由接受
```

再只增加一个：

```text
BOARD_FRAME_ACCEPTED_SEQ
```

而不是提前设计复杂ACK体系。

---

# 25. 工程开发方最终程序中的通信结构

正常100 ms主循环只需要：

```text
1. FC03：
offset=100
quantity=24

2. decode

3. 如果CONFIG_SEQ变化：
   FC03 offset=200
   quantity=64
   decode/validate config

4. 调用project15_core

5. encode 40001～40040

6. FC16：
offset=0
quantity=40

7. candidate / commit

8. CSV
```

这依然是一个非常接近现有V4结构的单主循环。

---

# 26. 我方和工程开发方在点表上的分工

## 我方负责

```text
确定：
地址
变量名
物理意义
类型
scale
符号
bit定义
enum定义
算法输入/输出关系
参数合法范围
```

并提供：

```text
project15_core.c/.h
```

---

## 工程开发方负责

在已有程序里：

```text
扩read_points
扩write_points
扩encode/decode
读取config block
实现CONFIG_SEQ逻辑
把ControllerInput传给C算法
把ControllerOutput填到40001～40040
保持V3.2/V4通信安全逻辑
```

不要求其重新设计15策略算法。

---

# 27. 本轮仍需要后续逐项核对的内容

当前地址布局和总体语义已经可以作为拟冻结版本。

但正式交工程开发方以前，还要用：

```text
当前冻结K26_V5模型
+
最终project15_core接口
```

逐项确认：

1. Qref最终允许范围和编码；
2. `SYSTEM_MODE`完整enum；
3. GridOn / Droop六设备bit顺序；
4. `EXEC_MODE_STATUS`实际信号来源；
5. 每个Runtime Config参数的默认值和合法范围；
6. EXT_CONFIG / EXT_DIAG未来第一版实际使用数量；
7. `RTLAB_HEARTBEAT`改为100 ms以后V3.2超时参数同步调整。

这些属于：

```text
实现前核表
```

不是推翻本轮架构。

---

# 28. 本轮完成以后，整个BOARD15骨架已经非常清楚

```text
RT-LAB
Fast Measurement 40101～40124
Runtime Config 40201～40264
        │
        │ FC03
        ▼
BOARD15
100 ms主循环
15策略 + 仲裁
1 s Baseline AGC
P/Q/Mode/Breaker/Fref
        │
        │ FC16
        ▼
40001～40040
        ↓
RT-LAB最终安全路由
        ↓
u_commit
        ↓
Execution Fault
        ↓
u_applied
        ↓
Plant
```

---

# 29. 下一步

完成点表架构以后，下一步不应再增加新的外围机制。

应该进入：

# BOARD15 内部设计05
# Project15 persistent状态逐变量更新 / commit规则审计

目标是把：

```text
原15策略persistent
基础AGC persistent
S6状态
Mode状态
Black Start状态
S15 Recovery状态
```

逐项确定：

```text
谁在新测量到来时更新
谁只有FC16成功后commit
谁在FC03失败时保持
谁在数据失效时清零
谁在重连以后继续
谁在重连以后必须重新证明
```

这一步完成以后，就可以正式冻结：

```text
Project15State
```

并进入C代码转换。
