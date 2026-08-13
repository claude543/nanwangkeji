---
title: LC输入与高压侧prim输出彻底理解
tags: [内容理解, 南网科技, 变流器, LC, prim, PCC, Stubline]
created: 2026-08-13
updated: 2026-08-13
---

> 返回：[[projects/南网科技暑期项目/README|南网科技暑期项目主页]]

# LC输入与高压侧prim输出彻底理解

> 背景：本页是 [[projects/南网科技暑期项目/内容理解/2026-08-13_变流器两电平从Pref到Pmeas完整原理彻底理解|变流器两电平从Pref到Pmeas完整原理彻底理解]] 的延伸问答，聚焦「LC 之后到底发生了什么」：功率/电流通路、跨 SS/SM 串联、PCC 功率计算与 AGC 反馈、prim 测量返回链路。

## 0. 一条主链（先钉在脑子里）

```text
SS 实时任务内：                        SM 实时任务内：
直流源 → Two-Level → LC → 低压Delta    三个单相变压器(高压Yg) → prim → 馈线 → PCC → 电网
                    │                    ↑
       [3条差分Stubline，每相一条]    ← 电气能量跨任务通道
                    │
prim 高压侧 Vabc/Iabc（测量）→ 12维数值 → OpComm（信息跨任务通道）→ SS Control → Measurements
```

三件必须分清的事：

- **Stubline 传"电"，OpComm 传"数"**，两者不混。
- **功率 = 电压 × 电流**，是 V/I 的计算结果，不是独立的物理端口；控制手柄只有变流器输出电压。
- **prim 返回的是"读数"不是"电"**，控制器靠它闭环。

---

## Q1. 所以经过LC后只是变成了更平滑的交流电压吗？那怎么改变功率呢，电流又去哪里了呢

**A**：不是。LC 不只是"把电压抹平"，它本身就是电流流过的通道，功率恰恰是靠流过 L1 的那股电流送出去的。

- L1 是**串联**在功率通路里的，电流必须从它身上流过——它滤的是电流里的高频成分，电流本身没消失。
- C1 是**并联**旁路，只"借用"一小部分高频电流滤波，基波（50 Hz）电流几乎全部继续往前走。
- 往电网方向走的不是孤零零的"平滑电压"，而是**电压 + 电流**一起走。功率 = 电压 × 电流，电压由电网定，能变的就是电流。

**怎么改功率**：电网/PCC 电压（幅值、频率、相位）由强电网给定，设备改不动。它能动的是桥臂输出电压 `v_converter` 相对电网电压 `v_grid` 的：

- **相位差（功角）** → 决定有功 P（对应 d 轴电流 id）
- **幅值差** → 决定无功 Q（对应 q 轴电流 iq）

这个差压在 L 上逼出电流：`L·di/dt ≈ v_converter − v_grid − R·i`。所以控制链是：**想要功率 → 定需要多少电流 → 定桥臂输出什么电压（相对电网差多少）→ 电流被逼出 → 功率实现**。

**电流去哪**：`直流母线 → IGBT桥臂 → L1 → 节点 → 变压器 → 馈线 → PCC/电网`，C1 只在中途分走高频纹波。电流从直流侧被"泵"出，流过 L1 进电网，经三相回路回来。

---

## Q2. 我还是不明白，两电平变流器输出的实际上是三相交流电压，它哪里来的电流呢？经过LC之后送给大电网的究竟是电压还是电流还是功率呢

**A**：**电流不是变流器"生产"出来的，而是两个电压源之间的电压差在电感上逼出来的。** 变流器是电压源型（VSC），它只在输出端"强制"一个可控电压；对面电网也是电压源（固定电压）。两者之间隔着 L1（+变压器漏感、线路阻抗），于是：

```text
I = (v_converter − v_grid) / (R + jωL)
```

- 两者同幅同相 → ΔV = 0 → I = 0 → 没有功率交换；
- 制造相位差 δ → 有功 P ≈ (Vc·Vg / X)·sinδ；
- 制造幅值差 → 无功 Q ≈ (Vc − Vg)·Vg / X。

**送给电网的到底是什么**：接口处三样一体，分不开——

| 量 | 谁决定 | 性质 |
|---|---|---|
| 节点电压 U | 电网/系统 | 状态量（变流器改不动） |
| 注入电流 I | 变流器通过电压差控制 | 状态量 |
| 功率 P/Q | U × I 的乘积 | 能量流动率（结果） |

不存在"只送电压"或"只送电流"；电流流过电感、流向电网的瞬间，功率已经在交换。

一句话：**变流器不是把功率装进电网，而是通过改变自身电压相对电网的幅值和相位，在 L 上"引导"出一股电流；电流与电网电压一相乘，功率就出现了。**

---

## Q3. 所以出LC之后：电压（电网定的）+干净的基波电流（你控制的）→功率（乘积）。连接上跨ss与sm出来给了prim，然后是怎么串联的呢

**A**：单台设备的电气串联如下：

```text
【SS 内】                          【SM 内】
变流器 → LC → 低压Delta(D1)
                 │
  A/B/C 各一条差分 Stubline（跨任务边界，一步延时）
                 │
        三个单相变压器高压侧（Yg 星形接地）
                 │
              prim（高压侧 V/I 测量）
                 │
            高压馈线 Line_xx
                 │
            PCC 公共母线 → 10 kV 电网源/等值阻抗
```

关键点：

- **出 LC 先接低压 Delta**：三相变压器拆成 3 个单相双绕组，低压侧跨过 Stubline 后在 SS 内首尾相接成三角形（A_pos+C_neg、A_neg+B_pos、B_neg+C_pos）。Delta 绕组是浮置的，与差分 Stubline 天然匹配。
- **跨任务靠 3 条差分 Stubline**：每个单相绕组一条（每相 2 端点），内含一个仿真步（100 μs）传播延时，把 SM/SS 两个 CPU 任务在数学上解耦。6 台设备合计 18 条。
- **prim 在 SM 且位于变压器高压侧**：分核只改计算位置，不改测量语义。原模型 prim 就在高压侧，控制器一直依赖它。
- **prim 之后**：每台设备的高压馈线汇到 PCC（PV1 直连，其余各一段 RL 馈线；ESS1/EV1 共享上游馈线）。

注意：**电气路径**（SS→SM，Stubline）与**测量信号路径**（SM prim→SS，OpComm）是两条不同的通道，不要混。

---

## Q4. prim测量→高压馈线→PCC，这条线上走的是电压和电流？所以pcc处怎么得出当前交换的总功率然后反馈给AGC呢

**A**：是的，线上走的是真实三相电压和电流（物理电气网络）。**功率是 PCC 处由测到的 V/I "算"出来的，不是打包送过去的。**

**PCC 测功率分两步**：

1. 互感器测瞬时量：`Three-Phase V-I Measurement` → `Vabc_pcc`、`Iabc_pcc`。PCC 处电流是六台设备汇合后对上级电网的**净交换电流**。
2. 算法算 P/Q（`J2_PCC_Measurements` 内部）：
```text
Vabc → PLL → 基波频率 f / 相角 θ
Vabc + Iabc + θ → Power (PLL-Driven, Positive-Sequence) → Ppcc_kW / Qpcc_kvar
```
底层是瞬时功率定义 `p(t) = va·ia + vb·ib + vc·ic`（dq 下等价 `P = 1.5(vd·id + vq·iq)`）。**功率 = 电压 × 电流的数学结果。**

**反馈给 AGC**（AGC 在 SM 内）：
```text
Ppcc_kW（标量）
→ dP = P_target − Ppcc_kW
→ 按资源顺序分配（PV增发 → ESS放电 → EV减充，或反向）
→ 六路 Pref → 每台配成 12 维 → Memory → OpComm → SS → 控制器
→ 设备执行 → PCC 再变
```
（V4 把 AGC 搬到板端时，Ppcc 改经 Modbus 寄存器下发，但"由 V/I 算功率"这件事不变。）

---

## Q5. 那为什么刚刚从LC中送给sm的电压和电流就经过一个stubline的传导之后刚到sm中，然后prim就又测量然后给ss又返回去了呢

**A**：**送过去的是"电"，返回来的是"读数"，不是同一个东西。** 真正的电压电流到了 SM 就继续走向 PCC/电网，一去不复返（或按工况双向净流动）；prim 送回去的只是一份"测量报告"（数值信号），不是把电原路退回。

```text
路径① 电气功率：SS 变流器 → LC → Delta →[Stubline]→ SM 变压器 → prim测量点 → 馈线 → PCC → 电网
路径② 测量信息：SM prim 测 Vabc/Iabc（"拍照"）→ 12维数值 → OpComm → SS Control System
```

- **Stubline 传"电"**：真实电路的解耦边界，承载三相电压电流，带一步延时让 SM/SS 并行算。
- **OpComm 传"数"**：普通数值通信，传测量值/命令值，不承载功率。

所以是三个环节同时进行：**电从 SS 流向电网（功率）＋ prim 在 SM 读这个电（测量）＋ 读数经 OpComm 回 SS 喂控制器（反馈）**。闭环成立，但不是"电来回跑"。

---

## Q6. 它必须知道"设备接入点此刻真实状态是什么"，才能闭环（Pref−Pmeas→电流参考→电压命令）。所以prim测完返回来的这个高压侧的数能反映出什么消息呢，它只是刚刚从LC出去的电压和电流呀

**A**：**不是"LC 出口量的复刻"，而是"设备接入点此刻被整个电网环境塑造出来的实时状态"。** 它反映三样控制器自己算不出来的东西：

1. **Vabc → PLL 锁相**：提取电网此刻的相位 θ 和频率 f，是所有 dq 变换的基准。没有它，控制器就"失去方向"，无法在同步坐标里注入/吸收电流。
2. **Iabc → 实测电流**：对应设备实际注入/吸收的 P/Q，与目标 Pref 相减得功率误差。
3. **网络耦合结果**：prim 处的 V/I 是整个系统联立求解的结果，受电网电压波动、其他五台设备出力、馈线压降、负荷等影响——**控制器不可能靠内部公式预知，只能实测**。

例：EV1 的 Pref 一点没改，但 PV1 突然少发 50 kW → PCC 电压变 → 馈线压降变 → prim_EV1 的 V/I 也变。这个变化只能靠 prim 拿到。

物理上它也 ≠ LC 出口：经过变压器升压（480V→10kV）、漏阻抗、连接组别（D1 有 30° 相移）、馈线压降。

一句话：**命令（Pref/PWM）是控制器"想"的，prim 的 V/I 是系统"实际发生"的，闭环就是拿两者不断对齐。prim 是控制器的眼睛。**

---

## Q7. 具体描述一下送回到VabcIabc的去向模块是哪里，作用是什么

**A**：进入 SS 的 Control System 后，`Vabc` 和 `Iabc` 的**唯一接收者是 `Measurements`**（"眼睛 + 翻译器"），在内部被翻译成两套 dq/P/Q/PLL 信号再分发。当前 GridOn=1 走 GFL 套。

**Measurements 内部 4 组支路**：

| 支路 | 链 | 输出（顶层名） | 去向与作用 |
|---|---|---|---|
| PLL | Vabc → V->pu2 → PLL(3ph) | Freq_PLL / theta_PLL | GFL 相位基准，所有 dq 变换与最终 PWM 相角 |
| GFL 电压 dq | Vabc → V->pu2 → abc to dq2(θ_PLL) → 滤波 | VdVq_measPLL `[VdVqF]` | → signal switch → VdVqs → Current Regulator 前馈（外部已有多少电压） |
| GFL 电流 dq | Iabc → A->pu3 → abc to dq3(θ_PLL) → 滤波 | IdIq_measPLL `[IdIqF]` | → signal switch → IdIqs → Current Regulator 电流误差反馈 |
| GFL P/Q | Vabc+Iabc+Freq_PLL+θ_PLL → Power → 滤波 → Gain(4/6) | P_meas_PLL/Q_meas_PLL `[PmeasF]/[QmeasF]` | → Power Control Loop，与 Pref/Qref 求功率误差 |

（另有不带 PLL 后缀的 GFM 支路：用 Droop 自生 wt 转 dq / 算 P/Q，当前只作后台候选。）

**最终去向**：
```text
Vabc → PLL → theta_PLL → signal switch → wts → Vref Generation（调制相位基准）
Vabc → VdVqF  → signal switch → VdVqs → Current Regulator（前馈）
Iabc → IdIqF  → signal switch → IdIqs → Current Regulator（电流误差）
Vabc+Iabc → PmeasF/QmeasF → Power Control Loop（功率误差）
```

---

## 8. 七问串成一条线（最终总图）

```text
                      AGC 上层
                         │ Pref/Qref
                         ▼
         ┌───────── Power Control Loop（P/Q误差 → 电流参考）
         │                │
         ▼                ▼
prim V/I → Measurements →├─ PmeasF/QmeasF ──→ Power Loop
         （唯一接收者）   ├─ IdIqF ──────────→ Current Regulator 误差
                          ├─ VdVqF ─────────→ Current Regulator 前馈
                          └─ theta_PLL ─────→ Vref Generation 相位基准
         ↓ signal switch → Current Regulator → Vref Generation → PWM
         → Two-Level → LC → 低压Delta →[Stubline]→ 变压器 → prim → 馈线 → PCC
         ↓
         prim 重新测 V/I → SM 12维 → OpComm → SS → Measurements → 下一拍闭环
```

**必须记住的三句话**：

1. **Stubline 传"电"，OpComm 传"数"**——功率走物理网络，测量/命令走数值通信。
2. **功率 = 电压 × 电流**——是 V/I 的计算结果，不是独立的物理端口；控制手柄只有变流器输出电压（相位差管 P、幅值差管 Q）。
3. **prim 是控制器的眼睛**——它返回的 V/I 是"系统实际发生的结果"，PLL 靠它锁相、功率环靠它算 P/Q、电流环靠它求误差。

---

## 关联页面

- [[projects/南网科技暑期项目/内容理解/2026-08-13_变流器两电平从Pref到Pmeas完整原理彻底理解|变流器两电平从Pref到Pmeas完整原理彻底理解]]（本文的母文）
- [[projects/南网科技暑期项目/内容理解/2026-08-11_核心模型控制与分核彻底理解|核心模型控制与分核彻底理解]]（SM/SS、prim/PCC、Stubline 详解）
- [[projects/南网科技暑期项目/问题复盘/2026-08-09_拆分后模型闭环工作原理|拆分后模型闭环工作原理]]（100μs 并行闭环、边界延时）
- [[projects/南网科技暑期项目/内容理解/2026-08-11_SS逆变器Control_System逐模块彻底理解_补充电流环输入与层级逻辑|SS逆变器Control System逐模块彻底理解]]（Measurements 内部逐块）
