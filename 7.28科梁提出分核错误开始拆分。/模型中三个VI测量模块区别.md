# 模型中三个V/I测量模块区别

## 现在区分三个最容易混淆的V/I测量块

现在模型中你至少要区分三类：

① **SS中的逆变器/低压侧测量**

② **SM中的六个prim\_\***

③ **SM中的PCC V-I Measurement**

它们可能长得很像，甚至都是Three-Phase V-I Measurement，但电气位置、用途、反馈层级完全不同。

---

## 十一、SS中的V/I测量到底是什么？

拆分以后，SS负责的是设备低压侧。

例如：

```text
SS_Slave
→ EV2 + EV1

SS_Slave2
→ ESS1 + ESS2

SS_Slave3
→ PV1 + PV2
```

每个SS里每台设备包含：

```text
Two-Level Converter；
DC侧；
本地滤波网络；
inv测量；
新增低压边界V-I测量；
Delta(D1)节点；
控制器；
PWM。
```

---

## 十二、SS里面其实又要分"inv测量"和"低压边界测量"

### 1. inv测量

它更靠近逆变器输出。

大致物理关系可以理解为：

```text
DC Source
   ↓
Two-Level Converter
   ↓
inv V-I measurement
   ↓
L1 / C1 等滤波网络
   ↓
低压交流端
```

它观察的是：

```text
逆变器自身输出侧的电压电流。
```

### 2. 拆分以后新增的低压V/I测量

例如：

```text
PV1_VI_LV
PV2_VI_LV
```

这些测量块是在采用官方Transformer Stubline分核结构以后增加的。交接文档明确记录了这些低压测量块，且其显式Vabc/Iabc在当前没有控制用途时可以直接在SS内部接Terminator。

它主要位于：

```text
逆变器/滤波器
        ↕
低压Delta(D1)边界
        ↕
Stubline
```

这一侧。

所以它的用途更接近：

```text
看低压分核边界上的电压电流。
```

---

## 十三、SS低压V/I为什么不能代替SM中的prim？

这是一个非常重要的问题。

因为它们根本不是同一个物理位置。

简化看：

```text
SS低压测量
   │
   │ 约480 V侧
   ↓
Delta
   ↓
Stubline / 变压器低压绕组
   ↓
变压器
   ↓
SM prim
   │
   │ 10 kV侧
   ↓
馈线 / 公共母线
```

所以两边之间隔着：

```text
变压器
```

而且我们的变压器存在：

```text
电压变比；
漏阻抗；
Yg / Delta(D1)连接；
相位关系。
```

所以低压侧测得的：

```text
Vabc_LV
Iabc_LV
```

和高压侧：

```text
Vabc_prim
Iabc_prim
```

不可能简单认为是同一信号。

我们的官方Stubline迁移结构本来就是：高压Yg部分在SM，低压侧在SS显式重构Delta(D1)，三相各通过差分Stubline跨任务边界。

因此：

```text
SS低压测量是分核边界/低压侧观测；SM prim才是设备接入10 kV网络时的高压侧反馈测量。
```

---

## 十四、那为什么控制器用的是SM prim，而不是SS低压测量？

因为我们迁移前的控制逻辑本来需要的是设备接入电网侧的三相状态。

现在虽然物理主电路被拆开：

```text
低压逆变器
在SS

高压变压器/馈线
在SM
```

但控制器不能因此失去原来的高压侧反馈。

于是我们专门建立：

```text
SM prim Vabc/Iabc
       ↓
普通数值通信
       ↓
SS Control System
```

这就是为什么每台设备12维输入里的前6个量是：

```text
Vabc(3)
Iabc(3)
```

来自对应自己的 prim\_\*。

换句话说：

> 物理设备被分到SS了，但它的"电网侧眼睛"仍然在SM，所以我们把眼睛看到的数据通过OpComm送回控制器。

这是理解当前分核模型的关键。

---

## 十五、为什么当时EV1接错prim_ESS1会这么严重？

我们曾经发现：

```text
prim_ESS1 Vabc/Iabc
        ↓
EV1_IO_Mux
        ↓
EV1 Control System
```

也就是说：

```text
EV1控制器控制的是EV1逆变器，但它看的却是ESS1的电网侧电压电流。
```

这就相当于：

```text
你在开1号车
方向盘控制1号车
但仪表盘显示的是2号车速度
```

那么：

```text
你踩油门
→ 1号车变快
→ 但仪表盘没按预期变化
→ 你继续踩
```

控制闭环必然异常。

最终恢复为：

```text
prim_EV1
→ EV1 Controller

prim_ESS1
→ ESS1 Controller
```

该错误及其修复在当前交接中已经明确记录。

---

## 十六、再看PCC V-I Measurement：它和prim是什么关系？

这是同一种"测量思想"，但测量层级不同。

可以把现在的系统想象成：

```text
PV1  ─ prim_PV1 ─┐
PV2  ─ prim_PV2 ─┤
ESS1 ─ prim_ESS1 ┤
ESS2 ─ prim_ESS2 ┤── 设备公共网络 ─ PCC VI ─ Grid
EV1  ─ prim_EV1 ─┤
EV2  ─ prim_EV2 ─┘
```

所以：

### prim

每台设备一个。

回答：

```text
"这台设备自己正在向系统送多少，还是从系统吸多少？"
```

### PCC VI

六台设备汇总以后只有一个。

回答：

```text
"整个微电网设备群合起来正在和外部电网交换多少功率？"
```

这两个层级完全不同。

---

## 十七、PCC为什么也必须规定ABC/abc方向？

因为PCC同样要定义：

```text
什么叫Ppcc正
什么叫Ppcc负
```

我们现在PCC最终恢复为：

```text
六设备网络
      ↓
   PCC ABC
  ┌────────┐
  │ PCC VI │
  └────────┘
   PCC abc
      ↓
Load1 / Load2 / Breaker / Grid
```

也就是：

```text
设备网络 → Grid
```

是PCC的正参考方向。当前最终PCC边界就是设备网络在ABC侧，Load/Grid在abc侧。

所以：

```text
六设备整体向外发电
设备 → PCC → Grid

Ppcc > 0
```

```text
六设备整体从电网吸收功率
Grid → PCC → 设备

Ppcc < 0
```

因此两台EV充电：

```text
Ppcc ≈ -120 kW
```

刚好与六个prim的设备功率符号体系统一。

---

## 十八、于是你可以把prim和PCC理解成"两级电表"

最容易记的方式：

```text
六块分户电表
= prim_PV1
  prim_PV2
  prim_ESS1
  prim_ESS2
  prim_EV1
  prim_EV2

一块总表
= PCC VI
```

理想情况下：

```text
P_PV1
+ P_PV2
+ P_ESS1
+ P_ESS2
+ P_EV1
+ P_EV2
- 网络损耗
≈ P_PCC
```

在我们的正常基线里：

```text
0
+0
+0
+0
-60
-60

≈ -120 kW
```

这就是为什么后来：

```text
六路设备功率总和
≈
PCC
```

成为判断模型是否恢复正常的重要证据
