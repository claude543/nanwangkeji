# K26_V5 LOCAL15｜15种策略最终波形图逐图讲解与工况内化手册

> **目的**：让你以后不依赖我，只看 `S01～S15` 的15张最终PNG，就能自己讲清楚：
>
> 1. 这个策略到底是干什么的；
> 2. 为什么测试时要这样制造工况；
> 3. 哪些参数被设置/修改、为什么取这个值；
> 4. 每幅图的每个子图、每条关键曲线是什么；
> 5. 理论上我们希望看到什么；
> 6. 实际图上出现了什么；
> 7. 根据什么判断测试通过；
> 8. 哪些地方容易看错，哪些结论不能仅凭这张PNG过度宣称。
>
> **适用对象**：当前冻结的 K26_V5 LOCAL15 15策略闭环版本。  
> **总体结论**：S1～S15 已完成最终闭环验收；本手册重点是帮助理解“为什么PASS”，而不是只记住“PASS”两个字。

---

# 0. 看所有波形以前，先背熟这几个统一约定

## 0.1 PCC有功符号

当前冻结约定：

```text
PCC > 0
= 微电网向上级主网外送有功

PCC < 0
= 微电网从主网进口有功
```

因此：

```text
dP > 0
→ 希望PCC往更正方向移动
→ 增加微网净出力 / 减少进口

dP < 0
→ 希望PCC往更负方向移动
→ 增加吸收/充电 / 减少外送
```

这一条对理解 S1、S4、S7、S9、S10、S11、S12、S13 最重要。

---

## 0.2 六设备 Pref 符号

### PV

```text
PV Pref > 0
= 发电
```

PV当前合法范围：

```text
0 ～ +1 pu
```

### ESS

```text
ESS Pref > 0
= 放电

ESS Pref < 0
= 充电
```

范围：

```text
-1 ～ +1 pu
```

### EV

当前EV作为充电负荷：

```text
EV Pref < 0
= 充电

EV Pref = 0
= 停止充电
```

因此：

```text
EV -1 → -0.5
```

不是“负荷增加”，而是：

```text
充电从100%降到50%
→ 释放一部分负荷
```

而：

```text
EV -0.5 → 0
```

表示继续减载。

---

## 0.3 `objective dP` 和 `effective dP`

这是 S1/S4/S11 图里最重要的两条线。

```text
objective dP
=
当前主有功目标本身想让系统调多少

effective dP
=
经过 S1/S4/S11 等硬约束以后
真正允许送给AGC的调节量
```

所以：

```text
objective = effective
```

说明当前没有硬约束改写主目标。

如果两条线分开：

```text
说明硬约束正在真正改变最终控制请求
```

---

## 0.4 `selected source`

当前主P请求的来源编码：

```text
2  = S2
7  = S7
9  = S9
10 = S10
12 = S12
13 = S13
```

因此：

```text
selected source = 12
```

不是“数值12 kW”，而是：

> 当前系统正在听 Strategy 12。

---

## 0.5 Breaker / GridOn / Mode

### PCC Breaker

```text
PCC breaker close = 1
→ PCC闭合，并网

PCC breaker close = 0
→ PCC断开
```

### GridOn

```text
GridOn = 1
→ GFL 跟网

GridOn = 0
→ GFM 构网
```

### executed mode

```text
0 = GRID_CONNECTED_NORMAL
3 = ISLANDED
4 = BLACK_START
5 = RESYNCHRONIZATION
```

当前波形最常见的是这四个。

---

# 1. 先学会一个通用读图方法

以后看到任何一张策略图，不要先盯“最后一幅Pref是不是动了”。

统一按以下顺序看：

```text
第一步：
工况有没有真正制造出来？

第二步：
策略本身有没有识别/产生请求？

第三步：
这个策略有没有真正获得执行权？

第四步：
仲裁/约束后的最终控制请求有没有改变？

第五步：
真实设备命令 Final Pref/Qref/GridOn/Breaker 有没有响应？

第六步：
有没有出现方向相反、错误设备动作、未满足量或不该动作却动作？
```

所以真正的闭环PASS不是：

```text
某一根线动了
```

而是：

```text
工况
↓
策略请求
↓
执行权/仲裁
↓
最终命令
↓
Plant接口动作
```

前后因果一致。

---

# 2. S01 需量控制

对应图：

```text
S01_需量控制.png
```

![S01](LOCAL15_15策略波形_PNG/S01_需量控制.png)

---

## 2.1 S1策略到底要干什么

S1解决的是：

> **微电网不能从主网进口过多，尤其要限制最大需量。**

例如：

```text
最大允许进口 = 50 kW
```

由于当前：

```text
PCC < 0 = 进口
```

因此要求：

```text
PCC >= -50 kW
```

如果主控制器还想进口100 kW：

```text
PCC target = -100 kW
```

S1必须出来“踩刹车”。

---

## 2.2 为什么测试时故意让 S7 和 S1 冲突

S1不是一个独立P主目标。

它是：

```text
硬约束
```

如果正常工况本来就只进口20 kW，而S1上限是50 kW：

```text
根本不会触发
```

那你只能证明：

```text
S1没乱动作
```

不能证明：

```text
S1真能限制过量进口
```

所以专门制造：

```text
S7希望：
PCC ≈ -100 kW

S1要求：
PCC >= -50 kW
```

这两个目标方向明确冲突。

如果S1真的进入闭环，就必须看到：

```text
objective dP
被S1修正
↓
effective dP发生变化
```

---

## 2.3 关键参数怎么设置

本轮核心设计：

```text
CFG15_MASTER_ENABLE = 1
```

LOCAL15总使能。

```text
CFG15_CONTROL_SOURCE = 1
```

真正听LOCAL15。

```text
CFG15_P_OBJECTIVE_MODE = 0
```

主目标使用S7联络线/PCC目标。

```text
CFG15_EXEC_S07 = 1
```

让S7提供基础P主目标。

S1测试前：

```text
CFG15_EXEC_S01 = 0
CFG_AA_demand_limit_kW = 250
CFG_AA_tie_target_kW = -100
```

其中：

```text
-100 kW
```

表示希望进口100 kW。

然后开启：

```text
CFG15_EXEC_S01 = 1
CFG_AA_demand_limit_kW = 50
```

于是产生：

```text
主目标：进口100
硬约束：最多进口50
```

---

## 2.4 为什么 demand limit 选50 kW

不是因为50 kW有什么神奇理论最优性。

而是为了让：

```text
-100 kW目标
vs
-50 kW边界
```

之间有足够大的：

```text
50 kW明确冲突
```

这样波形非常容易辨认。

如果只设：

```text
limit = 95 kW
```

只有5 kW差异，很容易被对象动态和噪声淹没。

---

## 2.5 这张图三个子图分别看什么

### 第一幅：`S1 import relief + S1 active`

蓝线：

```text
S1 import relief
```

表示：

> 从S1原策略角度看，当前进口超限需要纠正多少。

橙色/右轴：

```text
S1 active
```

表示：

> S1硬约束当前是否真正获得执行权。

这两者一定要区分。

原策略可以继续计算relief，即使：

```text
EXEC_S01 = 0
```

所以：

```text
relief非零
≠
S1正在真正控制系统
```

真正要看：

```text
active = 1
```

---

### 第二幅：`objective dP` vs `effective dP`

蓝：

```text
objective dP
```

橙：

```text
effective dP
```

在S1真正激活时，MAT审核显示：

```text
effective dP - objective dP
= +50 kW
```

这是最核心证据。

为什么是：

```text
+50
```

因为S1要：

```text
减少进口
→ PCC往更正方向
→ dP做正向修正
```

---

### 第三幅：六设备 `Final Pref`

这一幅证明：

```text
effective dP并没有停留在算法内部
```

而是进一步进入：

```text
AGC
↓
六设备最终有功指令
```

你会看到六设备中实际有资源承担调节。

不要求六条线都动。

因为：

```text
AGC会根据当前能力和内部资源分配规则决定谁承担
```

---

## 2.6 图上实际什么时候S1真正生效

由于这是人工Variables Table操作，实际MAT记录和最初设计的“约10 s”并不完全一样。

实际：

```text
CFG15_EXEC_S01
约13.923 s：
0 → 1
```

真正约束开始持续有效：

```text
约16.293 s
```

到：

```text
约32.134 s
```

之间可以看到：

```text
S1 active = 1
```

期间：

```text
effective - objective = +50 kW
```

---

## 2.7 为什么第一幅 `active` 看起来会反复开关

因为基础S7一直想把PCC往：

```text
-100 kW
```

推。

S1则在越过进口边界时把它往回推。

于是可能出现：

```text
越限
→ S1激活
→ 被纠正
→ 暂时不越限
→ S1释放
→ S7又继续推
→ 再越限
```

所以你看到的不是一条永远保持1的线，而可能是反复激活。

这不是自动说明控制失稳。

真正要看：

```text
每次active时
effective dP是否按正确方向被修正
```

---

## 2.8 S1怎么判PASS

必须同时满足：

```text
1. S1有持续的非零relief
2. S1 active真实进入1
3. effective dP相对objective dP出现+50 kW方向修正
4. 六设备Final Pref随最终请求发生真实变化
```

本图和MAT均满足。

**S1：PASS。**

---

# 3. S02 PCC跟踪

对应图：

```text
S02_PCC跟踪.png
```

![S02](LOCAL15_15策略波形_PNG/S02_PCC跟踪.png)

---

## 3.1 S2是干什么的

当前老师原S2本质是：

```text
dP = Ptarget - Ppcc
```

也就是：

> PCC有功跟踪误差。

它告诉AGC：

```text
PCC离目标还差多少
```

综合运行时，因为S7也使用相同误差，S2最终更多作为：

```text
PCC tracking / monitoring
```

但我们必须先证明：

> S2自己单独拿到执行权时，也能形成完整P闭环。

---

## 3.2 为什么这一张用的是S2单策略工况

关键设置：

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1
CFG15_P_OBJECTIVE_MODE = 0

CFG15_EXEC_S02 = 1
CFG15_EXEC_S07 = 0
```

为什么要关S7？

因为当前：

```text
S2 dP
=
S7 dP
```

如果S7也开：

```text
即使最后有P动作
你也无法证明到底是不是S2独立完成
```

所以这张S02图故意：

```text
只让S2拿执行权
```

---

## 3.3 第一幅：S2请求和Arbiter请求

两条线：

```text
S2 normalized dP
Arbiter dP
```

几乎完全重合。

实际MAT：

```text
最大误差 = 0
```

这说明：

```text
S2算出的请求
↓
没有被改错
↓
完整进入Arbiter输出
```

---

## 3.4 第二幅：selected source / duplicate guard / monitor-only

最关键：

```text
selected source = 2
```

全程成立。

意思：

> 当前真正执行的P请求源就是S2。

同时：

```text
duplicate guard = 0
S2 monitor-only = 0
```

因为本轮：

```text
S7没有开启
```

所以无需去重复，S2也不是monitor-only。

---

## 3.5 第三幅：六设备 Final Pref

可以看到：

```text
PV
EV
等资源
```

按照AGC分配逐步调整。

这说明：

```text
S2 dP
↓
Arbiter
↓
AGC
↓
Final Pref
```

不是只在策略模块内部转一圈。

---

## 3.6 为什么图上有些设备一直是0

这不等于失败。

AGC本来就不是：

```text
六台设备永远平均分
```

而是根据：

```text
当前可调能力
设备方向
SOC/PV限制
当前内部状态
```

选择资源。

验收S2的核心不是：

```text
六台全都动
```

而是：

```text
S2拥有source=2
Arbiter请求=S2请求
真实六设备链产生对应调节
```

---

## 3.7 S2怎么判PASS

```text
selected source = 2
duplicate guard = 0
monitor-only = 0

Arbiter dP
=
S2 normalized dP

真实Final Pref响应
```

**S2：PASS。**

---

# 4. S03 AVC电压无功控制

对应图：

```text
S03_AVC电压无功控制.png
```

![S03](LOCAL15_15策略波形_PNG/S03_AVC电压无功控制.png)

---

## 4.1 S3是干什么的

S3不是有功策略。

它负责：

> 根据PCC电压偏差产生总无功需求，并把无功分配给六台变流器。

原算法：

```text
V < Vnom
→ qCmd > 0

V > Vnom
→ qCmd < 0
```

实际最终链：

```text
S3 qCmd
↓
Q request
↓
Q Allocator
↓
6×Final Qref
↓
六台逆变器
```

---

## 4.2 关键参数

核心：

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1
CFG15_EXEC_S03 = 1
```

以及：

```text
CFG15_Q_SIGN_GAIN = +1
```

这个 `+1` 很重要。

它表示：

```text
老师原S3 qCmd的正负方向
无需翻转
即可进入当前六逆变器Qref
```

这是经过真实Plant方向测试后冻结的，不是凭经验写死。

原策略默认：

```text
CFG_AA_avc_q_limit_kvar = 120
CFG_AA_avc_v_deadband_pu = 0.02
CFG_AA_v_nom_V = 10000
```

---

## 4.3 关于“电压扰动到底改了多少”的准确边界

当前这份正式MAT/PNG可以确定：

```text
EXEC_S03在约22.669～69.902 s期间真正开启
```

而且存在真实S3 qCmd。

但：

> 当前上传的这份MAT和PNG没有把“当时Variables Table究竟在线修改了哪一个电压输入参数、精确改成多少”作为独立日志保存下来。

所以这部分不能为了讲得完整而虚构一个历史数值。

以后BOARD15标准化复测可以明确固定一个电压偏差，例如：

```text
0.97 pu
```

但那属于后续标准化复测建议，不是这份历史MAT能证明的唯一原始设置。

---

## 4.4 第一幅：原S3请求 → 总Q请求 → Q实际执行

蓝线左轴：

```text
原S3 q request / kvar
```

这是老师原策略一直在算的无功建议。

橙色右轴：

```text
Q total request
Q total applied
```

注意一个重要现象：

```text
0～约22.67 s
原S3 q request已经非零
但Q total request = 0
```

为什么？

因为：

```text
原策略可以一直计算
但EXEC_S03还没开
```

所以它没有真正进入执行层。

约22.67 s以后：

```text
EXEC_S03 = 1
```

于是：

```text
Q total request开始非零
```

并且：

```text
Q total applied
与
Q total request
重合
```

到约69.90 s后S3退出，Q执行又回0。

---

## 4.5 第二幅：Q capability / allocator / selected source / saturated

蓝线：

```text
Q capacity
```

表示六设备当前剩余无功总能力。

为什么它会慢慢下降？

因为Q能力不是固定：

```text
Qcap_i = sqrt(1 - Pref_i²)
```

随着设备有功Pref逐步占用更多视在容量：

```text
剩余Q空间减少
```

所以总Q能力会变化。

同时：

```text
allocator valid = 1
```

说明Q分配器工作正常。

S3执行期间：

```text
selected source = 3
```

表示：

> 当前Qref确实来自策略3。

而：

```text
saturated = 0
```

说明：

```text
S3要求的Q
没有超过六设备总剩余Q能力
```

---

## 4.6 第三幅：六设备 Final Qref

执行S3期间六台设备都出现非零Qref。

而且它们幅值不同。

这恰恰是正确的。

因为我们没有：

```text
Q/6平均分
```

而是：

```text
剩余视在容量多
→ 多承担Q

剩余能力少
→ 少承担Q
```

---

## 4.7 S3怎么判PASS

MAT审核：

```text
Q total applied
-
Q total request
最大误差 = 0

Q saturated = 0

Q allocator valid = 1

selected source = 3
```

且：

```text
六设备Final Qref真实非零
```

**S3：PASS。**

---

# 5. S04 防逆流

对应图：

```text
S04_防逆流.png
```

![S04](LOCAL15_15策略波形_PNG/S04_防逆流.png)

---

## 5.1 S4要干什么

S4用于：

> 防止微电网向主网反向外送，或者限制允许外送的上界。

本次测试取：

```text
anti_reverse_limit = 0 kW
```

即：

```text
PCC <= 0
```

意思：

> 不允许稳定向主网外送有功。

---

## 5.2 为什么一定先让S7制造外送

如果PCC本来就是：

```text
-100 kW进口
```

S4当然不会触发。

所以先：

```text
CFG_AA_tie_target_kW = +100
```

让S7主动把系统推向：

```text
+100 kW外送
```

然后再打开：

```text
CFG15_EXEC_S04 = 1
CFG_AA_anti_reverse_limit_kW = 0
CFG_AA_anti_reverse_deadband_kW = 2
```

形成：

```text
S7：
想+100

S4：
最多约0
```

这是明确硬冲突。

---

## 5.3 为什么deadband设2 kW

死区作用：

```text
在边界附近避免因为极小噪声
不断触发/释放
```

当前老师原策略就保留：

```text
2 kW
```

所以防逆流实际纠偏量接近：

```text
100 - 0 - 2
= 98 kW
```

这正好对应MAT：

```text
effective - objective = -98 kW
```

---

## 5.4 第一幅怎么看

蓝：

```text
S4 export relief
```

表示原策略认为当前出口超限多少。

橙：

```text
S4 active
```

才表示真正硬约束进入执行层。

本图必须特别注意：

> `S4 export relief` 在S4未获得执行权时也可能非零，因为老师原策略仍然一直计算。

所以不要看到40～60 s附近蓝线非零就说：

```text
S4已经开始真实控制
```

真正以：

```text
S4 active = 1
```

为准。

实际正式active区间约：

```text
58.046 ～ 96.929 s
```

---

## 5.5 第二幅：为什么两条dP差了98 kW

S4激活时：

```text
effective dP
=
objective dP - 98 kW
```

方向是负。

因为：

```text
当前出口过大
↓
要让PCC往更负方向
↓
减少外送
↓
负向修正
```

这就是S4最直接的闭环证据。

---

## 5.6 第三幅：Final Pref

最终AGC根据新的effective dP重新调六设备。

不要求：

```text
某一台指定设备必须固定动多少
```

要看：

```text
最终真实Pref确实随着硬约束修正变化
```

---

## 5.7 为什么S4 active也会反复跳

因为：

```text
S7持续想+100
S4持续限制≤0
```

于是：

```text
S4压回
→ 暂时不过限
→ S4释放
→ S7继续推
→ 再越限
```

所以边界附近会反复触发。

真正判断的是：

```text
每次active时
修正方向必须永远是抑制外送
```

---

## 5.8 S4怎么判PASS

```text
S4有持续relief
S4 active真实置1
effective-objective = -98 kW
六设备Final Pref随之改变
```

**S4：PASS。**

---

# 6. S05 防孤岛

对应图：

```text
S05_防孤岛_正向与通信负向边界.png
```

![S05](LOCAL15_15策略波形_PNG/S05_防孤岛_正向与通信负向边界.png)

这张图不是一份MAT。

而是把：

```text
正向电气异常测试
+
负向communication-only测试
```

两份MAT拼成一张。

这一点非常重要。

---

## 6.1 S5到底要干什么

最终LOCAL15中的S5职责不是：

```text
任何异常都直接打开PCC
```

而是：

> **识别真实电气孤岛风险，为S15提供物理解列资格。**

当前特别做了：

```text
通信异常
≠
电气孤岛
```

即：

```text
comm_bad可以报警
但不能单独打开PCC
```

---

## 6.2 正向工况关键设置

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S05 = 1
CFG15_EXEC_S15 = 1

CFG15_MODE_ACTUATION_ENABLE = 1
CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1

CFG15_ISLAND_MASTER = 1
```

即：

```text
ESS1作为孤岛GFM主机
```

然后制造电气异常：

```text
CFG_AA_v_nom_V
10000 → 20000
```

---

## 6.3 为什么改Vn而不是直接把10kV电网砸低

真实电压仍约：

```text
V ≈ 10000 V
```

策略看到：

```text
Vpu = V/Vn
≈ 10000/20000
≈ 0.5
```

而S5默认：

```text
允许偏差 = 0.10
```

所以：

```text
|0.5-1| = 0.5 > 0.10
```

一定形成：

```text
electrical_bad = 1
```

这样做的目的：

> 隔离验证“策略判断 → S5执行资格 → S15 → Breaker → ESS GFM”这一条执行链。

它不是：

```text
真实低电压故障试验
```

所以对外一定要称：

```text
策略判据注入
```

---

## 6.4 左上图：正向电气异常

三条线：

```text
electrical bad
S5 execute
S15 transition
```

在：

```text
约27.606 s
```

几乎同时：

```text
0 → 1
```

这说明：

```text
电气异常
↓
S5真实执行资格
↓
S15离网请求
```

完整贯通。

---

## 6.5 右上图：Mode / Breaker / island latch

约27.606 s：

```text
executed mode:
0 → 3
```

即：

```text
NORMAL → ISLANDED
```

同时：

```text
island latch:
0 → 1
```

PCC：

```text
breaker close → 0
```

即真正打开。

### 为什么前15 s左右PCC线有方波

这个非常容易看不懂。

在新Breaker接管完全生效前：

```text
Final Breaker
仍透传Legacy Pulse Generator
```

所以图前段会看到旧Pulse Generator的方波。

这不是S5在反复跳闸。

真正要看的是：

```text
新执行链正式接管且无异常时
PCC应稳定close=1

27.606 s电气异常后
PCC被LOCAL15拉成0并保持
```

---

## 6.6 负向工况为什么必须做

如果只证明：

```text
电气异常会跳PCC
```

还不够。

因为老师原S5中：

```text
通信异常也会让raw alarm/cmd=1
```

我们新增执行资格的核心改进就是：

```text
纯通信异常不能物理解列
```

所以必须专门测一次：

```text
通信坏
V/f正常
执行权限仍然打开
```

这才真正有安全证明力。

---

## 6.7 左下图：Communication-only

约：

```text
30.965 ～ 43.211 s
```

看到：

```text
comm bad = 1
```

但是：

```text
electrical bad = 0
```

这正是我们想制造的工况。

---

## 6.8 右下图：为什么这是最关键的安全证据

在communication-only区间：

```text
S5 execute = 0
S15 transition = 0
island latch = 0
```

PCC：

```text
保持闭合
```

即：

```text
通信异常
↓
可以被记录
但
↓
不具备物理解列资格
```

---

## 6.9 通信异常具体参数的准确边界

本次正式证据能确定：

```text
原策略comm输入被压到 < 0.5
```

形成：

```text
comm_bad=1
```

当前模型顶层存在通信健康测试入口。

但这张PNG/MAT并没有把“人工在线操作的通信量参数名称和改动数值”作为独立诊断行记录，所以不要为了复述而伪造一个不存在于证据中的精确操作名。

以后标准化复测只需保证：

```text
comm < 0.5
且
V/f保持正常
```

即可复现负向边界。

---

## 6.10 S5怎么判PASS

正向：

```text
electrical bad
→ S5 execute
→ S15 transition
→ mode3
→ island latch
→ PCC OPEN
```

负向：

```text
comm bad=1
electrical bad=0
→ S5 execute=0
→ S15 transition=0
→ latch=0
→ PCC不误跳
```

正负两边都成立。

**S5：PASS。**

---

# 7. S06 PV功率平滑

对应图：

```text
S06_PV功率平滑.png
```

![S06](LOCAL15_15策略波形_PNG/S06_PV功率平滑.png)

---

## 7.1 S6到底要干什么

S6处理：

> PV最大可用功率变化太快时，用ESS反向补偿，使组合功率变化更平缓。

注意：

> 当前模型S6实际读取的是 `Ppv_max1 / Ppv_max2`，不是PV电气 `Pmeas`。

---

## 7.2 为什么最开始改PCC target没用

PCC target改变：

```text
会让AGC重新调度
```

但并不一定改变：

```text
S6真正读取的Ppv_max曲线
```

所以早期测试出现：

```text
PCC在变
但S6 active=0
```

后来追线确认：

```text
S6输入来自PV_Profile_Curve
```

所以正确测试必须直接改：

```text
PV_profile_pu(6)
```

---

## 7.3 参数怎么改

默认：

```text
PV_profile_pu(6) = 0.65
P_unit = 100 kW
```

所以：

```text
PV1 max = 65 kW
PV2 max = 65 kW
总PVmax = 130 kW
```

实际测试：

```text
约42.671 s：
0.65 → 0.95
```

于是：

```text
每台65 →95 kW
总PV 130→190 kW
```

然后：

```text
约61.058 s：
0.95 → 0.55
```

总PV：

```text
190 →110 kW
```

最后：

```text
约92.034 s：
0.55 →0.65
```

恢复。

原策略爬坡参数默认：

```text
CFG_AA_smooth_rate_limit_pct_per_min = 15
```

---

## 7.4 第一幅为什么 `smooth ref` 比 PV1/PV2 高很多

图中：

```text
PV1 input
PV2 input
```

每一条是：

```text
单台PV可用功率
```

而：

```text
smooth ref
```

是：

```text
两台PV总可用功率的平滑参考
```

所以它大约在：

```text
110～200 kW
```

而单台PV只有：

```text
55～100 kW
```

这不是量纲错误。

---

## 7.5 PV上升时为什么补偿是负值

42.67 s：

```text
PV总可用：
130 →190
```

平滑参考不能瞬间跟上。

于是：

```text
smooth_ref < pv_now
```

所以：

```text
compensation
=
smooth_ref - pv_now
< 0
```

ESS：

```text
负Pref = 充电
```

所以：

```text
PV突然上升
→ ESS增加充电
→ 把多出来的变化吸收掉
```

图中补偿最低：

```text
约 -0.600 pu
```

---

## 7.6 PV下降时为什么补偿变正

61.06 s：

```text
PV：
190 →110 kW
```

此时smooth_ref还没来得及降下来：

```text
smooth_ref > pv_now
```

于是：

```text
compensation > 0
```

ESS：

```text
正Pref = 放电
```

所以：

```text
PV突然下降
→ ESS放电补上
```

最大约：

```text
+0.292 pu
```

---

## 7.7 第二幅怎么看

```text
comp request
comp applied
```

两条几乎完全重合。

这说明：

```text
请求多少补偿
执行器就实际完成多少
```

而：

```text
unserved = 0
```

说明两台ESS当前余量足够，没有未满足补偿。

`S6 active`：

```text
约42.67 s →1
约99.02 s →0
```

---

## 7.8 第三幅为什么ESS1和ESS2几乎重合

两台ESS在这个测试里可用方向余量近似相同。

所以余量比例分配结果接近：

```text
50% / 50%
```

因此两条Final Pref几乎重合。

这不是固定写死平均分。

如果两台ESS初始状态/余量不同：

```text
分配比例会改变
```

---

## 7.9 S6怎么判PASS

```text
PV上升
→ compensation<0
→ ESS充电

PV下降
→ compensation>0
→ ESS放电

request = applied
unserved = 0
```

方向和执行量全部正确。

**S6：PASS。**

---

# 8. S07 联络线有功控制

对应图：

```text
S07_联络线功率控制.png
```

![S07](LOCAL15_15策略波形_PNG/S07_联络线功率控制.png)

---

## 8.1 S7是干什么的

S7是当前综合运行中的：

> **正常PCC/联络线有功主控制请求源。**

核心：

```text
dP = Ptarget - Ppcc
```

然后AGC负责分配给六台资源。

---

## 8.2 为什么这张图故意同时开启S2

测试：

```text
CFG15_EXEC_S02 = 1
CFG15_EXEC_S07 = 1
CFG15_P_OBJECTIVE_MODE = 0
```

因为当前：

```text
S2 dP = S7 dP
```

真正需要验证的是：

> 综合运行时不能把相同的误差执行两次。

所以这张S7图实际上同时验收：

```text
S7主执行
+
S2去重复/monitor-only
```

---

## 8.3 第一幅：三条线为什么完全重合

```text
S2 dP
S7 dP
Arbiter dP
```

几乎完全重合。

这说明：

```text
S2 = S7
```

但Arbiter没有做：

```text
S2+S7
```

如果错误相加：

```text
Arbiter线应该约等于两倍
```

实际没有。

---

## 8.4 第二幅是这张图最重要的一幅

全程：

```text
selected source = 7
```

同时：

```text
duplicate guard = 1
S2 monitor-only = 1
```

由于：

```text
selected source=7
```

画在y=7。

而：

```text
duplicate guard
monitor-only
```

都等于1，两条线在y=1附近完全重合，所以视觉上可能像只有一条。

这恰恰表示：

```text
S7获得唯一执行权
S2被降为监测
```

---

## 8.5 第三幅：Final Pref

S7请求进入：

```text
AGC
```

以后六设备按照资源分配规则调整。

这证明：

```text
S7
↓
AGC
↓
Plant Pref
```

完整成立。

---

## 8.6 S7怎么判PASS

```text
S2 dP = S7 dP
selected source = 7
duplicate guard = 1
S2 monitor-only = 1
Arbiter dP = S7 dP
真实Final Pref变化
```

**S7：PASS。**

---

# 9. S08 低压/低频分级减载

对应图：

```text
S08_UVUF分级减载.png
```

![S08](LOCAL15_15策略波形_PNG/S08_UVUF分级减载.png)

---

## 9.1 S8要干什么

当发生：

```text
低电压
或
低频
```

时，系统要迅速减少可控负荷。

当前平台不额外切固定Load1/Load2。

而是利用：

```text
EV1 / EV2
```

作为柔性充电负荷。

---

## 9.2 分级逻辑

默认：

```text
CFG_AA_load_shed_step_kW = 50
```

所以：

```text
Stage0
→ 0 kW减载

Stage1
→ 50 kW

Stage2
→ 100 kW
```

优先顺序：

```text
EV2
→ EV1
```

---

## 9.3 为什么还是改阈值，不直接制造真实低压/低频

正常：

```text
Vpu≈1
f≈50
```

默认：

```text
UV threshold = 0.88
UF threshold = 49
```

不会触发。

### 一级

改：

```text
CFG_AA_uv_threshold_pu
0.88 → 1.10
```

因为：

```text
1.0 < 1.10
```

于是低压判据确定成立。

### 二级

再改：

```text
CFG_AA_uf_threshold_Hz
49 → 51
```

因为：

```text
50 < 51
```

低频也成立。

于是：

```text
低压 + 低频
→ Stage2
```

这样只验证：

```text
策略判据
→ Stage
→ EV真实减载
```

而不同时引入真实大电网事故动态。

---

## 9.4 第一幅：Stage 和 cmd shed

实际：

```text
93.7625 s：
Stage 0 → 1
cmd 0 → 50 kW

109.6813 s：
Stage 1 → 2
cmd 50 → 100 kW

131.7571 s：
Stage 2 → 1
cmd 100 → 50

139.4271 s：
Stage 1 → 0
cmd 50 → 0
```

这正好形成：

```text
0 → 1 → 2 → 1 → 0
```

---

## 9.5 第二幅：request / applied / unserved

非常关键：

```text
shed request
=
shed applied
```

全程：

```text
unserved = 0
```

说明：

> 请求的减载量全部由当前EV可调能力实际完成。

---

## 9.6 第三幅：为什么EV2动、EV1几乎不动

Stage1：

```text
EV2：
-1 → -0.5
```

即：

```text
减少50 kW充电
```

EV1仍保持：

```text
-1
```

Stage2：

```text
EV2：
-0.5 → 0
```

又释放50 kW。

所以总共：

```text
100 kW
```

此时EV2本身就有足够的100 kW可释放能力。

因此：

```text
EV1不需要动
```

这仍然正确证明了：

```text
EV2优先
```

如果请求超过EV2当时可释放量，执行器才会继续分给EV1。

---

## 9.7 S8怎么判PASS

```text
Stage严格0→1→2→1→0
cmd = 0/50/100/50/0
request = applied
unserved = 0
EV2按优先级向0移动
恢复后EV重新回充电状态
```

**S8：PASS。**

---

# 10. S09 削峰填谷

对应图：

```text
S09_削峰填谷.png
```

![S09](LOCAL15_15策略波形_PNG/S09_削峰填谷.png)

---

## 10.1 S9要干什么

当前S9是一个实时阈值型削峰填谷策略。

思路：

```text
进口过高（峰）
→ dP > 0
→ 减少进口

进口过低（谷）
→ dP < 0
→ 增加ESS/EV充电吸收
```

原默认阈值：

```text
CFG_AA_peak_threshold_kW = 220
CFG_AA_valley_threshold_kW = 80
```

---

## 10.2 关键执行设置

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S09 = 1
CFG15_P_OBJECTIVE_MODE = 1
```

并尽量关闭：

```text
S1/S4/S11硬约束
```

避免effective dP被其它策略改写。

---

## 10.3 这张图有一个最大的“阅读陷阱”

这张S09图使用的是联合MAT：

```text
S09_S12_S13_削峰填谷_新能源消纳_多目标模式切换_PASS.mat
```

同一Execute里依次测试：

```text
S9
→ S12
→ S13
```

实际source变化：

```text
0 ～约25.643 s：
source = 9

25.643 ～64.526 s：
source = 12

64.526 s以后：
source = 13
```

所以：

> **验收S9只看最前面的 source=9 区间。**

---

## 10.4 为什么上面S9 raw request在70s后又变成+180左右

因为：

```text
原S9策略一直在后台计算自己的cmd
```

即使：

```text
P_OBJECTIVE_MODE已经切到S13
```

S9 raw request仍可能变化。

但是：

```text
source=13
```

意味着：

> 70s后的S9 request根本没有进入最终执行链。

所以千万不要说：

```text
“S9后来输出+180，所以系统按+180执行”
```

这是错的。

---

## 10.5 S9真正的验收区间怎么看

0～25.643 s：

```text
selected source = 9
```

S9 dP：

```text
约 -80 ～ 0 kW
```

同时：

```text
objective dP
=
effective dP
=
S9 normalized dP
```

最大误差0。

这说明：

```text
S9有非零请求
↓
P Manager选择S9
↓
没有硬约束改写
↓
完整送AGC
```

---

## 10.6 第三幅Final Pref怎么看

S9前段产生的负dP意味着：

```text
希望增加吸收/充电
```

所以可以看到：

```text
EV等吸收侧资源往更负方向调
```

具体由AGC分配。

---

## 10.7 S9怎么判PASS

只看：

```text
source=9
```

的区间：

```text
S9 request非零
objective dP = S9 dP
effective dP = objective dP
Final Pref有对应真实响应
```

**S9：PASS。**

> 当前证明的是实时阈值型削峰填谷闭环，不等同于已经实现完整分时电价/日前经济优化。

---

# 11. S10 周期计划

对应图：

```text
S10_周期计划.png
```

![S10](LOCAL15_15策略波形_PNG/S10_周期计划.png)

---

## 11.1 S10到底是什么

S10和S7最大的不同：

```text
S7输出的是“当前还差多少dP”

S10输出的是“当前PCC计划目标是多少”
```

因此S10必须先做：

```text
S10 target - 当前PCC
↓
变成dP
```

再交AGC。

---

## 11.2 关键参数

```text
CFG15_EXEC_S10 = 1
CFG15_P_OBJECTIVE_MODE = 2
```

原计划周期：

```text
CFG_AA_plan_interval_s = 900
```

当前老师原S10使用的是：

```text
合成周期目标
```

不是实际24小时96点调度表。

---

## 11.3 第一幅为什么target只从-100缓慢变到-99.88

图的Y轴被放得非常窄：

```text
-100 ～ -99.88
```

所以看起来斜率明显。

实际上总变化只有约：

```text
0.12 kW
```

说明当前测试中老师原有合成周期计划目标在缓慢变化。

这张图主要要证明：

> 这个计划目标确实进入真实P控制链。

不是要证明一天的完整96点计划。

---

## 11.4 第二幅最关键

全程：

```text
selected source = 10
```

即：

> 当前P主目标确实来自S10。

同时：

```text
objective dP
和
effective dP
基本重合
```

说明本轮主要由S10目标控制，没有被硬约束显著改写。

---

## 11.5 为什么这个MAT文件名里还有S1/S4/S11

证据MAT叫：

```text
S01_S04_S10_S11_周期计划与有功硬约束联合验证_PASS.mat
```

历史上确实同时开过这些约束。

但第一次冻结审计发现：

```text
这份MAT并没有充分激励S1/S4/S11
```

所以：

> **这张S10图只能用于验收S10。**

S1/S4/S11最终PASS依赖后来专门的硬约束专项MAT。

这也是为什么我们不能“看到文件名写了S1/S4/S11就说它们都通过”。

---

## 11.6 第三幅：Final Pref

计划目标产生的dP进入AGC后：

```text
PV/EV/ESS
```

按资源能力逐步调整。

证明：

```text
S10 target
↓
P Manager
↓
AGC
↓
Final Pref
```

完整。

---

## 11.7 S10怎么判PASS

```text
P_OBJECTIVE_MODE=2
selected source=10全程
S10 target真实存在
objective/effective dP有效
Final Pref真实响应
```

**S10：PASS。**

---

# 12. S11 自发自用 / 余电外送

对应图：

```text
S11_自发自用余电外送.png
```

![S11](LOCAL15_15策略波形_PNG/S11_自发自用余电外送.png)

---

## 12.1 S11和S4到底有什么不同

S4：

```text
防逆流
```

典型可以要求：

```text
PCC <= 0
```

即不允许外送。

S11：

```text
自发自用 / 余电允许上网
```

可以规定：

```text
允许外送
但最多只能外送50 kW
```

即：

```text
PCC <= +50 kW
```

---

## 12.2 为什么工况用 `+100` 对 `+50`

先让S7：

```text
tie target = +100 kW
```

系统想外送100。

再打开S11：

```text
CFG15_EXEC_S11 = 1
CFG_AA_export_limit_kW = 50
```

于是：

```text
主目标：+100
政策上限：+50
```

差值正好：

```text
50 kW
```

非常清楚。

---

## 12.3 第一幅的raw relief为什么很早就有

和S4相同：

```text
S11 raw策略一直计算
```

所以即使：

```text
EXEC_S11 = 0
```

只要它认为当前有外送超限：

```text
export relief
```

仍可能非零。

真正要看：

```text
S11 active
```

正式MAT：

```text
约113.419 s以后
S11 active开始真实置1
```

---

## 12.4 第二幅：最关键的50 kW差值

S11激活时：

```text
effective dP - objective dP
= -50 kW
```

为什么负？

因为：

```text
原目标外送+100
但最多允许+50
↓
必须减少50 kW外送
↓
PCC往负方向
↓
dP负向修正50
```

---

## 12.5 第一幅为什么active也像脉冲

基础S7一直：

```text
想推+100
```

S11一直：

```text
限制+50
```

于是控制在边界附近反复：

```text
超限→激活→纠正→释放→再超限
```

看图时不要只要求：

```text
active必须一直=1
```

而要看：

```text
active=1时修正方向和幅值是否正确
```

---

## 12.6 S11怎么判PASS

```text
S11 relief持续非零
S11 active真实进入1
effective-objective = -50 kW
真实Final Pref改变
```

**S11：PASS。**

---

# 13. S12 新能源最大化消纳

对应图：

```text
S12_新能源最大化消纳.png
```

![S12](LOCAL15_15策略波形_PNG/S12_新能源最大化消纳.png)

---

## 13.1 S12到底要干什么

当：

```text
PV可用新能源很多
但当前内部吸收不足
```

S12希望：

```text
ESS/EV多充电
减少向外送
减少潜在弃光
```

当前PCC符号下：

```text
增加吸收
→ PCC更负
→ dP < 0
```

所以老师原S12的正“可吸收量”经过Normalizer以后变成：

```text
负dP
```

---

## 13.2 为什么专门重新做了一个S12非零补测

旧联合MAT：

```text
source = 12
```

没问题。

但是：

```text
S12 dP = 0
```

只能证明：

```text
路由选中了S12
```

不能证明：

```text
S12真的改变了设备
```

所以必须构造：

```text
富余新能源 + 吸纳不足
```

让S12产生非零请求。

---

## 13.3 关键执行参数

可以明确确认：

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S12 = 1
CFG15_P_OBJECTIVE_MODE = 3
```

原策略新能源目标默认：

```text
CFG_AA_renewable_target_pct = 95
```

本轮通过提高可再生能源可用出力、形成内部吸纳需求制造非零S12请求。

### 精确输入扰动值的边界

当前正式PNG/MAT可以证明：

```text
S12请求最低约 -105 kW
```

但是没有把“当时在线具体把PV_profile哪一个值改成多少”作为独立记录保存。

所以这份讲解不编造一个历史精确PV数值。

真正冻结的验收事实是：

```text
S12执行许可=1
P_OBJECTIVE_MODE=3
source=12
出现非零 -105 kW请求
```

---

## 13.4 第一幅：S12 dP

开始阶段出现：

```text
约 -105 kW
```

然后逐渐靠近0。

物理意义：

```text
开始时可再生富余/吸纳缺口最大
↓
系统逐步增加吸收
↓
剩余需要吸收的量减少
↓
S12 dP逐渐趋近0
```

所以：

```text
从-105往0走
```

不是策略失效。

恰恰是闭环需求逐渐被满足的表现。

---

## 13.5 第二幅：source=12

全程：

```text
selected source = 12
```

同时：

```text
objective dP
=
effective dP
=
S12 dP
```

几乎完全重合。

这说明：

```text
S12成为唯一主P目标
且没有其它硬约束偷偷改写
```

---

## 13.6 第三幅：为什么主要看到EV变得更负

当前这份补测中：

```text
PV/ESS部分Final Pref接近0
EV原来约 -0.6
```

随后EV进一步：

```text
变得更负
```

例如约：

```text
-0.60 → -0.64
```

这表示：

```text
EV增加充电
```

正好符合：

```text
新能源富余
→ 增加内部负荷吸收
```

的目标。

---

## 13.7 S12怎么判PASS

```text
S12 dP真实非零
最低约 -105 kW

source = 12

objective dP = S12 dP
effective dP = objective dP

Final Pref出现增加吸收方向的真实变化
```

**S12：PASS。**

---

# 14. S13 多目标协调

对应图：

```text
S13_多目标协调.png
```

![S13](LOCAL15_15策略波形_PNG/S13_多目标协调.png)

---

## 14.1 S13是干什么的

当前老师原S13把：

```text
成本
碳
新能源
联络线
SOC
```

等多个因素按权重形成一个带方向的综合P请求。

默认权重：

```text
cost       = 0.30
carbon     = 0.20
renewable  = 0.20
tie        = 0.20
soc        = 0.10
```

最终LOCAL15没有重新发明MPC/QP/PSO。

而是：

> 把老师当前已经存在的S13 cmd真实接进P主链。

---

## 14.2 关键设置

```text
CFG15_EXEC_S13 = 1
CFG15_P_OBJECTIVE_MODE = 4
```

其它主P目标在S13正式区间不拥有执行权。

---

## 14.3 这张图同样来自S9/S12/S13联合MAT

所以只看：

```text
64.526 s以后
```

因为：

```text
0～25.643：
source=9

25.643～64.526：
source=12

64.526以后：
source=13
```

---

## 14.4 第一幅：S13 raw request

S13原始请求在整个MAT中一直计算。

但只有：

```text
source=13
```

之后才是真正执行。

正式S13区间：

```text
请求约 -33 ～ -175.6 kW
```

并逐渐变得更负。

---

## 14.5 第二幅：为什么64.5 s以后才验收

64.526 s：

```text
selected source
12 → 13
```

从这一刻开始：

```text
objective dP
=
S13 dP
```

而：

```text
effective dP
≈ objective dP
```

说明没有其它硬约束改变它。

---

## 14.6 第三幅：Final Pref为什么大幅向充电/吸收方向走

S13请求为负：

```text
dP < 0
```

因此系统需要：

```text
增加吸收 / 降低净输出
```

图上可以看到：

```text
EV趋向-1
ESS也可能进入负Pref
```

表示：

```text
增加充电吸收
```

方向和S13请求一致。

---

## 14.7 S13怎么判PASS

正式区间：

```text
source=13
S13请求非零
objective dP = S13 dP
Final Pref按负dP方向真实动作
```

**S13：PASS。**

### 不能过度宣称什么

这张图证明：

```text
“当前老师已有多目标cmd能够真实闭环执行”
```

不证明：

```text
“这个多目标算法已经是严格全局最优”
```

也不应把它写成：

```text
MPC / QP / PSO
```

---

# 15. S14 黑启动

对应图：

```text
S14_黑启动四阶段真实执行.png
```

![S14](LOCAL15_15策略波形_PNG/S14_黑启动四阶段真实执行.png)

---

## 15.1 S14要解决什么

黑启动是：

> 主网不可用/系统失电后，由ESS先建立岛内电压频率，再逐步恢复其它资源和非关键负荷。

当前模型没有独立DeviceEnable。

所以S14当前实现的“逐设备投入”准确含义是：

```text
PCC解列
+
ESS GFM
+
Pref Gate分阶段释放
```

不是：

```text
真实接触器逐台闭合
```

---

## 15.2 关键参数

```text
CFG15_MASTER_ENABLE = 1
CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S14 = 1
CFG_AA_blackstart_enable = 1

CFG15_MODE_ACTUATION_ENABLE = 1
CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1

CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE = 1
CFG15_BLACKSTART_MASTER = 1
```

即：

```text
ESS1为黑启动构网主机
```

---

## 15.3 为什么Breaker和GFM权限必须同时开

如果：

```text
只开Breaker
```

PCC断开以后没有构网电压源。

如果：

```text
只开GFM
```

ESS1会在PCC仍接强网时变成电压源。

都不合理。

所以黑启动真实测试必须：

```text
Breaker接管
+
Device Mode接管
```

成套开启。

---

## 15.4 第一幅：Stage 1→2→3→4

原老师S14当前按仿真绝对时间推进。

正式主体MAT：

```text
约20.004 s：
Stage1 → Stage2

约40.005 s：
Stage2 → Stage3

约60.006 s：
Stage3 → Stage4
```

`sequence active=1`：

说明：

```text
Black Start Pref Gate正在真实工作
```

---

## 15.5 第二幅：系统模式 / PCC / black-start latch

全程：

```text
executed mode = 4
```

即：

```text
BLACK_START
```

同时：

```text
PCC breaker close = 0
```

即PCC真正解列。

`blackstart latch=1`：

表示：

```text
黑启动执行状态已经被锁存
```

---

## 15.6 第三幅：ESS1构网

图中：

```text
ESS1 GridOn = 0
```

代表：

```text
ESS1 = GFM
```

而：

```text
ESS1 Droop = 1
```

说明Droop投入。

因此：

```text
PCC OPEN
+
ESS1 GFM
```

黑启动的基本构网条件真实成立。

---

## 15.7 第四幅：六设备Pref Gate

理论冻结逻辑：

```text
Stage1：
全部Pref=0

Stage2：
ESS恢复；主构网ESS Pref保持0

Stage3：
PV + ESS恢复；EV=0

Stage4：
PV + ESS + EV全部允许恢复
```

---

## 15.8 为什么你只看当前这张PNG，会对Stage3产生疑惑

这一点必须明确讲。

当前15图一键脚本的S14主图只读取：

```text
S14_黑启动四阶段真实执行_主体工况_PASS.mat
```

它没有把：

```text
S14_黑启动Stage3_PV恢复专项补测_PASS.mat
```

一起拼进这张PNG。

因此：

> **这张PNG可以很清楚证明 Stage数字1→2→3→4、PCC解列、ESS1 GFM以及最终Stage4恢复，但仅凭这一张底部Pref图，Stage3的PV“确实已经恢复且EV仍为0”并不够直观。**

正式S14 PASS不是只依赖这张PNG。

我们后来专门做了：

```text
Stage3 PV恢复专项补测
```

正式证据是：

```text
40～60 s Stage3期间：
PV1/PV2 ≈ 0.65 pu
EV1/EV2 = 0

Stage4以后：
EV才恢复
```

因此：

```text
S14完整PASS
=
透明回归
+
四阶段主体
+
Stage3 PV专项
```

---

## 15.9 这张图本身能证明什么

单看这张PNG可以确定：

```text
Stage 1→2→3→4
sequence active=1

executed mode=4
blackstart latch=1
PCC OPEN

ESS1 GridOn=0
ESS1 Droop=1

Pref Gate确实在不同阶段改变设备命令
```

再结合Stage3专项MAT：

```text
PV不早于Stage3
EV不早于Stage4
```

---

## 15.10 S14怎么判PASS

必须按三份证据联合：

```text
1. Gate关闭时透明
2. BLACK_START下PCC OPEN + ESS1 GFM
3. Stage1→2→3→4正确
4. Stage3 PV恢复、EV仍0
5. Stage4 EV最后恢复
```

**S14：PASS。**

> 如果以后要把15张图作为完全自包含的对外交付图，S14是最值得再优化的一张：建议把Stage3专项的小图拼进当前S14主图。当前不影响技术结论，但会更容易一眼看懂。

---

# 16. S15 受控并离网切换与重同步恢复

对应图：

```text
S15_受控并离网与重同步恢复.png
```

![S15](LOCAL15_15策略波形_PNG/S15_受控并离网与重同步恢复.png)

这张图包含：

```text
T0
T1
T2
```

三轮完全不同的测试。

所以不能从左上一路当成同一次Execute看。

---

# 17. S15先理解最终要实现什么

完整目标：

```text
NORMAL并网
↓
电气孤岛触发
↓
PCC OPEN
↓
ESS1 GFM
↓
ISLANDED
↓
Grid条件恢复
↓
RECOVERY_REQUEST
↓
RESYNCHRONIZATION
↓
检查 ΔV / Δf / Δθ
↓
微调ESS1 Fref
↓
同步条件连续满足
↓
PCC重合
↓
保持一小段时间
↓
清除island latch
↓
ESS1 GFM→GFL
↓
NORMAL
```

---

# 18. S15正式同步参数

正式默认：

```text
CFG15_S15_SYNC_DV_MAX_PU = 0.10
```

电压差最大10%。

```text
CFG15_S15_SYNC_DF_MAX_HZ = 0.20
```

频差最大0.2 Hz。

```text
CFG15_S15_SYNC_DTHETA_MAX_DEG = 10
```

相角差最大10°。

```text
CFG15_S15_SYNC_STABLE_S = 0.50
```

三个条件连续满足0.50 s才能合闸。

```text
CFG15_S15_RECLOSE_HOLD_S = 0.20
```

合闸后ESS1继续GFM约0.20 s，再回GFL。

Fref控制：

```text
Ktheta = 0.005 Hz/deg
Kdf = 0.50
trim max = 0.20 Hz
```

---

# 19. T0：为什么先做透明回归

T0关键：

```text
CFG15_MODE_ACTUATION_ENABLE = 0
CFG15_PCC_BREAKER_ACTUATION_ENABLE = 0
CFG15_S15_RECOVERY_REQUEST = 0
```

其它S15结构都已经在模型里。

我们问的是：

> 加入Phase Estimator、Recovery Manager、Fref Router以后，如果不允许它真实接管，旧正常并网是否完全不变？

---

## 19.1 左上：Mode / Breaker / Recovery state

看到：

```text
executed mode = 0
breaker request = 1
recovery state = 0
```

全程不变。

表示：

```text
正常并网
PCC保持闭合
Recovery没有误启动
```

---

## 19.2 右上：Fref Router透明性

三条线都在0：

```text
Fref trim = 0

ESS1 Final - Legacy = 0
ESS2 Final - Legacy = 0
```

这意味着：

```text
S15 Router加入后
没有偷偷改变ESS Fref
```

这是非常重要的“新结构关闭时完全透明”证明。

---

## 19.3 T0怎么判PASS

```text
mode=0
PCC close=1
recovery state=0
trim=0
ESS1 Final Fref=Legacy
ESS2 Final Fref=Legacy
```

全部成立。

**T0：PASS。**

---

# 20. T1：为什么故意禁止重合闸

T1是真实孤岛 + 重同步控制方向测试。

关键：

```text
CFG15_MODE_ACTUATION_ENABLE = 1
CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1

CFG15_EXEC_S05 = 1
CFG15_EXEC_S15 = 1

CFG15_ISLAND_MASTER = 1
```

选择ESS1为GFM主机。

最关键特殊参数：

```text
CFG15_S15_SYNC_STABLE_S = 999
```

---

## 20.1 为什么设置999 s

我们想验证：

```text
Δf/Δθ出现以后
Fref trim方向到底对不对
```

如果一开始就使用正式0.5 s：

```text
万一Fref方向反了
PCC仍可能自动尝试重合
```

不安全。

设999：

```text
可以进入RESYNC
可以真实Fref trim

但本轮100 s左右试验
绝不可能满足999 s连续条件
↓
PCC绝不会自动重合
```

这是一轮“只验证控制方向，不释放危险动作”的安全试验。

---

## 20.2 T1孤岛怎么制造

使用：

```text
CFG_AA_v_nom_V
10000 → 20000
```

形成确定性：

```text
electrical_bad
```

实际MAT：

```text
约18.546 s
mode：
0 → 3

island latch：
0 → 1

breaker request：
1 → 0
```

系统进入：

```text
ISLANDED
```

---

## 20.3 为什么后来还要把Vn恢复10000

要进入恢复流程，先要：

```text
外部电气异常条件已经消失
```

但：

```text
island latch仍然保留
PCC仍然OPEN
ESS1仍然GFM
```

这正是受控恢复需要的起点。

---

## 20.4 T1什么时候发恢复请求

实际MAT：

```text
约49.037 s：
RECOVERY_REQUEST 0 →1
```

此时：

```text
mode 3 →5
recovery state 0→1
recovery active=1
```

进入：

```text
RESYNCHRONIZATION
```

PCC继续保持：

```text
OPEN
```

---

## 20.5 左中图怎么看

模式线：

```text
0 →3 →5
```

即：

```text
NORMAL
→ ISLANDED
→ RESYNCHRONIZATION
```

`island latch`：

```text
0 →1
```

后一直保持1。

`breaker request`：

```text
1 →0
```

后一直为0。

这正是T1需要的：

```text
能同步
但不允许合闸
```

---

## 20.6 右中图：Δθ、Fref trim、Δf

蓝色左轴：

```text
Δθ / deg
```

右轴：

```text
Fref trim / Hz
Δf / Hz
```

恢复期间，S15根据：

```text
Δθ
+
Δf
```

给ESS1产生非零：

```text
Fref trim
```

实际T1恢复区间：

```text
|Δf|max ≈ 0.0157 Hz
|Δθ|max ≈ 3.37°
Fref trim 最大绝对值 ≈ 0.0211 Hz
```

均处于很小范围。

而且：

```text
ESS1 Final Fref = Legacy + trim
ESS2 Final Fref = Legacy
```

证明只有选中主机构网ESS被微调。

---

## 20.7 T1为什么PASS

到试验结束：

```text
recovery state始终=1
PCC始终OPEN
reclose command始终=0
```

而同步控制真实工作：

```text
Fref trim非零
Δf / Δθ保持受控
```

并且：

```text
sync timer虽然累计到约51 s
仍远小于999 s
```

所以没有重合。

**T1：PASS。**

---

# 21. T2：最终完整受控重并网

T2和T1基本相同。

唯一关键区别：

```text
CFG15_S15_SYNC_STABLE_S
恢复正式值：
0.50 s
```

以及：

```text
RECLOSE_HOLD = 0.20 s
```

---

## 21.1 实际状态时间

真实MAT：

```text
约19.396 s：
mode 0 →3
PCC 1→0
island latch 0→1
ESS1进入GFM
```

约：

```text
49.378 s：
RECOVERY_REQUEST生效
mode 3 →5
```

进入重同步。

---

## 21.2 右下：重合闸前同步量

正式RESYNC窗口内：

```text
|ΔV|max ≈ 0.01022 pu
|Δf|max ≈ 0.00610 Hz
|Δθ|max ≈ 2.492°
```

正式阈值：

```text
0.10 pu
0.20 Hz
10°
```

所以实际误差都明显低于阈值。

---

## 21.3 为什么这张图没有直接画sync timer

当前PNG底右只画：

```text
ΔV
Δf
Δθ
```

没有把：

```text
sync_timer
```

画出来。

但正式MAT审核确认：

```text
sync timer最大 ≈ 0.5001 s
```

所以：

```text
同步条件不是只瞬间成立
而是连续保持了正式要求的0.50 s
```

这部分正式PASS证据来自MAT，而不是单看PNG。

---

## 21.4 左下：什么时候真正重合闸

实际：

```text
约49.888 s：
PCC breaker request
0 →1
```

同时：

```text
reclose commanded = 1
```

这意味着：

> 同步判据已经连续满足0.5 s，S15才允许PCC闭合。

不是异常一消失就合闸。

---

## 21.5 为什么合闸以后mode还短暂保持5

重合以后不立刻：

```text
GFM→GFL
```

而是保持约：

```text
0.20 s
```

正式MAT：

```text
reclose timer ≈0.197 s
```

到约：

```text
50.085 s
```

才：

```text
island latch 1→0
mode 5→0
```

此时ESS1：

```text
GridOn 0→1
```

即：

```text
GFM → GFL
```

---

## 21.6 为什么图里 `clear_island` 看不到

`clear_island` 是：

```text
100 μs的一拍脉冲
```

而MAT记录间隔约：

```text
10 ms
```

所以可能刚好没采到这一拍。

但是它产生的结果全部被记录：

```text
island latch清零
mode回0
ESS1回GFL
```

因此不是证据缺失。

---

## 21.7 T2怎么判PASS

完整链必须同时成立：

```text
NORMAL
↓
ISLANDED
↓
RESYNC
↓
ΔV/Δf/Δθ在阈值内
↓
连续0.50 s
↓
PCC重合
↓
保持约0.20 s
↓
island latch清零
↓
mode回0
↓
ESS1 GFM→GFL
```

实际全部成立。

**T2：PASS。**

因此：

**S15完整策略：PASS。**

---

# 22. 15张图最终应该分别记住哪一句话

| 策略 | 看图时最核心的一句话 |
|---|---|
| S1 | S7想进口100 kW，S1只允许50 kW，所以effective dP被**+50 kW**硬修正 |
| S2 | `source=2`，Arbiter dP严格等于S2 dP，证明S2可以独立闭环 |
| S3 | S3执行期间Q request=Q applied，六路Qref按剩余视在容量分配 |
| S4 | S7想外送100 kW，S4要求不外送，effective dP被**-98 kW**修正 |
| S5 | 电气异常会解列；纯通信异常不会误跳PCC |
| S6 | PV升→ESS充，PV降→ESS放，request=applied且unserved=0 |
| S7 | S2/S7请求相同，但`source=7 + duplicate_guard=1`，没有重复执行 |
| S8 | Stage 0→1→2→1→0，对应0/50/100 kW，优先释放EV2 |
| S9 | 只看`source=9`的前段：S9非零dP真正成为主目标 |
| S10 | `source=10`全程成立，周期计划target真正进入P控制链 |
| S11 | +100 kW外送目标碰到+50 kW上限，effective dP被**-50 kW**修正 |
| S12 | 非零S12请求最低约-105 kW，source=12，并让EV增加充电吸收 |
| S13 | 只看`source=13`区间：老师已有多目标cmd真正进入AGC和Final Pref |
| S14 | PCC解列+ESS1 GFM+Stage1/2/3/4；完整Stage3还要结合专项MAT |
| S15 | T0透明、T1只同步不合闸、T2满足ΔV/Δf/Δθ后自动重合并回NORMAL |

---

# 23. 最容易看错的六张图

## 23.1 S1 / S4 / S11

原策略的：

```text
relief
```

会一直计算。

所以：

```text
relief非零
≠
已经真实执行
```

要结合：

```text
constraint active
```

和：

```text
objective vs effective
```

一起看。

---

## 23.2 S9 / S13

它们来自同一个联合MAT。

```text
raw request一直算
```

但只有：

```text
selected source
```

等于对应策略号的时间段才是真正执行区间。

---

## 23.3 S14

当前主PNG没有把Stage3专项补测拼进去。

所以：

```text
完整S14 PASS
不能只凭这一张PNG一句话证明
```

必须知道：

```text
Stage3 PV专项MAT
```

也是正式证据的一部分。

---

## 23.4 S15

图里没直接画：

```text
sync timer
```

但MAT证明：

```text
0.5001 s
```

图里也可能看不到：

```text
clear_island 100 μs pulse
```

但它造成的最终状态变化被完整记录。

---

# 24. 如果老师让你现场解释一张图，统一用这个模板

你可以按下面5句话说。

### 第一句：策略作用

> 这个策略主要解决的是……

### 第二句：为什么这么设工况

> 为了保证这个策略一定被明确激励，同时排除其它因素，我们故意设置……

### 第三句：先看策略层

> 第一幅图说明触发条件/策略请求已经真实出现……

### 第四句：再看执行层

> 第二幅说明该策略获得了执行权，并且最终请求按照正确方向被修正/路由……

### 第五句：最后看Plant接口

> 最后一幅Final Pref/Qref/GridOn/Breaker发生了与策略目标一致的真实变化，所以这不是Shadow日志，而是完整闭环PASS。

只要这五步能讲清楚，你就不再是在“背图”。

而是在：

```text
工况
→ 算法
→ 仲裁
→ 执行
→ Plant
```

完整解释控制因果。

---

# 25. 最终总结：这15张图到底共同证明什么

单张图分别证明：

```text
S1～S15各自功能
```

15张图放在一起真正证明的是：

```text
老师原15策略
status/alarm/metric/cmd
↓
请求标准化
↓
主目标/硬约束/模式仲裁
↓
P/Q资源分配
↓
S6/S8辅助
↓
S14阶段Gate
↓
控制源Router
↓
u_commit
↓
u_applied
↓
Final Pref / Qref / GridOn / Droop / Breaker / Fref
↓
真实2PV + 2ESS + 2EV Plant
```

都已经形成可验证的闭环。

因此这15张波形不是为了“画15张好看的图”。

它们真正的价值是：

> **成为LOCAL15最终冻结的可视化Golden Reference。**

以后BOARD15写进控制板以后，同样的工况再跑一次，就可以逐图比较：

```text
LOCAL15参考结果
vs
BOARD15板端结果
```

判断板端移植有没有把某个策略的：

```text
方向
执行权
约束
资源分配
模式逻辑
恢复状态机
```

写错。
