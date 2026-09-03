# K26_V5 FINAL PLANNED ISLAND V3.0

## 这是什么

这是从当前正式 V2 模型进入**第一次完整六设备计划离岛控制验证**的事务式改模 Patch。

它不是 C1/C2/Mode7/Stage2 单变量诊断。

## 本次真实结构变化

### SM_Master

新增：

- `AA15_FINAL_SYSTEM_STAGE`：唯一五台孤岛阶段参数。
- `AA15_FINAL_ISLAND_COORDINATOR`：
  - 接收 ESS1 `Fout`；
  - 复用 `Ppvmax1/2`、`SOC1/2`、`SOC_min/max`；
  - 捕获五台切岛前实际有功；
  - 计算一次 P-f 总修正；
  - 只使用一个慢速频率恢复积分器；
  - 按实时上下调余量分配给 PV1/PV2/ESS2/EV1/EV2；
  - 生成公共慢速电压恢复量。
- `AA15_FINAL_G29_MUX38`：重新定义 G29 为最终中央证据。

不扩大 PV/ESS/EV 三组当前 24 宽实时通信向量。

### 五台 GFL

每台：

- 原 `Droop` 通信字段在五台 GFL 中改作统一系统阶段；
- 旧 GFL Droop Control 固定禁用；
- `Fref` 在岛态下由中央送 ESS1 `Fout`；
- `Pref` 由中央送“切岛基准 + 一次P-f + 慢速协调”；
- `Vref` 承载公共慢速电压恢复；
- `AA15_ISLAND_GFL_SUPPORT_MANAGER` 全部替换；
- `AA15_PLL_EXEC_FRAME_HOLD` 全部替换：
  - 正常：本机 PLL；
  - hold：最后本机角 + ESS1 Fout 推进；
  - 恢复：无扰重新捕获本机 PLL。

## 第一 Build 基线

- Kfast = 0
- Kslow = 0.50
- VFF fc = 1 Hz
- K_PF_SUM = 0.50 pu/Hz
- P-f LPF = 2 Hz
- P-f deadband = ±0.02 Hz
- Ki_f_secondary = 0.80
- secondary total slew = 0.20 pu/s
- Kmag = 0.25
- Vsupport fc = 1 Hz
- support max: PV .20 / ESS2 .30 / EV .15 pu
- Imax = 1.20 pu
- FrameHold 0.85 / 0.95 pu
- EV undervoltage relief 0.95 -> 0.85 pu
- voltage secondary starts Stage3 + 0.30 s

## Stage

`K26_V5/SM_Master/AA15_FINAL_SYSTEM_STAGE/Value`

- 0 GRID_NORMAL
- 1 ISLAND_PREPARE
- 2 ISLAND_PRIMARY
- 3 ISLAND_SECONDARY
- 4 RESYNC_HOLD
- 5 GRID_RECOVERY

第一轮 Supervisor 将只使用 0 -> 1 -> 2 -> 3。

## G29 新定义

1 master_valid  
2 dP_primary_total  
3 dP_secondary_total  
4 dV_secondary  
5-9 up headroom PV1/PV2/ESS2/EV1/EV2  
10-14 down headroom PV1/PV2/ESS2/EV1/EV2  
15 stage_echo  
16 fail_code  
17-21 final Pref PV1/PV2/ESS2/EV1/EV2  
22-26 actual Pmeas PV1/PV2/ESS2/EV1/EV2  
27 J1 applied close  
28 PCC P  
29 PCC Q  
30 PCC online frequency（仅电压有效时解释）  
31 PCC Vab RMS  
32 ESS1 Fout  
33 ESS1 Vout  
34-35 Ppvmax1/2  
36-37 SOC1/2  
38 Punit

## 运行

1. 打开并确认当前 `K26_V5.slx` 是正式 V2，模型停止、Dirty=off。
2. 将 Patch 放在当前目录。
3. 运行：

```matlab
PATCH_K26_V5_FINAL_PLANNED_ISLAND_V3_0
```

4. 只有日志出现 `PATCH PASS` 才允许 Rebuild All。
5. 不要再使用 V2 supervisor；下一步将使用对应 V3 full planned-island supervisor。


## V3.0 交付前二次静态审查修正

正式交付前再次检查并修正：

1. GFL 新管理模块中 `MasterF` / `VrefCmd` 输入与诊断输出重名问题，诊断输出已改为 `MasterFDiag` / `VrefCmdDiag`。
2. 统一状态时序：Supervisor 约在 J1+0.20 s 进入 Stage3，因此有功慢速协调在 Stage3 进入即开始；电压慢速恢复额外延迟0.30 s，约 J1+0.50 s。
3. ESS2 能力约束明确使用 `SOC2`，不误用 ESS1 的 `SOC1`。
4. 代数环枚举 API 若在 R2023b/RT-LAB 环境不可用，只记录警告；完整模型 `compile` 仍是保存前后的硬门槛。
