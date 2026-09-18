# -*- coding: utf-8 -*-
r"""
RUN_K26_K50_ESS2_HEALTH_HANDOVER_PRIMARY_FORMAL_R2.py
======================================================================

R2.2 Build 后正式动态试验（R2：闭合 Restore Config 第五 Mode 源）：
  ESS1 构网 -> ESS2 同期/真实合闸 -> 0功率观察 -> -0.005 pu 小功率资格
  -> S14 与正常 Coordinator 同任务平滑接管 -> 接管后保持
  -> 小权限一次有功协调（Primary P-f，一次有功-频率协调）

没有透明回归，没有参数扫描，没有运行中控制参数写入。
人工 Reset -> Load once -> MODEL_PAUSED @ t≈0 后直接运行。

本轮首个基础任务始终为 -0.005 pu（100 kW 基准下约吸收 500 W）。
接管后的 Primary commissioning envelope（一次协调试验范围）仅允许：
  -0.006 <= Pcmd_ESS2 <= -0.004 pu  （约 -600 W ~ -400 W）
  总命令上/下变化速度 <= 0.0005 pu/s（约 50 W/s）
  ESS2 coordinator authority = 0.001 pu（约 100 W）
这是小权限验收边界，不是正常全功率能力声明。

普通 V/f/I/P 波动、功率误差、轻微振荡、CurrentLimit/调制波动不由 Host 提前判停。
模型内部状态、保护、限幅照常工作；Runner 只记录。
只有 RT-LAB API/时钟/执行身份等使数据本身失效的结构性错误才中止 Host 流程。

第一次 Execute 后禁止修改任何控制参数。58 s 终点只调度一次（57.9999 s按100 μs容差视为到达），
不要 Reset；随后直接运行配套 DirectMAT 计算脚本。
"""
import os, sys, re, csv, json, math, time, traceback
from datetime import datetime

import RtlabApi

VERSION = "ESS2_HEALTH_HANDOVER_PRIMARY_FORMAL_R2_20260918"
PROJECT_KEY = "yanshou_V7"
MODEL_KEY = "K26_K50_CLEAN_P1"
EXPECTED_STEP_S = 1e-4
MODEL_ROOT = r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\models\K26_K50_CLEAN_P1"
MODEL_FILE = os.path.join(MODEL_ROOT, MODEL_KEY + ".slx")
PROJECT_FILE = r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\yanshou_V7.llp"

TARGET_PU = -0.005
E2HH_MODE = 5.0
PRIMARY_AUTH_PU = 0.001
APPROVED_LIMITS = (-0.006, -0.004, 0.0005, 0.0005)
MAX_TARGET_CLOCK_S = 58.0
SAMPLE_STEP_S = 0.5
CASE_NAME = "HEALTH_HANDOVER_PRIMARY_R2_2_MODE5_FIXED"
CASE_TITLE = "R2.2健康资格 + 第五Mode源闭合 + 同任务接管 + 接管后小权限一次有功协调"

EXPECTED_PARAMS = {'CFG_GATEA_ENABLE': {'leaf': 'CFG_GATEA_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_GATEA_FREF_HZ': {'leaf': 'CFG_GATEA_FREF_HZ', 'property': 'Value', 'value': 50.0, 'required': True},
 'CFG15_MASTER_ENABLE': {'leaf': 'CFG15_MASTER_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_CONTROL_SOURCE': {'leaf': 'CFG15_CONTROL_SOURCE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_P_OBJECTIVE_MODE': {'leaf': 'CFG15_P_OBJECTIVE_MODE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S01': {'leaf': 'CFG15_EXEC_S01', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S02': {'leaf': 'CFG15_EXEC_S02', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S03': {'leaf': 'CFG15_EXEC_S03', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S04': {'leaf': 'CFG15_EXEC_S04', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S05': {'leaf': 'CFG15_EXEC_S05', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S06': {'leaf': 'CFG15_EXEC_S06', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S07': {'leaf': 'CFG15_EXEC_S07', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S08': {'leaf': 'CFG15_EXEC_S08', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S09': {'leaf': 'CFG15_EXEC_S09', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S10': {'leaf': 'CFG15_EXEC_S10', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S11': {'leaf': 'CFG15_EXEC_S11', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S12': {'leaf': 'CFG15_EXEC_S12', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S13': {'leaf': 'CFG15_EXEC_S13', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_EXEC_S14': {'leaf': 'CFG15_EXEC_S14', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_EXEC_S15': {'leaf': 'CFG15_EXEC_S15', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_MODE_ACTUATION_ENABLE': {'leaf': 'CFG15_MODE_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_PCC_BREAKER_ACTUATION_ENABLE': {'leaf': 'CFG15_PCC_BREAKER_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_DIAG_MODE_BREAKER_DECOUPLE': {'leaf': 'CFG15_DIAG_MODE_BREAKER_DECOUPLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG15_ISLAND_MASTER': {'leaf': 'CFG15_ISLAND_MASTER', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_BLACKSTART_MASTER': {'leaf': 'CFG15_BLACKSTART_MASTER', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE': {'leaf': 'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG15_S15_RECOVERY_REQUEST': {'leaf': 'CFG15_S15_RECOVERY_REQUEST', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_AA_enable': {'leaf': 'CFG_AA_enable', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_AA_blackstart_enable': {'leaf': 'CFG_AA_blackstart_enable', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_AA_tie_target_kW': {'leaf': 'CFG_AA_tie_target_kW', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_AA_v_nom_V': {'leaf': 'CFG_AA_v_nom_V', 'property': 'Value', 'value': 10000.0, 'required': True},
 'CFG_AA_island_freq_dev_Hz': {'leaf': 'CFG_AA_island_freq_dev_Hz', 'property': 'Value', 'value': 0.5, 'required': True},
 'CFG_AA_island_v_dev_pu': {'leaf': 'CFG_AA_island_v_dev_pu', 'property': 'Value', 'value': 0.1, 'required': True},
 'AA15_COMM_OK': {'leaf': 'AA15_COMM_OK', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_AC_CONNECT_PV1': {'leaf': 'CFG_DIAG_AC_CONNECT_PV1', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_AC_CONNECT_PV2': {'leaf': 'CFG_DIAG_AC_CONNECT_PV2', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_AC_CONNECT_ESS2': {'leaf': 'CFG_DIAG_AC_CONNECT_ESS2', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_AC_CONNECT_EV1': {'leaf': 'CFG_DIAG_AC_CONNECT_EV1', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_AC_CONNECT_EV2': {'leaf': 'CFG_DIAG_AC_CONNECT_EV2', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE': {'leaf': 'CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_DIAG_P_SCALE_PV1': {'leaf': 'CFG_DIAG_P_SCALE_PV1', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_P_SCALE_PV2': {'leaf': 'CFG_DIAG_P_SCALE_PV2', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_P_SCALE_ESS2': {'leaf': 'CFG_DIAG_P_SCALE_ESS2', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_P_SCALE_EV1': {'leaf': 'CFG_DIAG_P_SCALE_EV1', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_P_SCALE_EV2': {'leaf': 'CFG_DIAG_P_SCALE_EV2', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_Q_SCALE_PV1': {'leaf': 'CFG_DIAG_Q_SCALE_PV1', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_Q_SCALE_PV2': {'leaf': 'CFG_DIAG_Q_SCALE_PV2', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_Q_SCALE_ESS2': {'leaf': 'CFG_DIAG_Q_SCALE_ESS2', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_Q_SCALE_EV1': {'leaf': 'CFG_DIAG_Q_SCALE_EV1', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_DIAG_Q_SCALE_EV2': {'leaf': 'CFG_DIAG_Q_SCALE_EV2', 'property': 'Value', 'value': 1.0, 'required': True},
 'F1_FILTER_MODE': {'leaf': 'F1_FILTER_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F1_AD_ENABLE': {'leaf': 'F1_AD_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F1_K_AD': {'leaf': 'F1_K_AD', 'property': 'Value', 'value': 0.0, 'required': True},
 'F2_FAST_FB_MODE': {'leaf': 'F2_FAST_FB_MODE', 'property': 'Value', 'value': 2.0, 'required': True},
 'F2_IL_SIGN': {'leaf': 'F2_IL_SIGN', 'property': 'Value', 'value': 1.0, 'required': True},
 'F2_RFF_LOCAL': {'leaf': 'F2_RFF_LOCAL', 'property': 'Value', 'value': 0.0015, 'required': True},
 'F2_LFF_LOCAL': {'leaf': 'F2_LFF_LOCAL', 'property': 'Value', 'value': 0.125, 'required': True},
 'F2_PHASE_LOCAL_RAD': {'leaf': 'F2_PHASE_LOCAL_RAD', 'property': 'Value', 'value': 0.0, 'required': True},
 'F3_VREG_STATE_MODE': {'leaf': 'F3_VREG_STATE_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F4_ANGLE_SYNC_MODE': {'leaf': 'F4_ANGLE_SYNC_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F4_SYNC_OFFSET_RAD': {'leaf': 'F4_SYNC_OFFSET_RAD', 'property': 'Value', 'value': -2.0943951023931953, 'required': True},
 'F6_SHAPED_AD_ENABLE': {'leaf': 'F6_SHAPED_AD_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F6_SHAPED_AD_MODE': {'leaf': 'F6_SHAPED_AD_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F6_SHAPED_AD_GAIN': {'leaf': 'F6_SHAPED_AD_GAIN', 'property': 'Gain', 'value': 0.0, 'required': True},
 'F6_SHAPED_AD_SIGN': {'leaf': 'F6_SHAPED_AD_SIGN', 'property': 'Gain', 'value': -1.0, 'required': True},
 'F8_ENABLE': {'leaf': 'F8_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F8_IOUT_GAIN': {'leaf': 'F8_IOUT_GAIN', 'property': 'Gain', 'value': -1.0, 'required': True},
 'F8_CAP_GAIN': {'leaf': 'F8_CAP_GAIN', 'property': 'Value', 'value': 1.0, 'required': True},
 'F8_BC_PU': {'leaf': 'F8_BC_PU', 'property': 'Value', 'value': 0.05, 'required': True},
 'F8_IOUT_FILTER_MODE': {'leaf': 'F8_IOUT_FILTER_MODE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F9_VREG_MAP_MODE': {'leaf': 'F9_VREG_MAP_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F10_INNER_VRAW_MODE': {'leaf': 'F10_INNER_VRAW_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F10_INNER_IRAW_MODE': {'leaf': 'F10_INNER_IRAW_MODE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F20_IOUT_MODE': {'leaf': 'F20_IOUT_MODE', 'property': 'Value', 'value': 1.0, 'required': True},
 'F20_IOUT_RELEASE_TIME_S': {'leaf': 'F20_IOUT_RELEASE_TIME_S', 'property': 'Value', 'value': 6.2, 'required': True},
 'F20_V2_ENABLE': {'leaf': 'F20_V2_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F20_V2_CAPTURE_REQ': {'leaf': 'F20_V2_CAPTURE_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F20_V2_CLEAR_REQ': {'leaf': 'F20_V2_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F21_CURRENT_PI_RESET_ENABLE': {'leaf': 'F21_CURRENT_PI_RESET_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F22_ENABLE': {'leaf': 'F22_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F22_HANDOVER_MODE': {'leaf': 'F22_HANDOVER_MODE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F22_SUPPORT_ENABLE': {'leaf': 'F22_SUPPORT_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F22_SUPPORT_GAIN': {'leaf': 'F22_SUPPORT_GAIN', 'property': 'Value', 'value': 0.0, 'required': True},
 'F23_ENABLE': {'leaf': 'F23_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F23_ARM': {'leaf': 'F23_ARM', 'property': 'Value', 'value': 0.0, 'required': True},
 'F23_COMMIT_REQ': {'leaf': 'F23_COMMIT_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F23_CLEAR_REQ': {'leaf': 'F23_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F24_ENABLE': {'leaf': 'F24_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F24_ARM': {'leaf': 'F24_ARM', 'property': 'Value', 'value': 0.0, 'required': True},
 'F24_RELEASE_ENABLE': {'leaf': 'F24_RELEASE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F24_CLEAR_REQ': {'leaf': 'F24_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F25_ENABLE': {'leaf': 'F25_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'F25_PREPARE_ARM': {'leaf': 'F25_PREPARE_ARM', 'property': 'Value', 'value': 0.0, 'required': True},
 'F25_PREPARE_COMMIT_REQ': {'leaf': 'F25_PREPARE_COMMIT_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F25_EDGE_ARM_REQ': {'leaf': 'F25_EDGE_ARM_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'F25_CLEAR_REQ': {'leaf': 'F25_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_PLAN_COMMIT_ENABLE': {'leaf': 'CFG_PLAN_COMMIT_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_PLAN_COMMIT_HOLD_REQ': {'leaf': 'CFG_PLAN_COMMIT_HOLD_REQ', 'property': 'Value', 'value': 0.0, 'required': True},
 'AA15_FINAL_SYSTEM_STAGE': {'property': 'Value', 'value': 0.0, 'required': True, 'path': 'SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_SYSTEM_STAGE'},
 'AA15_S14V2_CFG_PICKUP_TARGET_PU': {'leaf': 'AA15_S14V2_CFG_PICKUP_TARGET_PU', 'property': 'Value', 'value': -0.005, 'required': True},
 'AA15_S14V2_CFG_ESS2_COORD_AUTH_PU': {'leaf': 'AA15_S14V2_CFG_ESS2_COORD_AUTH_PU', 'property': 'Value', 'value': 0.001, 'required': True},
 'CFG_ESS2_RESTORE_MASTER_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_MASTER_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_CONTROL_SOURCE': {'leaf': 'CFG_ESS2_RESTORE_CONTROL_SOURCE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_MANUAL_REQUEST': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_REQUEST', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_MANUAL_COMMIT': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_COMMIT', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_MANUAL_RELEASE': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_RELEASE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_ESS2_RESTORE_V_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_V_MIN_PU', 'property': 'Value', 'value': 0.9, 'required': True},
 'CFG_ESS2_RESTORE_V_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_V_MAX_PU', 'property': 'Value', 'value': 1.1, 'required': True},
 'CFG_ESS2_RESTORE_DF_MAX_HZ': {'leaf': 'CFG_ESS2_RESTORE_DF_MAX_HZ', 'property': 'Value', 'value': 0.5, 'required': True},
 'CFG_ESS2_RESTORE_IREF_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_IREF_MAX_PU', 'property': 'Value', 'value': 0.05, 'required': True},
 'CFG_ESS2_RESTORE_IMEAS_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_IMEAS_MAX_PU', 'property': 'Value', 'value': 0.05, 'required': True},
 'CFG_ESS2_RESTORE_HEADROOM_MIN': {'leaf': 'CFG_ESS2_RESTORE_HEADROOM_MIN', 'property': 'Value', 'value': 0.05, 'required': True},
 'CFG_ESS2_RESTORE_READY_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_READY_DWELL_S', 'property': 'Value', 'value': 0.5, 'required': True},
 'CFG_ESS2_RESTORE_POST_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_POST_DWELL_S', 'property': 'Value', 'value': 0.2, 'required': True},
 'CFG_ESS2_RESTORE_RELEASE_RAMP_S': {'leaf': 'CFG_ESS2_RESTORE_RELEASE_RAMP_S', 'property': 'Value', 'value': 2.0, 'required': True},
 'CFG_ESS2_RESTORE_PHASE_GATE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_PHASE_GATE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_PHASE_COS_MIN': {'leaf': 'CFG_ESS2_RESTORE_PHASE_COS_MIN', 'property': 'Value', 'value': 0.984807753012208, 'required': True},
 'CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN': {'leaf': 'CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_VRATIO_MIN': {'leaf': 'CFG_ESS2_RESTORE_VRATIO_MIN', 'property': 'Value', 'value': 0.95, 'required': True},
 'CFG_ESS2_RESTORE_VRATIO_MAX': {'leaf': 'CFG_ESS2_RESTORE_VRATIO_MAX', 'property': 'Value', 'value': 1.05, 'required': True},
 'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'CFG_ESS2_RESTORE_POST_I_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_I_MAX_PU', 'property': 'Value', 'value': 0.2, 'required': True},
 'CFG_ESS2_RESTORE_POST_V_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_V_MIN_PU', 'property': 'Value', 'value': 0.8, 'required': True},
 'CFG_ESS2_RESTORE_POST_V_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_V_MAX_PU', 'property': 'Value', 'value': 1.2, 'required': True},
 'CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN': {'leaf': 'CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN', 'property': 'Value', 'value': 1.0, 'required': True},
 'CFG_ESS2_RESTORE_FNOM_HZ': {'leaf': 'CFG_ESS2_RESTORE_FNOM_HZ', 'property': 'Value', 'value': 50.0, 'required': True},
 'CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S', 'property': 'Value', 'value': 2.0, 'required': True},
 'CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU', 'property': 'Value', 'value': 0.0045, 'required': True},
 'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU', 'property': 'Value', 'value': 0.0005, 'required': True},
 'CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S', 'property': 'Value', 'value': 3.0, 'required': True},
 'F7_VFF_GAIN': {'leaf': 'F7_VFF_GAIN', 'property': 'Gain', 'value': 1.0, 'required': False},
 'F11_CURRENT_REF_TEST_ENABLE': {'leaf': 'F11_CURRENT_REF_TEST_ENABLE', 'property': 'Value', 'value': 0.0, 'required': False},
 'F12_VFF_NOTCH_MODE': {'leaf': 'F12_VFF_NOTCH_MODE', 'property': 'Value', 'value': 0.0, 'required': False},
 'CFG_AA_switch_enable': {'leaf': 'CFG_AA_switch_enable', 'property': 'Value', 'value': 0.0, 'required': False},
 'CFG_ESS2_RESTORE_TS': {'leaf': 'CFG_ESS2_RESTORE_TS', 'property': 'Value', 'value': 0.0001, 'required': False},
 'TargetSlaveRecord': {'path': 'SS_Slave2/AA15_BASETEST_TARGET_PU', 'property': 'Value', 'value': -0.005, 'required': True},
 'FileID27': {'path': 'SS_Slave2/AA15_BASETEST_G27_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True},
 'FileID29': {'path': 'SM_Master/AA15_BASETEST_G29_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True},
 'FileID30': {'path': 'SS_Slave2/AA15_BASETEST_G30_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True},
 'E2_DIAG_P_LOOP_ENABLE': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/CFG_E2_DIAG_P_LOOP_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True},
 'E2_DIAG_Q_LOOP_ENABLE': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/CFG_E2_DIAG_Q_LOOP_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'E2_DIAG_DIRECT_IREF_ENABLE': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/CFG_E2_DIAG_DIRECT_IREF_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True},
 'E2_DIAG_DIRECT_ID_TARGET_PU': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/CFG_E2_DIAG_DIRECT_ID_TARGET_PU', 'property': 'Value', 'value': 0.0, 'required': True},
 'E2_DIAG_DIRECT_IQ_TARGET_PU': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU', 'property': 'Value', 'value': 0.0, 'required': True},
 'E2_DIAG_P_KP_RT': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/PI regulator with anti-windup D/CFG_E2_DIAG_P_KP_RT', 'property': 'Value', 'value': 0.06, 'required': True},
 'E2_DIAG_P_KI_RT': {'path': 'SS_Slave2/ESS2_Control/Power Control Loop/PI regulator with anti-windup D/CFG_E2_DIAG_P_KI_RT', 'property': 'Value', 'value': 0.5, 'required': True},
 'E2HH_NEXT_TARGET_PU': {'path': 'SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR/CFG_E2HH_NEXT_TARGET_PU',
                         'property': 'Value',
                         'value': -0.005,
                         'required': True}}

MANDATORY_SIGNALS = {'Ppcc_kW': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain/port1',
 'Qpcc_kvar': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain1/port1',
 'Freq_Hz': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Saturation1/port1',
 'Vab_rms_true_V': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain3/port1',
 'J1_applied_close': 'K26_K50_CLEAN_P1/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_GATEA_J1_FORCE_OPEN_SWITCH/port1',
 'executed_mode': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Grid_Mode_Execution_Manager/AA15_Grid_Mode_Execution_Core/port1',
 'ESS1_final_droop': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port3',
 'GridOn_1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port7',
 'GridOn_2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port8',
 'GridOn_3_ESS1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port9',
 'GridOn_4': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port10',
 'GridOn_5': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port11',
 'GridOn_6': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port12',
 'restore_state_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(1)',
 'restore_ready_count_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(2)',
 'restore_post_count_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(3)',
 'restore_alpha_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(4)',
 'restore_fail_code_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(5)',
 'ess2_final_idref': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(3)',
 'ess2_final_iqref': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(4)',
 'ess2_idmeas': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(5)',
 'ess2_iqmeas': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(6)',
 'ess2_mod_index': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(15)',
 'ess2_pmeas_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(16)',
 'ess2_qmeas_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(17)',
 'ess2_pll_hz': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(19)',
 'ess2_vpu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(21)',
 'ess2_pref_eff_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(26)',
 'ess2_qref_eff_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(28)',
 'ess2_current_limit': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(35)',
 'ess2_master_f_hz': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(37)',
 'ess2_raw_mod_demand': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(42)',
 'ess2_mod_headroom': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(43)',
 'ESS2_final_breaker_cmd': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_BREAKER_ROUTER/port1',
 'Pcmd_1_PV1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_1/port1',
 'Pcmd_2_PV2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_2/port1',
 'Pcmd_3_ESS1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_3/port1',
 'Pcmd_4_ESS2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_4/port1',
 'Pcmd_5_EV1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_5/port1',
 'Pcmd_6_EV2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_6/port1'}

OPTIONAL_SIGNALS = {'ESS1_Fout_direct': 'K26_K50_CLEAN_P1/SS_Slave2/ESS1_Control/Droop Control/Fout/port1',
 's14_substate': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_SUBSTATE/port1',
 's14_coarse_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_COARSE/port1',
 's14_elapsed_s': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_ELAPSED/port1',
 's14_restore_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_RESTORE_STAGE/port1',
 's14_coord_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_COORD_STAGE/port1',
 's14_gfl_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_GFL_STAGE/port1',
 's14_pickup_enable': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_PICKUP_ENABLE/port1',
 's14_owner_request': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_OWNER_REQUEST/port1',
 'p_s14_ramped_pu': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port2',
 'p_coord_raw_pu': 'K26_K50_CLEAN_P1/SM_Master/P3_FROM_002_01/port1',
 'p_final_applied_pu': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port1',
 'handover_beta': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port3',
 'ess2_available': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_AVAILABLE/port1',
 'correction_gain': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_CORRECTION_GAIN/port1',
 'secondary_enable': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_SECONDARY/port1',
 's14_active': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_ACTIVE/port1',
 'coord_dp_primary': 'K26_K50_CLEAN_P1/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE/port17',
 'coord_dp_secondary': 'K26_K50_CLEAN_P1/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE/port18',
 'coord_master_valid': 'K26_K50_CLEAN_P1/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE/port16'}

class ContractFail(RuntimeError):
    pass

class TrialStop(RuntimeError):
    def __init__(self, status, reason):
        super(TrialStop, self).__init__(reason)
        self.status = str(status)
        self.reason = str(reason)

def normalize_path(x):
    p = str(x).replace("\\", "/")
    p = re.sub(r"\s+", " ", p).strip()
    p = re.sub(r"\s*/\s*", "/", p)
    return p.rstrip("/")

def scalar(v):
    if isinstance(v, (tuple, list)):
        if len(v) != 1:
            raise ContractFail("预期单值，实际=%r" % (v,))
        v = v[0]
    return float(v)

def almost(a,b,tol=1e-8):
    try:
        return math.isfinite(float(a)) and math.isfinite(float(b)) and abs(float(a)-float(b)) <= tol
    except Exception:
        return False

def split_state():
    raw = RtlabApi.GetModelState()
    if isinstance(raw,(tuple,list)):
        return raw[0], raw
    return raw, raw

def host_norm(path):
    return os.path.normcase(os.path.normpath(str(path).replace("/",os.sep).replace("\\",os.sep)))

def _looks_like_model_info(x):
    return isinstance(x,(tuple,list)) and len(x)>=3 and isinstance(x[0],str)

def _normalize_models_field(models):
    if models is None:
        return []
    if _looks_like_model_info(models) and isinstance(models[0],str):
        return [tuple(models)]
    if isinstance(models,(tuple,list)):
        return [tuple(x) for x in models if _looks_like_model_info(x)]
    return []

def connect_exact_model(log):
    try:
        cur = RtlabApi.GetCurrentModel()
    except Exception:
        cur = None
    def exact(cur):
        if not isinstance(cur,(tuple,list)) or len(cur)<2:
            return False
        expected = normalize_path(MODEL_FILE).lower()
        cands=[str(cur[0]),str(cur[1]),normalize_path(cur[0])+"/"+str(cur[1])]
        for c in cands:
            n=normalize_path(c).lower()
            if n==expected or n+".slx"==expected:
                return True
        return False
    if exact(cur):
        log("[CONNECT PASS] reuse current model: %r" % (cur,))
        return cur

    active=list(RtlabApi.GetActiveProjects() or [])
    candidates=[]
    for item in active:
        if not isinstance(item,(tuple,list)) or len(item)<6:
            continue
        pp=host_norm(item[0])
        if os.path.basename(pp).lower()==PROJECT_KEY.lower()+".llp":
            models=_normalize_models_field(item[5])
            if len(models)==1 and MODEL_KEY.lower() in normalize_path(models[0][0]).lower():
                candidates.append(item)
    if len(candidates)!=1:
        raise ContractFail("无法唯一确定 yanshou_V7 当前工程：%r" % ([x[0] for x in candidates],))
    RtlabApi.OpenProject(project=candidates[0][0], returnOnAmbiguity=True)
    deadline=time.monotonic()+4.0
    while time.monotonic()<deadline:
        cur=RtlabApi.GetCurrentModel()
        if exact(cur):
            log("[CONNECT PASS] exact current model: %r" % (cur,))
            return cur
        time.sleep(0.1)
    raise ContractFail("打开工程后仍未附着到 K26_K50_CLEAN_P1。")

def signal_rows():
    rows=[]
    for rec in list(RtlabApi.GetSignalsDescription()):
        try:
            rows.append({"id":int(rec[1]),"path":str(rec[2]),"label":str(rec[3])})
        except Exception:
            pass
    return rows

def resolve_signal(rows, raw_path):
    wanted=normalize_path(raw_path)
    exact=[r for r in rows if normalize_path(r["path"]).lower()==wanted.lower()]
    if exact:
        paths={normalize_path(r["path"]).lower():r["path"] for r in exact}
        if len(paths)==1:
            return next(iter(paths.values()))
    suffix="/"+normalize_path(raw_path).split(MODEL_KEY+"/")[-1]
    hits=[r for r in rows if normalize_path(r["path"]).lower().endswith(suffix.lower())]
    paths={normalize_path(r["path"]).lower():r["path"] for r in hits}
    if len(paths)==1:
        return next(iter(paths.values()))
    return None

def resolve_parameter(pdesc, spec):
    hits=[]
    for row in pdesc:
        try:
            path,prop=str(row[1]),str(row[2])
        except Exception:
            continue
        if prop.lower()!=spec["property"].lower():
            continue
        npath=normalize_path(path)
        if "path" in spec:
            ok=npath.lower().endswith("/"+normalize_path(spec["path"]).lower())
        else:
            ok=npath.split("/")[-1].lower()==spec["leaf"].lower()
        if ok:
            hits.append(path.rstrip("/\\")+"/"+prop)
    uniq={normalize_path(x).lower():x for x in hits}
    if len(uniq)==1:
        return next(iter(uniq.values()))
    return None


class Runner:
    def __init__(self):
        self.stamp=datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        root=r"D:\E2RUN"
        try:
            os.makedirs(root,exist_ok=True)
        except Exception:
            root=os.path.join(os.environ.get("TEMP",os.getcwd()),"E2RUN")
            os.makedirs(root,exist_ok=True)
        self.run_dir=os.path.join(root,"handover_primary_r2_2_mode5fix_"+self.stamp)
        os.makedirs(self.run_dir,exist_ok=False)
        self.logf=open(os.path.join(self.run_dir,"run.txt"),"w",encoding="utf-8",buffering=1)
        self.param_paths={};self.signal_paths={};self.optional_paths={}
        self.param_before={};self.extra_before={};self.expected={};self.written=[]
        self.mode_paths=[];self.restore_mode_path=None;self.limits_paths=[];self.mode_readback={};self.host_warnings=[]
        self.clock=None;self.t=0.0;self.execute_attempted=False
        self.sys_ctrl=False;self.par_ctrl=False;self.observations=[];self.events=[]
        self.file_id=int(time.time()*1000)%1000000000
        self.status="CREATED";self.reason="";self.stop_before=None
        self.event_times={}
        self.contract_flags={"wrong_mode_seen":False,"j1_closed_seen":False,"ess1_role_lost_seen":False,
                             "secondary_seen":False,"model_fail_seen":False,"nonfinite_seen":False}

    def log(self,s=""):
        text=str(s);print(text);sys.stdout.flush();self.logf.write(text+"\n");self.logf.flush()

    def event(self,kind,**kw):
        row={"event":kind,"target_clock_s":self.t,"host_time":datetime.now().isoformat()};row.update(kw)
        self.events.append(row)
        if kind not in self.event_times:self.event_times[kind]=self.t
        with open(os.path.join(self.run_dir,"events.jsonl"),"a",encoding="utf-8") as f:
            f.write(json.dumps(row,ensure_ascii=False)+"\n")

    def take_controls(self):
        RtlabApi.TakeFunctionControl(RtlabApi.OP_FB_SYSTEM,0,RtlabApi.OP_CTRL_PRIO_MACRO);self.sys_ctrl=True
        RtlabApi.TakeFunctionControl(RtlabApi.OP_FB_PARAMETER,0,RtlabApi.OP_CTRL_PRIO_MACRO);self.par_ctrl=True

    def release_controls(self):
        if self.par_ctrl:
            try:RtlabApi.ReleaseFunctionControl(RtlabApi.OP_FB_PARAMETER,0)
            except Exception as e:self.log("参数控制释放警告：%r"%e)
        if self.sys_ctrl:
            try:RtlabApi.ReleaseFunctionControl(RtlabApi.OP_FB_SYSTEM,0)
            except Exception as e:self.log("系统控制释放警告：%r"%e)

    def read_clock(self):
        v=scalar(RtlabApi.GetSignalsByName((self.clock,)))
        if not math.isfinite(v):raise ContractFail("目标时钟无效，无法继续形成有效时序数据。")
        return v

    def _special_parameter_hits(self,pdesc,names):
        out=[]
        lowNames={x.lower() for x in names}
        for row in pdesc:
            try:path,prop=str(row[1]),str(row[2])
            except Exception:continue
            if prop.lower()!="value":continue
            leaf=normalize_path(path).split("/")[-1].lower()
            if leaf in lowNames:out.append(path.rstrip("/\\")+"/"+prop)
        uniq={normalize_path(x).lower():x for x in out}
        return list(uniq.values())

    def discover(self):
        pdesc=list(RtlabApi.GetParametersDescription());srows=signal_rows();missing=[]
        for key,spec in EXPECTED_PARAMS.items():
            p=resolve_parameter(pdesc,spec)
            if p is None:
                if spec.get("required",True):missing.append("parameter:"+key)
            else:self.param_paths[key]=p
        # Four previously-proven Mode sources.
        self.mode_paths=self._special_parameter_hits(
            pdesc,("AA15_BASETEST_ENABLE","AA15_ESS2_BASETEST_ENABLE")
        )
        if len(self.mode_paths)!=4:
            missing.append("E2HH generic mode sources expected4 got%d:%r"%(len(self.mode_paths),self.mode_paths))

        # Fifth Mode source: Restore Executor receives cfg(35) from this Restore Config Constant.
        # This exact runtime path was proven reversibly tunable on the current Build:
        # original 1 -> write 5 -> readback 5 -> restore 1 -> readback 1.
        self.restore_mode_path=resolve_parameter(pdesc,{
            "path":"SS_Slave2/AA15_ESS2_RESTORE_CONFIG/CFG_ESS2_BASETEST_ENABLE",
            "property":"Value",
            "required":True
        })
        if self.restore_mode_path is None:
            missing.append("Restore Config fifth mode source not exposed")
        # RT-LAB exposes vector/matrix parameters as indexed scalar names
        # (e.g. Value(1), Value(2), ...). Discover the four approved-limit elements.
        lim=[]
        for row in pdesc:
            try:
                bpath,pname=str(row[1]),str(row[2])
            except Exception:
                continue
            if normalize_path(bpath).split("/")[-1].lower()!="cfg_e2hh_approved_limits":
                continue
            if not pname.lower().startswith("value"):
                continue
            nums=[int(x) for x in re.findall(r"\((\d+)\)",pname)]
            order=tuple(nums) if nums else (999,)
            lim.append((order,bpath.rstrip("/\\")+"/"+pname))
        lim.sort(key=lambda x:x[0])
        self.limits_paths=[x[1] for x in lim]
        if len(self.limits_paths)!=4:
            missing.append("CFG_E2HH_APPROVED_LIMITS indexed scalars expected4 got%d:%r"%(len(self.limits_paths),self.limits_paths))
        for key,path in MANDATORY_SIGNALS.items():
            p=resolve_signal(srows,path)
            if p is None:missing.append("signal:"+key)
            else:
                try:scalar(RtlabApi.GetSignalsByName((p,)));self.signal_paths[key]=p
                except Exception as e:missing.append("signal:%s(%r)"%(key,e))
        for key,path in OPTIONAL_SIGNALS.items():
            p=resolve_signal(srows,path)
            if p is not None:
                try:scalar(RtlabApi.GetSignalsByName((p,)));self.optional_paths[key]=p
                except Exception:pass
        for cand in [MODEL_KEY+"/SM_Master/Clock/port1",MODEL_KEY+"/SM_Master/Board_HB_Time/port1",MODEL_KEY+"/SM_Master/Clock1/port1"]:
            p=resolve_signal(srows,cand)
            if p:
                try:scalar(RtlabApi.GetSignalsByName((p,)));self.clock=p;break
                except Exception:pass
        if self.clock is None:missing.append("target_clock")
        with open(os.path.join(self.run_dir,"discovery.json"),"w",encoding="utf-8") as f:
            json.dump({"mandatory":self.signal_paths,"optional":self.optional_paths,"parameters":self.param_paths,
                       "mode_paths_generic":self.mode_paths,"restore_mode_path":self.restore_mode_path,
                       "all_mode_paths":self.mode_paths+([self.restore_mode_path] if self.restore_mode_path else []),
                       "limits_paths":self.limits_paths,"missing":missing},f,ensure_ascii=False,indent=2)
        if missing:raise ContractFail("当前Build正式试验必要接口发现失败；Execute前阻断：%r"%missing)
        self.log("接口发现PASS：标量参数%d，Mode源5/5（含Restore Config第五源），Limits向量1/1，必要信号%d，可选信号%d。"%
                 (len(self.param_paths),len(self.signal_paths),len(self.optional_paths)))

    def require_zero(self):
        state,raw=split_state()
        if state!=RtlabApi.MODEL_PAUSED:raise ContractFail("请人工 Reset -> Load once 后保持 MODEL_PAUSED；实际=%r"%(raw,))
        dt,factor=RtlabApi.GetTimeInfo()
        if not almost(dt,EXPECTED_STEP_S,1e-10):raise ContractFail("目标步长不是100微秒：%r"%dt)
        self.t=self.read_clock()
        if abs(self.t)>2.1*EXPECTED_STEP_S:raise ContractFail("目标机不是新加载零时刻：t=%g；禁止在旧积分状态上重试。"%self.t)

    def get_param(self,key):return scalar(RtlabApi.GetParametersByName((self.param_paths[key],)))

    def set_param(self,key,value):
        if self.execute_attempted:raise ContractFail("第一次Execute后禁止在线改控制参数："+key)
        p=self.param_paths[key];before=self.get_param(key);self.written.append(("scalar",key,p,before))
        RtlabApi.SetParametersByName((p,),(float(value),));after=self.get_param(key)
        tol=0.1 if key.startswith("FileID") else max(1e-9,1e-8*max(abs(float(value)),1.0))
        if not almost(after,value,tol):raise ContractFail("参数回读不一致 %s: wanted=%r got=%r"%(key,value,after))
        self.expected[key]=float(value)

    def read_path_scalar(self,p):return scalar(RtlabApi.GetParametersByName((p,)))

    def set_path_scalar(self,p,value,label):
        if self.execute_attempted:raise ContractFail("第一次Execute后禁止在线改控制参数："+label)
        before=self.read_path_scalar(p);self.written.append(("path_scalar",label,p,before))
        RtlabApi.SetParametersByName((p,),(float(value),));after=self.read_path_scalar(p)
        if not almost(after,value,max(1e-9,1e-8*max(abs(float(value)),1.0))):
            raise ContractFail("%s回读不一致 path=%s wanted=%g got=%g"%(label,p,value,after))
        return after

    def setup(self):
        self.require_zero();self.take_controls()
        keys=list(self.param_paths);vals=RtlabApi.GetParametersByName(tuple(self.param_paths[k] for k in keys))
        # Current project scalar parameters are one value per requested path.
        self.param_before=dict(zip(keys,map(float,vals)))
        self.extra_before={"mode_sources_generic":[self.read_path_scalar(p) for p in self.mode_paths],
                           "restore_mode_source":self.read_path_scalar(self.restore_mode_path),
                           "approved_limits":[self.read_path_scalar(p) for p in self.limits_paths]}
        with open(os.path.join(self.run_dir,"parameters_before.json"),"w",encoding="utf-8") as f:
            json.dump({"scalar":self.param_before,"extra":self.extra_before},f,ensure_ascii=False,indent=2)

        # Total enable last. All configuration is written and read back BEFORE first Execute.
        self.set_param("CFG15_MASTER_ENABLE",0.0)
        late=["CFG_AA_enable","CFG_AA_blackstart_enable","CFG15_EXEC_S14","CFG15_MASTER_ENABLE"]
        for key,spec in EXPECTED_PARAMS.items():
            if key not in self.param_paths or key in late:continue
            val=self.file_id if key in ("FileID27","FileID29","FileID30") else spec["value"]
            self.set_param(key,val)
        # All five R2.2 Mode sources must be mode5 before first Execute.
        # The fifth source is the Restore Config input that controls Restore Executor hrOn.
        for i,p in enumerate(self.mode_paths):
            self.set_path_scalar(p,E2HH_MODE,"E2HH_MODE_GENERIC_%d"%(i+1))
        self.set_path_scalar(self.restore_mode_path,E2HH_MODE,"E2HH_MODE_RESTORE_CONFIG_5")
        # Small commissioning envelope for state60 primary coordination.
        # Each vector element is an indexed scalar RT-LAB parameter.
        for i,(pLim,vLim) in enumerate(zip(self.limits_paths,APPROVED_LIMITS)):
            self.set_path_scalar(pLim,vLim,"CFG_E2HH_APPROVED_LIMITS_%d"%(i+1))
        for key in late:self.set_param(key,EXPECTED_PARAMS[key]["value"])

        # Formal readback contract: five Mode sources must all be exactly 5 before first Execute.
        generic_mode_rb=[self.read_path_scalar(p) for p in self.mode_paths]
        restore_mode_rb=self.read_path_scalar(self.restore_mode_path)
        self.mode_readback={"generic":generic_mode_rb,"restore_config":restore_mode_rb}
        if len(generic_mode_rb)!=4 or any(not almost(v,E2HH_MODE,1e-12) for v in generic_mode_rb):
            raise ContractFail("四个通用E2HH Mode源回读不全为5：%r"%generic_mode_rb)
        if not almost(restore_mode_rb,E2HH_MODE,1e-12):
            raise ContractFail("Restore Config第五Mode源回读!=5：got=%r"%restore_mode_rb)
        gotlim=[self.read_path_scalar(p) for p in self.limits_paths]
        if len(gotlim)!=4 or any(not almost(a,b,1e-9) for a,b in zip(gotlim,APPROVED_LIMITS)):
            raise ContractFail("Approved limits indexed readback mismatch: %r"%gotlim)
        checks={"E2_DIAG_P_KP_RT":0.06,"E2_DIAG_P_KI_RT":0.5,"E2_DIAG_P_LOOP_ENABLE":1.0,
                "E2_DIAG_Q_LOOP_ENABLE":0.0,"E2_DIAG_DIRECT_IREF_ENABLE":0.0,
                "AA15_S14V2_CFG_PICKUP_TARGET_PU":TARGET_PU,
                "AA15_S14V2_CFG_ESS2_COORD_AUTH_PU":PRIMARY_AUTH_PU,
                "CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU":0.0005,"E2HH_NEXT_TARGET_PU":TARGET_PU}
        for k,v in checks.items():
            if not almost(self.get_param(k),v,1e-9):raise ContractFail("正式合同回读不一致：%s wanted=%g got=%g"%(k,v,self.get_param(k)))

        self.stop_before=scalar(RtlabApi.GetStopTime());RtlabApi.SetStopTime(60.0)
        if not almost(scalar(RtlabApi.GetStopTime()),60.0,1e-8):raise ContractFail("StopTime=60 s回读失败。")
        self.require_zero()
        self.log("正式配置PASS：五个Mode源均=5；P=-0.005 pu，Kp/Ki=0.06/0.5，Q/Direct/Secondary OFF。")
        self.log("Primary commissioning envelope: [%+.6f,%+.6f] pu, rate up/down %.6g/%.6g pu/s, authority %.6g pu"%
                 (APPROVED_LIMITS[0],APPROVED_LIMITS[1],APPROVED_LIMITS[2],APPROVED_LIMITS[3],PRIMARY_AUTH_PU))
        self.log("G27/G29/G30 FileID=%d；第一次Execute之后不再写任何控制参数。"%self.file_id)

    def restore_before_execute(self):
        if self.execute_attempted:return
        for typ,label,p,before in reversed(self.written):
            try:
                if typ in ("scalar","path_scalar"):
                    RtlabApi.SetParametersByName((p,),(float(before),))
            except Exception:pass
        if self.stop_before is not None:
            try:RtlabApi.SetStopTime(self.stop_before)
            except Exception:pass

    def read_signals(self):
        keys=list(self.signal_paths)+list(self.optional_paths)
        paths=[self.signal_paths[k] for k in self.signal_paths]+[self.optional_paths[k] for k in self.optional_paths]
        vals=RtlabApi.GetSignalsByName(tuple(paths))
        if len(vals)!=len(keys):raise ContractFail("在线信号批量读取长度不一致。")
        return dict(zip(keys,map(float,vals)))

    def run_to(self,target):
        state,raw=split_state()
        if state!=RtlabApi.MODEL_PAUSED:raise ContractFail("每段必须从暂停开始：%r"%(raw,))
        target=round(float(target)/EXPECTED_STEP_S)*EXPECTED_STEP_S;before=self.read_clock()
        if target<=before+0.25*EXPECTED_STEP_S:return
        RtlabApi.SetPauseTime(target)
        if not almost(scalar(RtlabApi.GetPauseTime()),target,EXPECTED_STEP_S):raise ContractFail("PauseTime回读失败。")
        self.execute_attempted=True;RtlabApi.Execute(1.0)
        deadline=time.monotonic()+max(25.0,5.0*(target-before)+8.0)
        while time.monotonic()<deadline:
            state,raw=split_state()
            if state==RtlabApi.MODEL_PAUSED:
                got=self.read_clock()
                if got>=target-2.01*EXPECTED_STEP_S and got<=target+1.01*EXPECTED_STEP_S:self.t=got;return
            time.sleep(0.005)
        raise ContractFail("未取得预期Pause确认；保留已生成MAT，不自动Reset。")

    def _mark_once(self,key,condition,kind,**kw):
        if condition and key not in self.event_times:self.event(kind,**kw)

    def sample(self,tag):
        s=self.read_signals();t=self.read_clock();self.t=t
        row={"target_clock_s":t,"tag":tag};row.update(s);self.observations.append(row)
        rs=int(round(s.get("restore_state_z",float("nan")))) if math.isfinite(s.get("restore_state_z",float("nan"))) else -999
        sub=s.get("s14_substate",float("nan"));beta=s.get("handover_beta",float("nan"));cg=s.get("correction_gain",float("nan"))
        p=s.get("ess2_pmeas_pu",float("nan"));v=s.get("ess2_vpu",float("nan"));pf=s.get("p_final_applied_pu",float("nan"))
        self.log("t=%7.3f | S14=%s Restore=%s fail=%s | beta=%s corr=%s | V=%.4f P=%+.5f Pcmd=%s"%
                 (t,"?" if not math.isfinite(sub) else "%d"%round(sub),rs,s.get("restore_fail_code_z",float("nan")),
                  "?" if not math.isfinite(beta) else "%.3f"%beta,"?" if not math.isfinite(cg) else "%.3f"%cg,
                  v,p,"?" if not math.isfinite(pf) else "%+.5f"%pf))
        self.observe_contract(s)
        self._mark_once("FIRST_RESTORE_STATE6",rs==6,"FIRST_RESTORE_STATE6")
        self._mark_once("FIRST_RESTORE_STATE7",rs==7,"FIRST_RESTORE_STATE7")
        if math.isfinite(sub):
            self._mark_once("FIRST_S14_STATE40",round(sub)==40,"FIRST_S14_STATE40")
            self._mark_once("FIRST_S14_STATE50",round(sub)==50,"FIRST_S14_STATE50_HANDOVER")
            self._mark_once("FIRST_S14_STATE60",round(sub)==60,"FIRST_S14_STATE60_PRIMARY")
        if math.isfinite(beta):
            self._mark_once("FIRST_BETA_NONZERO",beta>1e-3,"FIRST_HANDOVER_BETA_NONZERO",beta=beta)
            self._mark_once("FIRST_BETA_FULL",beta>=0.999,"FIRST_HANDOVER_BETA_FULL",beta=beta)
        if math.isfinite(cg):
            self._mark_once("FIRST_CORRECTION_NONZERO",cg>1e-3,"FIRST_PRIMARY_GAIN_NONZERO",gain=cg)
            self._mark_once("FIRST_CORRECTION_FULL",cg>=0.999,"FIRST_PRIMARY_GAIN_FULL",gain=cg)
        if math.isfinite(pf):
            self._mark_once("FIRST_PRIMARY_COMMAND_MOVEMENT",
                            "FIRST_S14_STATE60" in self.event_times and abs(pf-TARGET_PU)>1e-5,
                            "FIRST_PRIMARY_COMMAND_MOVEMENT",p_final=pf)
        return s

    def observe_contract(self,s):
        # Host intentionally does not stop on waveform/qualification deviations. It records them.
        essential=["Freq_Hz","Vab_rms_true_V","restore_state_z","restore_fail_code_z","ess2_pmeas_pu","ess2_vpu"]
        bad=[k for k in essential if not math.isfinite(s.get(k,float("nan")))]
        if bad and not self.contract_flags["nonfinite_seen"]:
            self.contract_flags["nonfinite_seen"]=True;self.event("ONLINE_NONFINITE_OBSERVED",signals=bad)
        fail=s.get("restore_fail_code_z",0.0);rs=s.get("restore_state_z",0.0)
        if (math.isfinite(fail) and fail>0.5) or (math.isfinite(rs) and round(rs)==9):
            if not self.contract_flags["model_fail_seen"]:
                self.contract_flags["model_fail_seen"]=True;self.event("MODEL_RESTORE_FAILURE_REPORTED",state=rs,fail=fail)
        if self.t>=1.0:
            em=s.get("executed_mode",float("nan"))
            if math.isfinite(em) and not almost(em,4,0.1) and not self.contract_flags["wrong_mode_seen"]:
                self.contract_flags["wrong_mode_seen"]=True;self.event("EXECUTED_MODE_CONTRACT_BREACH",value=em)
            j1=s.get("J1_applied_close",float("nan"))
            if math.isfinite(j1) and j1>0.5 and not self.contract_flags["j1_closed_seen"]:
                self.contract_flags["j1_closed_seen"]=True;self.event("J1_UNEXPECTED_CLOSE",value=j1)
            gfm=s.get("ESS1_final_droop",float("nan"));g3=s.get("GridOn_3_ESS1",float("nan"))
            if ((math.isfinite(gfm) and gfm<0.5) or (math.isfinite(g3) and g3>0.5)) and not self.contract_flags["ess1_role_lost_seen"]:
                self.contract_flags["ess1_role_lost_seen"]=True;self.event("ESS1_GFM_ROLE_CONTRACT_BREACH",droop=gfm,gridOn=g3)
        se=s.get("secondary_enable",float("nan"))
        if math.isfinite(se) and abs(se)>1e-6 and not self.contract_flags["secondary_seen"]:
            self.contract_flags["secondary_seen"]=True;self.event("UNEXPECTED_SECONDARY_ENABLE",value=se)

    def formal_run(self):
        # No transparent regression. One formal 58 s capture from fresh Load.
        #
        # IMPORTANT R2 fix:
        # Do NOT use `while self.t < 58` because a valid 100-us target run may
        # report 57.9999 s after the single planned 58-s Pause. The old loop
        # interpreted that as "not yet 58" and issued one unnecessary extra
        # Execute. Use a one-shot absolute timeline instead: each target appears once.
        checkpoints=[0.5,1.0,2.0,4.0,5.5,6.0,8.0,10.0,12.0]
        n=int(round((MAX_TARGET_CLOCK_S-12.5)/SAMPLE_STEP_S))+1
        checkpoints += [12.5 + SAMPLE_STEP_S*i for i in range(n)]
        checkpoints=sorted(set(round(x,10) for x in checkpoints if x<=MAX_TARGET_CLOCK_S+1e-12))
        for x in checkpoints:
            if x>self.t+0.25*EXPECTED_STEP_S:
                self.run_to(x)
                self.sample("FORMAL")
        if self.t < MAX_TARGET_CLOCK_S-2.01*EXPECTED_STEP_S:
            raise ContractFail("正式记录未到58 s容差窗口：target_clock=%g"%self.t)
        reached50="FIRST_S14_STATE50" in self.event_times
        reached60="FIRST_S14_STATE60" in self.event_times
        self.status="CAPTURE_COMPLETE_58S_NO_HOST_ELECTRICAL_VERDICT"
        self.reason=("58 s正式记录完成；在线可选S14/beta/corr信号若未暴露，不作为未接管判据，"
                     "最终以G29 DirectMAT为准。普通波动/振荡不由Runner判停。")
        self.event("PLANNED_58S_CAPTURE_COMPLETE",state50_online=reached50,state60_online=reached60,
                   terminal_clock=self.t)

    def preserve_pause(self):
        if not self.execute_attempted:return
        try:
            state,raw=split_state()
            if state!=RtlabApi.MODEL_PAUSED:
                RtlabApi.Pause();deadline=time.monotonic()+10.0
                while time.monotonic()<deadline:
                    state,raw=split_state()
                    if state==RtlabApi.MODEL_PAUSED:break
                    time.sleep(0.01)
            if state==RtlabApi.MODEL_PAUSED:self.t=self.read_clock()
        except Exception as e:
            msg="末端Pause状态确认警告（不改写已完成的58 s数据状态）：%r"%e
            self.host_warnings.append(msg);self.log(msg)

    def write_outputs(self):
        keys=[]
        for r in self.observations:
            for k in r:
                if k not in keys:keys.append(k)
        with open(os.path.join(self.run_dir,"online_snapshots.csv"),"w",encoding="utf-8-sig",newline="") as f:
            w=csv.DictWriter(f,fieldnames=keys);w.writeheader();[w.writerow(r) for r in self.observations]
        manifest={
            "version":VERSION,"case":CASE_NAME,"case_title":CASE_TITLE,"status":self.status,"reason":self.reason,
            "target_clock_s":self.t,"execute_attempted":self.execute_attempted,"file_id":self.file_id,
            "target_pu":TARGET_PU,"mode":E2HH_MODE,"mode_source_count":5,
            "mode_readback_before_execute":self.mode_readback,
            "primary_auth_pu":PRIMARY_AUTH_PU,
            "approved_limits":list(APPROVED_LIMITS),"power_base_W":100000,
            "event_times":self.event_times,"contract_flags":self.contract_flags,
            "first_state6_s":self.event_times.get("FIRST_RESTORE_STATE6"),
            "first_state7_s":self.event_times.get("FIRST_RESTORE_STATE7"),
            "first_state40_s":self.event_times.get("FIRST_S14_STATE40"),
            "first_state50_s":self.event_times.get("FIRST_S14_STATE50"),
            "first_beta_nonzero_s":self.event_times.get("FIRST_BETA_NONZERO"),
            "first_beta_full_s":self.event_times.get("FIRST_BETA_FULL"),
            "first_state60_s":self.event_times.get("FIRST_S14_STATE60"),
            "first_correction_nonzero_s":self.event_times.get("FIRST_CORRECTION_NONZERO"),
            "first_correction_full_s":self.event_times.get("FIRST_CORRECTION_FULL"),
            "first_primary_command_movement_s":self.event_times.get("FIRST_PRIMARY_COMMAND_MOVEMENT"),
            "expected_mat_files":{"G27":"base_power_r1_g27_%d.mat"%self.file_id,
                                  "G29":"base_power_r1_g29_%d.mat"%self.file_id,
                                  "G30":"base_power_r1_g30_%d.mat"%self.file_id},
            "expected_rows_with_time":{"G27":120,"G29":95,"G30":145},
            "controller_contract":{"P_Kp":0.06,"P_Ki":0.5,"P_loop":1,"Q_loop":0,"direct_current":0,
                                   "secondary":0,"support_actual":0},
            "runner_policy":"first Execute after all writes; no control parameter writes after Execute; ordinary waveform deviations record-only",
            "mandatory_signal_paths":self.signal_paths,"optional_signal_paths":self.optional_paths,
            "parameter_paths":self.param_paths,
            "mode_paths_generic":self.mode_paths,
            "restore_mode_path":self.restore_mode_path,
            "all_mode_paths":self.mode_paths+[self.restore_mode_path],
            "limits_paths":self.limits_paths,
            "host_warnings":self.host_warnings
        }
        with open(os.path.join(self.run_dir,"manifest.json"),"w",encoding="utf-8") as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
        self.log("结果目录："+self.run_dir);self.log("最终Runner状态："+self.status)
        self.log("保持PAUSED，不要Reset。现在运行配套MATLAB DirectMAT脚本。")

    def main(self):
        self.log("ESS2正式健康恢复/接管/Primary一体时序试验；无透明回归。")
        self.log("输出目录："+self.run_dir)
        try:
            connect_exact_model(self.log);self.discover();self.setup();self.formal_run()
        except (Exception,KeyboardInterrupt) as e:
            self.status="FAILED_AFTER_EXECUTE" if self.execute_attempted else "BLOCKED_BEFORE_EXECUTE";self.reason=repr(e)
            self.log("停止：%r"%e)
            with open(os.path.join(self.run_dir,"traceback.txt"),"w",encoding="utf-8") as f:f.write(traceback.format_exc())
            if not self.execute_attempted:self.restore_before_execute()
        finally:
            if self.execute_attempted:self.preserve_pause()
            self.release_controls();self.write_outputs();self.logf.close()
        return {"status":self.status,"reason":self.reason,"run_dir":self.run_dir}

if __name__=="__main__":
    Runner().main()
