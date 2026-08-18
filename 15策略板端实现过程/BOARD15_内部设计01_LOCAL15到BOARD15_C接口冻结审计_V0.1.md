# BOARD15 内部设计 01｜LOCAL15 → BOARD15 C接口冻结审计 V0.1
## —— ControllerInput / Config / State / Output / Diagnostics / Adapter 第一轮边界设计

> **日期**：2026-08-17  
> **性质**：内部设计文件，**不是交给工程开发方的正式版本要求**。  
> **当前基线**：K26_V5 LOCAL15（本地15策略闭环）15/15 PASS（全部通过），作为 BOARD15（板端15策略）的 Golden Reference（黄金参考）。  
> **目的**：在正式把 LOCAL15 转成 C 代码、设计 BOARD15 Modbus 点表、编写最终工程程序版本要求以前，先把“算法到底需要什么输入、保存什么状态、输出什么命令、哪些状态如何更新、哪些功能留在 RT-LAB”分清。
>
> 本文采用三种标记：
>
> - **【已验证事实】**：来自当前模型、代码、MAT或V3.2/V4/V5已冻结工程语义；
> - **【建议冻结】**：当前基于事实给出的 BOARD15 设计建议，后续确认后可进入正式要求；
> - **【待决策】**：现在不能凭感觉写死，必须在下一轮周期/点表/通信设计中解决。
>
> ---
>
> # 0. 本轮先给结论
>
> BOARD15 不应该简单理解为：
>
> ```text
> 把 Advanced_Strategy_Core.m 翻译成 C
> ↓
> 放进当前 V5 程序
> ```
>
> 因为最终 LOCAL15 已经不是单独一个 15策略 MATLAB Function（MATLAB函数）：
>
> ```text
> 原15策略判断
> ↓
> Request Normalizer（请求标准化）
> ↓
> P Objective / Constraint（有功主目标 / 约束）
> ↓
> AGC（有功资源分配）
> ↓
> Execution Mapper（执行映射）
> ↓
> S6/S8 Auxiliary（辅助执行）
> ↓
> Black Start Gate（黑启动门控）
> ↓
> Command Source Router（命令源路由）
> ↓
> u_commit（正式提交前的命令状态）
> ↓
> Q / Mode / Breaker / Recovery 等其它执行域
> ```
>
> 所以最终 C 版本必须迁移的是：
>
> > **整个 LOCAL15 控制架构的算法语义，而不是只迁移原始 `Advanced_Strategy_Core`。**
>
> ---
>
> # 1. 继续继承 V3.2 → V4 → V5 的工程主线
>
> ## 1.1 【已验证事实】V3.2 已经建立安全通信外壳
>
> 已有：
>
> ```text
> DISCONNECTED
> WAIT_VALID
> ENABLED
>
> MODEL_STATUS
> RTLAB_HEARTBEAT
> BOARD_HEARTBEAT
> measurements_valid
> valid_cycles_before_enable
> 自动重连
> 输入范围检查
> EXT_AGC_ENABLE
> CMD_SEQ
> ```
>
> BOARD15 不重新发明另一套通信状态机。
>
> ---
>
> ## 1.2 【已验证事实】V4 已经建立 candidate / commit（候选 / 提交）
>
> V4 的核心原则：
>
> ```text
> 正式状态
> ↓ copy
> candidate_state
> ↓
> 算法计算
> ↓
> candidate_output
> ↓
> finite / range / encode 检查
> ↓
> FC16
>
> 成功：
> commit candidate
> CMD_SEQ + 1
>
> 失败：
> candidate 丢弃
> 正式状态不推进
> CMD_SEQ 不加
> ```
>
> 普通 Modbus 重连：
>
> ```text
> 不 reset AGC
> 不补算历史周期
> ```
>
> BOARD15 必须继承这种“成功发布才确认命令状态”的思想。
>
> ---
>
> ## 1.3 【已验证事实】V5-A 已经形成板端真实 Pref 接管
>
> V5-A：
>
> ```text
> BOARD_CMD
> ↓
> EXTERNAL_COMMAND_VALID
> ↓
> TAKEOVER_SWITCH
> ↓
> FINAL_APPLIED
> ↓
> 六设备 Pref
> ```
>
> 板端失效：
>
> ```text
> HOLD LAST_APPLIED
> ```
>
> 而不是立刻切回一个内部历史可能不同的本地AGC。
>
> BOARD15 应在此安全语义上扩展到：
>
> ```text
> P
> Q
> Mode
> Breaker
> Fref
> ```
>
> 而不是推翻 V5-A。
>
> ---
>
> # 2. 最终建议的软件边界
>
> ## 2.1 工程主程序层
>
> 工程开发方负责：
>
> ```text
> Modbus TCP
> FC03 / FC16
> decode / encode
> V3.2安全状态机
> 心跳
> 数据有效性
> scheduler（调度）
> input snapshot（输入快照）
> candidate / commit 管理
> JSON默认配置
> runtime config（运行时配置）
> CSV / log
> 断线重连
> ```
>
> ---
>
> ## 2.2 算法模块层
>
> 我方提供：
>
> ```text
> project15_core.c
> project15_core.h
> ```
>
> 其内部负责：
>
> ```text
> 原15策略判断
> 请求标准化
> P主目标/硬约束
> AGC资源分配
> S6/S8辅助
> S3 Q分配
> 模式判断
> GFM主机选择
> 黑启动阶段
> 重同步状态机
> ```
>
> ---
>
> ## 2.3 Controller Adapter（控制算法适配层）
>
> **【建议冻结】**
>
> 主程序不要直接到处调用：
>
> ```text
> strategy_xxx()
> agc_xxx()
> recovery_xxx()
> ```
>
> 而是只面对统一接口：
>
> ```text
> controller_reset(...)
> controller_init(...)
> controller_step(...)
> ```
>
> 当前：
>
> ```text
> controller_step
> → project15_core
> ```
>
> 后续增加其它算法：
>
> ```text
> controller_step
> → RESERVED / future controller
> ```
>
> 主程序外围不重构。
>
> ---
>
> # 3. `ControllerInput`（统一动态输入）第一轮冻结审计
>
> 最重要原则：
>
> > **输入接口不能只按“当前某个算法此刻恰好用什么”设计，而应把当前实时模型已经具备、完整BOARD15确定会使用的测量一次提供完整。**
>
> 但也不虚构当前模型不存在的设备状态。
>
> ---
>
> ## 3.1 时间
>
> ### 【已验证事实】
>
> 原策略和AGC都使用时间：
>
> ```text
> Advanced_Strategy_Core:
> t
>
> AGC:
> t
>
> S6:
> t
> ```
>
> V4正式要求已经使用：
>
> ```text
> 板端 monotonic clock（单调时钟）
> ```
>
> 不使用系统日期时间。
>
> ### 【建议冻结】
>
> ```c
> double monotonic_time_s;
> ```
>
> 作为算法内部正式时间基准。
>
> ### 【待决策】
>
> 是否额外提供：
>
> ```c
> double rtlab_sim_time_s;
> ```
>
> 只用于测试/日志时间对齐，而不是算法控制时间。
>
> ---
>
> # 3.2 PCC（公共耦合点）测量
>
> ### 【已验证事实】
>
> 当前已经具有：
>
> ```text
> Ppcc_kW
> Qpcc_kvar
> Vab_rms_pcc
> Freq_pcc
> ```
>
> ### 【建议冻结】
>
> ```c
> double pcc_p_kw;
> double pcc_q_kvar;
> double pcc_v_rms_v;
> double pcc_freq_hz;
> ```
>
> ---
>
> # 3.3 Grid（上级电网侧）测量
>
> ### 【已验证事实】
>
> 当前 J2_Grid_Measurements 已有：
>
> ```text
> Pgrid_kW
> Qgrid_kvar
> Vab_rms_grid
> Freq_grid
> ```
>
> Stage15明确使用：
>
> ```text
> Vab_rms_grid
> Freq_grid
> ```
>
> ### 【建议冻结】
>
> 完整输入结构保留：
>
> ```c
> double grid_p_kw;
> double grid_q_kvar;
> double grid_v_rms_v;
> double grid_freq_hz;
> ```
>
> 即使当前某些策略不直接使用 Pgrid/Qgrid，也属于已经存在、低成本且有明确工程语义的测量。
>
> ---
>
> # 3.4 同步相角
>
> ### 【已验证事实】
>
> LOCAL15 Stage15 当前采用：
>
> ```text
> Grid Vabc
> PCC Vabc
> ↓
> RT-LAB顶层 Phase Estimator
> ↓
> grid_phase_deg
> pcc_phase_deg
> phase_valid
> ```
>
> 原因是 Grid/PCC 两侧必须采用同一算法和同一坐标定义。
>
> ### 【建议冻结】
>
> **相角估计继续留在 RT-LAB，BOARD15 接收已经计算好的标量相角。**
>
> 即：
>
> ```c
> double grid_phase_deg;
> double pcc_phase_deg;
> int phase_valid;
> ```
>
> 不建议让板端通过低频 Modbus 接收三相瞬时 Vabc 后重新做相角估计。
>
> 理由：
>
> ```text
> Vabc是100 μs电磁暂态量
> ↓
> 普通Modbus管理周期无法等价搬运三相瞬时波形
> ↓
> RT-LAB本身已经有经过验证的同构相角估计器
> ```
>
> ### 【待决策】
>
> 相角标量更新频率需要多快，必须和 S15 板端执行周期一起审计。
>
> ---
>
> # 3.5 PV 最大可用功率
>
> ### 【已验证事实】
>
> ```text
> PV1_P_MAX
> PV2_P_MAX
> ```
>
> 同时：
>
> ```text
> S6真实读取的也是 Ppv_max1 / Ppv_max2
> ```
>
> 而不是PV Pmeas。
>
> ### 【建议冻结】
>
> ```c
> double pv_max_kw[2];
> ```
>
> ---
>
> # 3.6 ESS SOC
>
> ### 【已验证事实】
>
> ```text
> ESS1_SOC
> ESS2_SOC
> ```
>
> 当前 LOCAL15 Stage08 已保证 SOC 跟随最终真实执行链。
>
> ### 【建议冻结】
>
> ```c
> double ess_soc[2];
> ```
>
> ---
>
> # 3.7 六设备实测有功
>
> ### 【已验证事实】
>
> V4虽然基础AGC不用：
>
> ```text
> PV1 Pmeas
> PV2 Pmeas
> ESS1 Pmeas
> ESS2 Pmeas
> EV1 Pmeas
> EV2 Pmeas
> ```
>
> 但明确要求继续：
>
> ```text
> 读取
> 解码
> 记录
> ```
>
> ### 【建议冻结】
>
> ```c
> double p_meas_kw[6];
> ```
>
> 顺序固定：
>
> ```text
> 0 PV1
> 1 PV2
> 2 ESS1
> 3 ESS2
> 4 EV1
> 5 EV2
> ```
>
> 这组输入必须从最终主程序第一版就保留，不以后再扩。
>
> ---
>
> # 3.8 通信 / 模型可信状态
>
> ### 【已验证事实】
>
> 当前已经有：
>
> ```text
> MODEL_STATUS
> RTLAB_HEARTBEAT
> FC03 success/failure
> measurements_valid
> DISCONNECTED / WAIT_VALID / ENABLED
> ```
>
> 原 Advanced_Strategy_Core 还需要：
>
> ```text
> comm
> ```
>
> LOCAL15 当前用 Constant 1 代替旧通信仿真层。
>
> ### 【建议冻结】
>
> 不把：
>
> ```text
> 原 strategy comm
> ```
>
> 直接绑定某一个寄存器。
>
> 由主程序从当前真实通信状态生成统一布尔量：
>
> ```c
> int measurement_channel_valid;
> int command_channel_valid;
> int controller_enabled;
> int comm_ok_for_strategy;
> uint16_t model_status_raw;
> uint16_t rtlab_heartbeat;
> ```
>
> 其中：
>
> ```text
> comm_ok_for_strategy
> ```
>
> 是给原项目S5等策略使用的统一通信健康语义。
>
> ### 【待决策】
>
> `comm_ok_for_strategy` 到底定义为：
>
> ```text
> FC03 fresh
> AND
> FC16 recent success
> ```
>
> 还是主要代表测量链健康，必须结合最终策略安全逻辑冻结。
>
> ---
>
> # 3.9 最近正式提交信息
>
> ### 【已验证事实】
>
> V4已经有：
>
> ```text
> CMD_SEQ
> candidate
> committed state
> ```
>
> ### 【建议冻结】
>
> Controller Context / Input 中允许算法读取：
>
> ```c
> uint16_t last_committed_cmd_seq;
> int has_committed_command;
> ```
>
> 以及必要时：
>
> ```c
> double last_committed_pref_pu[6];
> ```
>
> 但这组量应来自主程序的 committed frame（正式提交帧），不是算法自己猜。
>
> ---
>
> # 3.10 当前不应该虚构的输入
>
> 当前不能直接写：
>
> ```text
> device_fault_status[6]
> inverter_temperature[6]
> breaker_feedback contacts
> hardware ACK from each inverter
> ```
>
> 因为当前模型/点表尚没有这些真实独立量。
>
> 如果后面确有接口再增加。
>
> ---
>
> # 4. `ControllerConfig`（配置）第一轮分类
>
> 这里最关键的工作不是“把所有CFG原样复制到C结构体”，而是分清：
>
> ```text
> A. 真正属于策略算法
> B. 属于板端执行框架
> C. 只属于LOCAL15测试环境
> D. 应继续留在RT-LAB
> ```
>
> ---
>
> # 4.1 原 `CFG_AA_*` —— 原策略算法参数
>
> ### 【已验证事实】
>
> 需要迁移的原策略配置包括：
>
> ```text
> CFG_AA_enable
> CFG_AA_demand_window_s
> CFG_AA_demand_limit_kW
> CFG_AA_agc_error_band_pct
> CFG_AA_v_nom_V
> CFG_AA_avc_v_deadband_pu
> CFG_AA_avc_q_limit_kvar
> CFG_AA_anti_reverse_limit_kW
> CFG_AA_anti_reverse_deadband_kW
> CFG_AA_island_freq_dev_Hz
> CFG_AA_island_v_dev_pu
> CFG_AA_smooth_rate_limit_pct_per_min
> CFG_AA_pv_fluct_trigger_pct
> CFG_AA_tie_target_kW
> CFG_AA_uv_threshold_pu
> CFG_AA_uf_threshold_Hz
> CFG_AA_load_shed_step_kW
> CFG_AA_peak_threshold_kW
> CFG_AA_valley_threshold_kW
> CFG_AA_plan_interval_s
> CFG_AA_export_limit_kW
> CFG_AA_renewable_target_pct
> CFG_AA_blackstart_enable
> CFG_AA_switch_enable
> CFG_AA_opt_weight_cost
> CFG_AA_opt_weight_carbon
> CFG_AA_opt_weight_renewable
> CFG_AA_opt_weight_tie
> CFG_AA_opt_weight_soc
> ```
>
> 加：
>
> ```text
> CFG_P_unit_kW
> ```
>
> ---
>
> # 4.2 AGC 独立配置
>
> ### 【已验证事实】
>
> 当前AGC还需要：
>
> ```text
> P_dead_kW
> SOC_min
> SOC_max
> Ts_agc
> PV_init_kW
> EV_init_kW
> ```
>
> ### 【建议冻结】
>
> 统一进入：
>
> ```c
> AgcConfig
> ```
>
> 与原15策略物理参数分开，不混成一个扁平数组。
>
> ---
>
> # 4.3 `CFG15_EXEC_S01 ... S15`
>
> ### 【建议冻结】
>
> 这15个真实执行许可必须迁到BOARD15：
>
> ```c
> uint32_t strategy_enable_mask;
> ```
>
> 比15个独立布尔寄存器更适合通信和配置。
>
> 但在C内部可以提供：
>
> ```text
> is_enabled(S01)
> ...
> ```
>
> ---
>
> # 4.4 `CFG15_P_OBJECTIVE_MODE`
>
> ### 【已验证事实】
>
> 当前编码：
>
> ```text
> 0 = S7
> 1 = S9
> 2 = S10
> 3 = S12
> 4 = S13
> ```
>
> ### 【建议冻结】
>
> 迁入 BOARD15 项目配置。
>
> ---
>
> # 4.5 模式与执行参数
>
> ### 【建议冻结】
>
> 以下需要保留：
>
> ```text
> BLACKSTART_MASTER
> ISLAND_MASTER
> MODE_ACTUATION_ENABLE
> PCC_BREAKER_ACTUATION_ENABLE
> BLACKSTART_PREF_SEQUENCE_ENABLE
> Q_SIGN_GAIN
> ```
>
> 这些在最终板端测试和项目运行中仍有明确作用。
>
> ---
>
> # 4.6 S15重同步参数
>
> ### 【建议冻结】
>
> 全部迁移：
>
> ```text
> RECOVERY_REQUEST
> SYNC_DV_MAX_PU
> SYNC_DF_MAX_HZ
> SYNC_DTHETA_MAX_DEG
> SYNC_STABLE_S
> RECLOSE_HOLD_S
> FREF_KTHETA_HZ_PER_DEG
> FREF_KDF
> FREF_TRIM_MAX_HZ
> ```
>
> ---
>
> # 4.7 不应该迁入项目控制器的 LOCAL15 测试参数
>
> ### 【建议冻结】
>
> 以下属于模型侧测试基础，不进入 project15_core：
>
> ```text
> CFG15_EXEC_FAULT_ENABLE
> CFG15_EXEC_FAULT_DEVICE
> CFG15_EXEC_FAULT_GAIN
> CFG15_EXEC_FAULT_START_S
> CFG15_EXEC_FAULT_END_S
> ```
>
> 原因：
>
> ```text
> execution fault
> 应在 u_commit 以后
> 由RT-LAB Plant侧制造
> ```
>
> 如果板端算法自己知道：
>
> ```text
> “我现在被故障注入了”
> ```
>
> 就破坏了真实执行失配语义。
>
> ---
>
> # 4.8 同样不进入 project15_core 的参数
>
> ```text
> CFG15_PARAM_PROBE
> CFG15_TEST_CASE_ID
> CFG15_TEST_ENABLE
> ```
>
> 它们是LOCAL15框架/测试探针。
>
> ---
>
> # 4.9 `CFG15_CONTROL_SOURCE`
>
> ### 【建议冻结】
>
> **不放进 `project15_core`。**
>
> 因为：
>
> ```text
> BOARD15本身就是一个控制源
> ```
>
> V5A / BOARD15 / fallback 的选择属于：
>
> ```text
> RT-LAB最终Source Router / 主程序安全层
> ```
>
> 而不是15策略算法内部。
>
> ---
>
> # 4.10 `CFG15_SYSTEM_PROFILE`
>
> ### 【建议冻结】
>
> 不沿用当前 LOCAL15 中带特定内部开发含义的 Profile 编码。
>
> 对工程主程序只保留通用：
>
> ```text
> algorithm_mode
> ```
>
> 当前：
>
> ```text
> PROJECT15
> ```
>
> 其它枚举：
>
> ```text
> RESERVED
> ```
>
> 用于后续算法扩展。
>
> ---
>
> # 5. `ControllerOutput`（算法输出）第一轮冻结
>
> 这里必须严格区分：
>
> ```text
> 算法候选输出
> ≠
> 主程序正式提交输出
> ≠
> RT-LAB Plant实际采用
> ```
>
> ---
>
> # 5.1 P有功命令
>
> ### 【已验证事实】
>
> 最终LOCAL15：
>
> ```text
> 6 × Final Pref
> ```
>
> ### 【建议冻结】
>
> ```c
> double pref_pu[6];
> ```
>
> 域：
>
> ```text
> PV  [0, 1]
> ESS [-1, 1]
> EV  [-1, 0]
> ```
>
> ---
>
> # 5.2 Q无功命令
>
> ### 【已验证事实】
>
> 最终：
>
> ```text
> 6 × Final Qref
> ```
>
> ### 【建议冻结】
>
> ```c
> double qref_pu[6];
> ```
>
> ---
>
> # 5.3 设备模式命令
>
> ### 【已验证事实】
>
> 最终 LOCAL15 控制：
>
> ```text
> 6 × Droop
> 6 × GridOn
> ```
>
> ### 【建议冻结】
>
> ```c
> uint8_t droop_enable[6];
> uint8_t grid_on[6];
> ```
>
> 当前语义：
>
> ```text
> GridOn=1 → GFL
> GridOn=0 → GFM
> ```
>
> ---
>
> # 5.4 PCC Breaker
>
> ### 【已验证事实】
>
> 当前最终：
>
> ```text
> PCC_BREAKER_REQUEST_CLOSE
> ↓
> RT-LAB Breaker Router
> ↓
> FINAL_BREAKER
> ```
>
> ### 【建议冻结】
>
> 板端算法输出：
>
> ```c
> uint8_t pcc_breaker_request_close;
> ```
>
> **不要让算法概念直接等同“物理断路器一定已经闭合”。**
>
> RT-LAB最终仍保留安全路由和Board有效性判断。
>
> ---
>
> # 5.5 Fref
>
> 这是一个当前不应该过早写死的接口。
>
> ### 【已验证事实】
>
> LOCAL15当前：
>
> ```text
> legacy_fref
> +
> fref_trim
> ↓
> selected ESS final Fref
> ```
>
> ### 【建议方向】
>
> BOARD15更适合输出：
>
> ```c
> double fref_trim_hz;
> uint8_t selected_master;
> uint8_t recovery_active;
> ```
>
> 由RT-LAB利用原Supervisor的：
>
> ```text
> legacy Fref
> ```
>
> 做最终：
>
> ```text
> legacy + trim
> ```
>
> 这样BOARD15不需要复制/追踪原Supervisor Fref基准。
>
> ### 【待决策】
>
> 最终点表到底传：
>
> ```text
> absolute final Fref
> ```
>
> 还是：
>
> ```text
> Fref trim + selected master
> ```
>
> 必须在BOARD15点表设计阶段冻结。
>
> ---
>
> # 5.6 系统状态输出
>
> ### 【建议冻结】
>
> ```c
> uint8_t system_mode;
> uint8_t selected_master;
> uint8_t controller_output_valid;
> ```
>
> 以及必要的：
>
> ```text
> objective_source
> constraint mask
> mode reason
> ```
>
> 可进入 diagnostics，不一定全部进入实时控制寄存器。
>
> ---
>
> # 6. 三层命令状态在BOARD15中如何对应
>
> ## 6.1 `u_calc`
>
> BOARD15中定义为：
>
> ```text
> project15_core 本轮计算得到的 candidate command frame
> ```
>
> 还没有经过：
>
> ```text
> FC16成功
> ```
>
> ---
>
> ## 6.2 `u_commit`
>
> 定义为：
>
> ```text
> 最近一次成功通过FC16完整发布到RT-LAB的 command frame
> ```
>
> 由：
>
> ```text
> 工程主程序 candidate / commit 管理
> ```
>
> 维护。
>
> 不是 project15_core 自己声称“我已经commit”。
>
> ---
>
> ## 6.3 `u_applied`
>
> 定义为：
>
> ```text
> RT-LAB实际进入Plant的最终命令状态
> ```
>
> 包括：
>
> ```text
> Board失效保持
> RT-LAB final safety
> execution fault injection
> ```
>
> ### 【建议冻结】
>
> `u_applied` **不作为BOARD15算法可直接读取的真值输入**。
>
> 它留在RT-LAB作为：
>
> ```text
> Plant侧真实执行诊断
> ```
>
> BOARD15只根据：
>
> ```text
> u_commit
> +
> Pmeas
> ```
>
> 判断系统实际状态。
>
> ---
>
> # 7. `ControllerState` —— 本轮最关键的状态分类
>
> **这是现在不能简单照抄V4的地方。**
>
> V4只有基础AGC，candidate/commit套在整个 `AgcState` 上很自然。
>
> BOARD15拥有：
>
> ```text
> 统计状态
> 能量累计状态
> 命令分配状态
> 平滑控制状态
> 模式锁存
> 恢复计时器
> ```
>
> 它们的物理含义不同。
>
> ---
>
> # 7.1 A类：Measurement / Estimator State（测量/统计状态）
>
> ### 【已验证事实】
>
> 原 `Advanced_Strategy_Core` persistent：
>
> ```text
> demand_avg
> peak_power
> pv_prev
> self_use_energy
> export_energy
> pv_energy
> curtailed_energy
> ```
>
> 这些主要代表：
>
> ```text
> 系统已经发生过什么
> ```
>
> 而不是：
>
> ```text
> 我成功发过什么控制命令
> ```
>
> ### 【建议冻结原则】
>
> 这类状态：
>
> ```text
> 在新的、有效、可信测量快照到达时更新
> ```
>
> **不应仅因为 FC16 本周期写失败就回滚。**
>
> 举例：
>
> ```text
> FC03仍然持续看到负荷峰值
> FC16碰巧一次失败
> ```
>
> `peak_power` 不应该假装这个峰值没有发生过。
>
> ---
>
> # 7.2 B类：Command Allocation State（命令/资源分配状态）
>
> ### 【已验证事实】
>
> AGC关键 persistent：
>
> ```text
> Ppv[2]
> Pess[2]
> Pev[2]
> ```
>
> 它们定义：
>
> ```text
> 下一轮资源从哪里继续分
> ```
>
> ### 【建议冻结原则】
>
> 这类状态继续继承 V4：
>
> ```text
> candidate calculation
> ↓
> candidate output
> ↓
> 成功完整发布
> ↓
> commit allocation state
> ```
>
> FC16失败：
>
> ```text
> 正式Ppv/Pess/Pev不推进
> ```
>
> 这和 V4 已冻结语义一致。
>
> ---
>
> # 7.3 C类：Auxiliary Command State（辅助命令状态）
>
> ### 【已验证事实】
>
> S6具有：
>
> ```text
> last_t
> smooth_ref
> initialized
> ```
>
> `smooth_ref`直接决定后续ESS补偿命令。
>
> ### 【建议冻结原则】
>
> `smooth_ref` 更接近：
>
> ```text
> command-generating state
> ```
>
> 初步建议：
>
> ```text
> 只有对应候选命令成功发布后
> 才正式推进控制用 smooth_ref
> ```
>
> 以避免：
>
> ```text
> 输出通信失败期间
> smooth_ref自己向前走
> ↓
> RT-LAB却一直HOLD旧命令
> ↓
> 恢复时命令突然跳到一个远处状态
> ```
>
> ### 【待决策】
>
> S6的“观测型PV变化记忆”和“控制型smooth_ref”是否需要拆成两个状态，需要在C转换时明确。
>
> ---
>
> # 7.4 D类：Mode Decision State（模式判断状态）
>
> 原策略中：
>
> ```text
> black_state
> switch_timer
> ```
>
> 既不是纯统计，也不是普通功率命令。
>
> ### 【建议冻结原则】
>
> 应拆成：
>
> ```text
> requested / detected mode
> ```
>
> 与：
>
> ```text
> executed / committed mode
> ```
>
> 两层。
>
> 即继承LOCAL15已经形成的：
>
> ```text
> raw mode
> ≠
> executed mode
> ```
>
> 不让“策略判断发生”直接等于“物理模式已经完成切换”。
>
> ---
>
> # 7.5 E类：Physical Execution Latch（物理执行锁存）
>
> ### 【已验证事实】
>
> 当前：
>
> ```text
> island_latch
> blackstart_latch
> ```
>
> 代表系统已经进入相应执行状态。
>
> ### 【建议冻结原则】
>
> 板端版本不能：
>
> ```text
> 算法一判断应该离网
> ↓
> 立刻把自己的executed mode记成ISLANDED
> ```
>
> 如果这一帧Breaker/GridOn命令：
>
> ```text
> FC16根本没有成功送出
> ```
>
> 板端就没有资格声称：
>
> ```text
> 已执行离网
> ```
>
> 所以 executed latch 至少应与：
>
> ```text
> command frame successful commit
> ```
>
> 建立关系。
>
> ### 【待决策】
>
> 是否还需要：
>
> ```text
> RT-LAB返回的执行状态确认
> ```
>
> 才把 `requested mode` 提升为 `executed mode`，要结合新点表确定。
>
> ---
>
> # 7.6 F类：Recovery / Synchronization State（恢复/同步状态）
>
> ### 【已验证事实】
>
> S15：
>
> ```text
> recovery_state
> sync_timer
> reclose_timer
> ```
>
> ### 【建议冻结原则】
>
> 这类状态不能简单规定：
>
> ```text
> “FC16失败就全部回滚”
> ```
>
> 也不能：
>
> ```text
> “通信坏了还继续同步计时”
> ```
>
> 应满足：
>
> ```text
> fresh Grid/PCC measurement
> +
> phase valid
> +
> mode route valid
> +
> command path可用
> ```
>
> 才允许 `sync_timer` 连续积累。
>
> 当关键可信条件失效：
>
> ```text
> sync_timer应清零或冻结
> ```
>
> 最终规则需要和快速通信周期一起设计。
>
> ---
>
> # 7.7 G类：Scheduler State（调度状态）
>
> 包括：
>
> ```text
> AGC last_t
> 各任务 last_run
> ```
>
> ### 【建议冻结原则】
>
> scheduler应归工程主程序 / 控制器调度层管理。
>
> 不把：
>
> ```text
> “什么时候调用某个模块”
> ```
>
> 与算法物理状态混为一体。
>
> ---
>
> # 8. 第一版 `ControllerState` 推荐结构
>
> 这里只冻结结构思想，不冻结最终C字段名。
>
> ```c
> typedef struct {
>
>     StrategyEstimatorState estimator;
>
>     AgcAllocationState agc;
>
>     AuxiliaryControlState auxiliary;
>
>     ModeDecisionState mode_request;
>
>     ModeExecutionState mode_execution;
>
>     RecoveryState recovery;
>
> } Project15State;
> ```
>
> 关键：
>
> > **不要再把所有 persistent 全塞进一个“candidate_state一刀切”。**
>
> 最终必须定义各子状态自己的：
>
> ```text
> update condition
> commit condition
> reset condition
> reconnect behavior
> ```
>
> ---
>
> # 9. `ControllerDiagnostics`（诊断）第一轮边界
>
> 主程序公共日志和算法日志分开。
>
> ---
>
> ## 9.1 Common Diagnostics（主程序公共诊断）
>
> 工程主程序天然应该记录：
>
> ```text
> monotonic_time
> communication_state
> FC03 result
> measurement snapshot sequence
> measurements_valid
> MODEL_STATUS
> RTLAB_HEARTBEAT
> candidate_valid
> encode result
> FC16 result
> CMD_SEQ
> BOARD_HEARTBEAT
> algorithm_mode
> ```
>
> ---
>
> ## 9.2 Project15 Diagnostics（算法内部诊断）
>
> 当前LOCAL15已经证明有价值的包括：
>
> ```text
> strategy status[15]
> alarm[15]
> metric[15]
> cmd[15]
>
> objective_source
> objective_dP
> effective_dP
> constraint_mask
>
> AGC status
> remain
>
> Q request / applied / capacity
>
> S6 request / applied / unserved
> S8 request / applied / unserved
>
> raw mode
> executed mode
> mode reason
> selected master
>
> breaker request
> island latch
> blackstart latch
>
> recovery state
> ΔV
> Δf
> Δθ
> sync timer
> reclose timer
> fref trim
> ```
>
> ### 【建议冻结】
>
> 不要求所有诊断全部占用实时Modbus寄存器。
>
> 应分：
>
> ```text
> Critical real-time diagnostics
> （需要RT-LAB看到）
>
> +
> Board CSV diagnostics
> （只需板端日志）
> ```
>
> ---
>
> # 9.3 通用扩展诊断槽
>
> ### 【建议冻结】
>
> 主程序日志结构预留：
>
> ```text
> EXT_DIAG[]
> ```
>
> 或等价通用诊断数组。
>
> 当前项目算法可使用其中一部分。
>
> 后续其它算法模块可以复用。
>
> 对工程开发方的理由：
>
> > 后续控制算法升级时无需重构日志模块。
>
> ---
>
> # 10. 哪些功能明确继续留在 RT-LAB
>
> 这一节很重要，避免BOARD15把Plant侧职责拿走。
>
> ---
>
> ## 10.1 Electrical Plant（电气对象）
>
> 全部留RT-LAB：
>
> ```text
> 2PV + 2ESS + 2EV
> inverter control plant
> network
> loads
> PCC
> breaker physical model
> SOC physical evolution
> ```
>
> ---
>
> ## 10.2 Final Board Validity / Hold（板端最终有效性与保持）
>
> ### 【建议冻结】
>
> 继续保留RT-LAB最后一层：
>
> ```text
> board output valid
> +
> board heartbeat fresh
> ↓
> accept new board frame
>
> invalid
> ↓
> HOLD LAST_APPLIED / safe behavior
> ```
>
> 原因：
>
> 如果BOARD程序本身：
>
> ```text
> 崩溃
> 断网
> ```
>
> 它不可能再主动告诉Plant：
>
> ```text
> “请安全保持”
> ```
>
> 所以最后一层安全必须在RT-LAB侧独立存在。
>
> ---
>
> ## 10.3 Execution Fault Injector
>
> ### 【建议冻结】
>
> 保留RT-LAB。
>
> 位置仍是：
>
> ```text
> u_commit
> ↓
> Plant-side execution fault
> ↓
> u_applied
> ```
>
> ---
>
> ## 10.4 Phase Estimator
>
> ### 【建议冻结】
>
> 当前继续留RT-LAB，向Board提供：
>
> ```text
> grid phase
> PCC phase
> valid
> ```
>
> ---
>
> ## 10.5 Legacy Fref / Final Fref Safety
>
> ### 【待决策】
>
> 如果最终采用：
>
> ```text
> Board输出Fref trim
> ```
>
> 则：
>
> ```text
> legacy_fref + trim
> ```
>
> 的最后组合继续放RT-LAB。
>
> ---
>
> # 11. PCC功率符号必须继续单独处理
>
> ### 【已验证事实】
>
> 当前LOCAL15冻结语义：
>
> ```text
> Ppcc > 0
> = 微电网向上级电网外送
>
> Ppcc < 0
> = 微电网从上级电网购电
> ```
>
> 但旧V3.1/V4点表40101使用：
>
> ```text
> 购电为正
> 送电为负
> ```
>
> V4用：
>
> ```text
> pcc_sign_gain = -1
> ```
>
> 转到AGC内部语义。
>
> ### 【建议冻结】
>
> 为避免破坏V3.2/V4既有寄存器：
>
> ```text
> 40101 legacy register semantics先保持不变
> ```
>
> 主程序解码后统一转换：
>
> ```text
> ControllerInput.pcc_p_kw
> ```
>
> 进入 project15_core 前：
>
> ```text
> 已经变成：
> 正=外送
> 负=进口
> ```
>
> 也就是说：
>
> > **符号转换只在I/O Adapter做一次，算法内部统一使用LOCAL15符号。**
>
> 不允许每个策略自己再翻一次符号。
>
> ---
>
> # 12. 第一轮推荐的 `ControllerInput` 草案
>
> > 字段名仅是内部草案，最终C字段名在转C前冻结。
>
> ```c
> typedef struct
> {
>     /* Time */
>     double monotonic_time_s;
>
>     /* PCC */
>     double pcc_p_kw;        /* + export, - import */
>     double pcc_q_kvar;
>     double pcc_v_rms_v;
>     double pcc_freq_hz;
>     double pcc_phase_deg;
>
>     /* Grid */
>     double grid_p_kw;
>     double grid_q_kvar;
>     double grid_v_rms_v;
>     double grid_freq_hz;
>     double grid_phase_deg;
>     int    phase_valid;
>
>     /* DER capabilities / states */
>     double pv_max_kw[2];
>     double ess_soc[2];
>     double p_meas_kw[6];
>
>     /* communication / model context */
>     int measurement_channel_valid;
>     int command_channel_valid;
>     int measurements_valid;
>     int controller_enabled;
>     int comm_ok_for_strategy;
>
>     uint16_t model_status_raw;
>     uint16_t rtlab_heartbeat;
>
>     /* commit context */
>     uint16_t last_committed_cmd_seq;
>     int has_committed_command;
>
> } ControllerInput;
> ```
>
> ---
>
> # 13. 第一轮推荐的 `ControllerOutput` 草案
>
> ```c
> typedef struct
> {
>     /* active/reactive command frame */
>     double pref_pu[6];
>     double qref_pu[6];
>
>     /* device operating mode requests */
>     uint8_t droop_enable[6];
>     uint8_t grid_on[6];
>
>     /* PCC request */
>     uint8_t pcc_breaker_request_close;
>
>     /* synchronization */
>     double fref_trim_hz;
>     uint8_t selected_master;
>
>     /* system state */
>     uint8_t system_mode;
>     uint8_t output_valid;
>
>     /* strategy output mirrors */
>     double strategy_status[15];
>     double strategy_alarm[15];
>     double strategy_metric[15];
>     double strategy_cmd[15];
>
> } ControllerOutput;
> ```
>
> 注意：
>
> ```text
> 这是算法候选输出结构
> ```
>
> 正式 `u_commit` 由工程主程序在成功FC16以后维护。
>
> ---
>
> # 14. 第一轮推荐的 `ControllerConfig` 分层
>
> ```text
> Project15Config
> │
> ├─ StrategyConfig
> │   └─ 原CFG_AA + P_unit
> │
> ├─ AgcConfig
> │   └─ deadband / SOC limits / Ts / init
> │
> ├─ ExecutionConfig
> │   ├─ strategy enable mask
> │   ├─ P objective mode
> │   ├─ Q sign gain
> │   ├─ mode actuation enable
> │   └─ breaker actuation enable
> │
> ├─ BlackStartConfig
> │   ├─ master
> │   └─ sequence enable
> │
> └─ ResyncConfig
>     ├─ recovery request
>     ├─ ΔV / Δf / Δθ
>     ├─ stable time
>     ├─ reclose hold
>     └─ Fref gains / limit
> ```
>
> 外围主程序再有：
>
> ```text
> AppConfig
> ├─ IP / port / Unit ID
> ├─ communication cycle
> ├─ reconnect
> ├─ heartbeat
> ├─ algorithm_mode
> ├─ logging
> └─ runtime config control
> ```
>
> 这两层不能混在一起。
>
> ---
>
> # 15. 当前最关键的“未冻结事项”
>
> 下面这些没有解决以前，**不能写最终工程版本要求**。
>
> ---
>
> ## O1. Sample-Time Audit（执行周期审计）【P0】
>
> 当前：
>
> ```text
> Plant = 100 μs
> V4 communication ≈ 1 s
> AGC = 1 s
> ```
>
> 但：
>
> ```text
> S15同步
> mode/safety
> heartbeat
> ```
>
> 不能直接假设也用1 s。
>
> 必须决定：
>
> ```text
> Board基础通信周期
> fast supervision周期
> AGC周期
> strategy慢周期
> S15周期
> ```
>
> 这是下一设计节点。
>
> ---
>
> ## O2. BOARD15完整Modbus点表【P0】
>
> 当前 40101～40116 / 40001～40012 不够。
>
> 需要新增：
>
> ```text
> Grid V/f/phase
> PCC phase
> phase_valid
>
> Qref
> GridOn
> Droop
> Breaker
> Fref trim / Fref
>
> runtime configuration bank
> diagnostics
> ```
>
> 具体地址、类型、scale、连续块必须重新设计。
>
> ---
>
> ## O3. 各状态类别的commit规则【P0】
>
> 必须逐项决定：
>
> ```text
> estimator state
> allocation state
> auxiliary state
> mode request
> executed mode latch
> recovery state
> ```
>
> 哪些：
>
> ```text
> valid measurement后更新
> ```
>
> 哪些：
>
> ```text
> FC16成功后commit
> ```
>
> 哪些：
>
> ```text
> 还需Plant执行确认
> ```
>
> ---
>
> ## O4. S15 Board输出到底是Absolute Fref还是Trim【P0】
>
> 当前推荐：
>
> ```text
> trim
> ```
>
> 但未冻结。
>
> ---
>
> ## O5. `comm_ok_for_strategy` 精确定义【P1】
>
> 需要结合：
>
> ```text
> FC03
> FC16
> heartbeat
> freshness
> ```
>
> 冻结。
>
> ---
>
> ## O6. Runtime Config 原子更新机制【P1】
>
> 推荐：
>
> ```text
> CONFIG_SEQ
> +
> config snapshot
> +
> apply at cycle boundary
> ```
>
> 但点表未冻结。
>
> ---
>
> ## O7. 扩展配置 / 扩展诊断槽大小【P2】
>
> 需要预留，但不能现在凭感觉定数量。
>
> ---
>
> # 16. 本轮已经可以冻结的设计原则
>
> 1. **BOARD15迁移整个LOCAL15控制架构，不只迁原15策略函数。**
>
> 2. **V3.2安全通信、V4 candidate/commit、V5真实接管都作为继承基线。**
>
> 3. **工程主程序与算法模块通过统一Controller Adapter解耦。**
>
> 4. **算法输入一次提供完整现有测量，不以后为新增算法反复改主程序。**
>
> 5. **相角估计先保留RT-LAB，板端接收Grid/PCC phase标量。**
>
> 6. **算法内部统一PCC符号：正=外送，负=进口；旧寄存器差异在I/O Adapter一次转换。**
>
> 7. **执行故障注入留RT-LAB，不迁入Board算法。**
>
> 8. **`u_calc`=候选ControllerOutput；`u_commit`=成功FC16后的正式命令帧；`u_applied`留Plant侧。**
>
> 9. **不能把整个Project15State无差别套一个candidate/commit，必须按状态性质分类。**
>
> 10. **板端输出不仅有6 Pref，还要覆盖Q、模式、Breaker和重同步命令。**
>
> 11. **RT-LAB继续保留Board失效时最后安全保持/回退的最后一道独立安全层。**
>
> 12. **最终工程文件只描述项目软件需求和扩展能力，不暴露任何内部后续用途。**
>
> ---
>
> # 17. 下一步
>
> 本轮完成的是：
>
> ```text
> LOCAL15 → BOARD15
> 接口/状态边界第一轮审计
> ```
>
> 下一步应立即做：
>
> > **BOARD15 Sample-Time Audit（板端多速率/执行周期审计）**
>
> 因为只有周期冻结以后，才能决定：
>
> ```text
> FC03多快
> S15测量多快
> Controller Step多快
> AGC多久更新
> Modbus点表一次读多少
> Runtime Config多久检查
> ```
>
> 而这些将直接决定最终程序主循环和通信架构。
