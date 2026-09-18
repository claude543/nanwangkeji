# -*- coding: utf-8 -*-
r"""
RUN_K26_K50_ESS2_BASE_POWER_OBSERVE_R3.py
======================================

当前 Build 已成功后的正式单轮试验脚本（精简版）。
不做透明回归，不重复改模，不在线扫增益，不手工推进 Stage/COMMIT/RELEASE。
模型自己完成：
ESS1 建网 -> ESS2 准备/同期/真实合闸 -> state35 零目标基础控制开放
-> state40 0→-0.005 pu -> 固定平台观察约30 s -> state45 等待受控暂停。

本轮是诊断观察，不要求 state7/pickupOK/V/f/I/P 健康资格作为继续运行条件。

与上一版正式 Runner 的关键区别：
1) 不再要求 352 个记录通道全部能被 RT-LAB 在线信号接口暴露。
   记录通道以最终 MAT 为准；在线只读取此前成熟 Runner 已证明可读的必要信号。
2) 不做运行前 2.2 s 文件切换/回传门槛，不因为文件 I/O 先阻断电气试验。
3) 不把普通 V/f/I/P 波动、CurrentLimit 或调制度变化当成 host 侧失败。
   这些全部记录，最终由 G27/G29/G30 MAT 判断。
4) host 只响应：NaN/Inf、模型/RT-LAB合同失效、意外协调器接管、模型明确的结构性失败。
5) 单文件运行；不需要 RUN_CONTRACT.json / schemas 等伴随文件。

操作：
人工 Reset -> Load once -> MODEL_PAUSED @ t≈0；不要手工 Execute。
然后运行本文件。运行结束后不要 Reset，先保存/上传 G27/G29/G30 MAT。
"""
import os, sys, re, csv, json, math, time, traceback
from datetime import datetime

import RtlabApi

VERSION = "ESS2_BASE_POWER_OBSERVE_R3_20260916"
PROJECT_KEY = "yanshou_V7"
MODEL_KEY = "K26_K50_CLEAN_P1"
EXPECTED_STEP_S = 1e-4
MODEL_ROOT = r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\models\K26_K50_CLEAN_P1"
MODEL_FILE = os.path.join(MODEL_ROOT, MODEL_KEY + ".slx")
PROJECT_FILE = r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\yanshou_V7.llp"

TARGET_PU = -0.005
MAX_RUN_S = 90.0
POST_STATE6_OBSERVE_S = 40.0
SAMPLE_STEP_S = 0.5


EXPECTED_PARAMS = {'CFG_GATEA_ENABLE': {'leaf': 'CFG_GATEA_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_GATEA_FREF_HZ': {'leaf': 'CFG_GATEA_FREF_HZ', 'property': 'Value', 'value': 50.0, 'required': True}, 'CFG15_MASTER_ENABLE': {'leaf': 'CFG15_MASTER_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_CONTROL_SOURCE': {'leaf': 'CFG15_CONTROL_SOURCE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_P_OBJECTIVE_MODE': {'leaf': 'CFG15_P_OBJECTIVE_MODE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S01': {'leaf': 'CFG15_EXEC_S01', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S02': {'leaf': 'CFG15_EXEC_S02', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S03': {'leaf': 'CFG15_EXEC_S03', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S04': {'leaf': 'CFG15_EXEC_S04', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S05': {'leaf': 'CFG15_EXEC_S05', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S06': {'leaf': 'CFG15_EXEC_S06', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S07': {'leaf': 'CFG15_EXEC_S07', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S08': {'leaf': 'CFG15_EXEC_S08', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S09': {'leaf': 'CFG15_EXEC_S09', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S10': {'leaf': 'CFG15_EXEC_S10', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S11': {'leaf': 'CFG15_EXEC_S11', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S12': {'leaf': 'CFG15_EXEC_S12', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S13': {'leaf': 'CFG15_EXEC_S13', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_EXEC_S14': {'leaf': 'CFG15_EXEC_S14', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_EXEC_S15': {'leaf': 'CFG15_EXEC_S15', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_MODE_ACTUATION_ENABLE': {'leaf': 'CFG15_MODE_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_PCC_BREAKER_ACTUATION_ENABLE': {'leaf': 'CFG15_PCC_BREAKER_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_DIAG_MODE_BREAKER_DECOUPLE': {'leaf': 'CFG15_DIAG_MODE_BREAKER_DECOUPLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG15_ISLAND_MASTER': {'leaf': 'CFG15_ISLAND_MASTER', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_BLACKSTART_MASTER': {'leaf': 'CFG15_BLACKSTART_MASTER', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE': {'leaf': 'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG15_S15_RECOVERY_REQUEST': {'leaf': 'CFG15_S15_RECOVERY_REQUEST', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_AA_enable': {'leaf': 'CFG_AA_enable', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_AA_blackstart_enable': {'leaf': 'CFG_AA_blackstart_enable', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_AA_tie_target_kW': {'leaf': 'CFG_AA_tie_target_kW', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_AA_v_nom_V': {'leaf': 'CFG_AA_v_nom_V', 'property': 'Value', 'value': 10000.0, 'required': True}, 'CFG_AA_island_freq_dev_Hz': {'leaf': 'CFG_AA_island_freq_dev_Hz', 'property': 'Value', 'value': 0.5, 'required': True}, 'CFG_AA_island_v_dev_pu': {'leaf': 'CFG_AA_island_v_dev_pu', 'property': 'Value', 'value': 0.1, 'required': True}, 'AA15_COMM_OK': {'leaf': 'AA15_COMM_OK', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_AC_CONNECT_PV1': {'leaf': 'CFG_DIAG_AC_CONNECT_PV1', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_AC_CONNECT_PV2': {'leaf': 'CFG_DIAG_AC_CONNECT_PV2', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_AC_CONNECT_ESS2': {'leaf': 'CFG_DIAG_AC_CONNECT_ESS2', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_AC_CONNECT_EV1': {'leaf': 'CFG_DIAG_AC_CONNECT_EV1', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_AC_CONNECT_EV2': {'leaf': 'CFG_DIAG_AC_CONNECT_EV2', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE': {'leaf': 'CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_DIAG_P_SCALE_PV1': {'leaf': 'CFG_DIAG_P_SCALE_PV1', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_P_SCALE_PV2': {'leaf': 'CFG_DIAG_P_SCALE_PV2', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_P_SCALE_ESS2': {'leaf': 'CFG_DIAG_P_SCALE_ESS2', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_P_SCALE_EV1': {'leaf': 'CFG_DIAG_P_SCALE_EV1', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_P_SCALE_EV2': {'leaf': 'CFG_DIAG_P_SCALE_EV2', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_Q_SCALE_PV1': {'leaf': 'CFG_DIAG_Q_SCALE_PV1', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_Q_SCALE_PV2': {'leaf': 'CFG_DIAG_Q_SCALE_PV2', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_Q_SCALE_ESS2': {'leaf': 'CFG_DIAG_Q_SCALE_ESS2', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_Q_SCALE_EV1': {'leaf': 'CFG_DIAG_Q_SCALE_EV1', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_DIAG_Q_SCALE_EV2': {'leaf': 'CFG_DIAG_Q_SCALE_EV2', 'property': 'Value', 'value': 1.0, 'required': True}, 'F1_FILTER_MODE': {'leaf': 'F1_FILTER_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F1_AD_ENABLE': {'leaf': 'F1_AD_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F1_K_AD': {'leaf': 'F1_K_AD', 'property': 'Value', 'value': 0.0, 'required': True}, 'F2_FAST_FB_MODE': {'leaf': 'F2_FAST_FB_MODE', 'property': 'Value', 'value': 2.0, 'required': True}, 'F2_IL_SIGN': {'leaf': 'F2_IL_SIGN', 'property': 'Value', 'value': 1.0, 'required': True}, 'F2_RFF_LOCAL': {'leaf': 'F2_RFF_LOCAL', 'property': 'Value', 'value': 0.0015, 'required': True}, 'F2_LFF_LOCAL': {'leaf': 'F2_LFF_LOCAL', 'property': 'Value', 'value': 0.125, 'required': True}, 'F2_PHASE_LOCAL_RAD': {'leaf': 'F2_PHASE_LOCAL_RAD', 'property': 'Value', 'value': 0.0, 'required': True}, 'F3_VREG_STATE_MODE': {'leaf': 'F3_VREG_STATE_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F4_ANGLE_SYNC_MODE': {'leaf': 'F4_ANGLE_SYNC_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F4_SYNC_OFFSET_RAD': {'leaf': 'F4_SYNC_OFFSET_RAD', 'property': 'Value', 'value': -2.0943951023931953, 'required': True}, 'F6_SHAPED_AD_ENABLE': {'leaf': 'F6_SHAPED_AD_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F6_SHAPED_AD_MODE': {'leaf': 'F6_SHAPED_AD_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F6_SHAPED_AD_GAIN': {'leaf': 'F6_SHAPED_AD_GAIN', 'property': 'Gain', 'value': 0.0, 'required': True}, 'F6_SHAPED_AD_SIGN': {'leaf': 'F6_SHAPED_AD_SIGN', 'property': 'Gain', 'value': -1.0, 'required': True}, 'F8_ENABLE': {'leaf': 'F8_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F8_IOUT_GAIN': {'leaf': 'F8_IOUT_GAIN', 'property': 'Gain', 'value': -1.0, 'required': True}, 'F8_CAP_GAIN': {'leaf': 'F8_CAP_GAIN', 'property': 'Value', 'value': 1.0, 'required': True}, 'F8_BC_PU': {'leaf': 'F8_BC_PU', 'property': 'Value', 'value': 0.05, 'required': True}, 'F8_IOUT_FILTER_MODE': {'leaf': 'F8_IOUT_FILTER_MODE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F9_VREG_MAP_MODE': {'leaf': 'F9_VREG_MAP_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F10_INNER_VRAW_MODE': {'leaf': 'F10_INNER_VRAW_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F10_INNER_IRAW_MODE': {'leaf': 'F10_INNER_IRAW_MODE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F20_IOUT_MODE': {'leaf': 'F20_IOUT_MODE', 'property': 'Value', 'value': 1.0, 'required': True}, 'F20_IOUT_RELEASE_TIME_S': {'leaf': 'F20_IOUT_RELEASE_TIME_S', 'property': 'Value', 'value': 6.2, 'required': True}, 'F20_V2_ENABLE': {'leaf': 'F20_V2_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F20_V2_CAPTURE_REQ': {'leaf': 'F20_V2_CAPTURE_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F20_V2_CLEAR_REQ': {'leaf': 'F20_V2_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F21_CURRENT_PI_RESET_ENABLE': {'leaf': 'F21_CURRENT_PI_RESET_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F22_ENABLE': {'leaf': 'F22_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F22_HANDOVER_MODE': {'leaf': 'F22_HANDOVER_MODE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F22_SUPPORT_ENABLE': {'leaf': 'F22_SUPPORT_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F22_SUPPORT_GAIN': {'leaf': 'F22_SUPPORT_GAIN', 'property': 'Value', 'value': 0.0, 'required': True}, 'F23_ENABLE': {'leaf': 'F23_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F23_ARM': {'leaf': 'F23_ARM', 'property': 'Value', 'value': 0.0, 'required': True}, 'F23_COMMIT_REQ': {'leaf': 'F23_COMMIT_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F23_CLEAR_REQ': {'leaf': 'F23_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F24_ENABLE': {'leaf': 'F24_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F24_ARM': {'leaf': 'F24_ARM', 'property': 'Value', 'value': 0.0, 'required': True}, 'F24_RELEASE_ENABLE': {'leaf': 'F24_RELEASE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F24_CLEAR_REQ': {'leaf': 'F24_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F25_ENABLE': {'leaf': 'F25_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'F25_PREPARE_ARM': {'leaf': 'F25_PREPARE_ARM', 'property': 'Value', 'value': 0.0, 'required': True}, 'F25_PREPARE_COMMIT_REQ': {'leaf': 'F25_PREPARE_COMMIT_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F25_EDGE_ARM_REQ': {'leaf': 'F25_EDGE_ARM_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'F25_CLEAR_REQ': {'leaf': 'F25_CLEAR_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_PLAN_COMMIT_ENABLE': {'leaf': 'CFG_PLAN_COMMIT_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_PLAN_COMMIT_HOLD_REQ': {'leaf': 'CFG_PLAN_COMMIT_HOLD_REQ', 'property': 'Value', 'value': 0.0, 'required': True}, 'AA15_FINAL_SYSTEM_STAGE': {'property': 'Value', 'value': 0.0, 'required': True, 'path': 'SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_SYSTEM_STAGE'}, 'AA15_S14V2_CFG_PICKUP_TARGET_PU': {'leaf': 'AA15_S14V2_CFG_PICKUP_TARGET_PU', 'property': 'Value', 'value': -0.005, 'required': True}, 'AA15_S14V2_CFG_ESS2_COORD_AUTH_PU': {'leaf': 'AA15_S14V2_CFG_ESS2_COORD_AUTH_PU', 'property': 'Value', 'value': 0.01, 'required': True}, 'CFG_ESS2_RESTORE_MASTER_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_MASTER_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_CONTROL_SOURCE': {'leaf': 'CFG_ESS2_RESTORE_CONTROL_SOURCE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_MANUAL_REQUEST': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_REQUEST', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_MANUAL_COMMIT': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_COMMIT', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_MANUAL_RELEASE': {'leaf': 'CFG_ESS2_RESTORE_MANUAL_RELEASE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_ESS2_RESTORE_V_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_V_MIN_PU', 'property': 'Value', 'value': 0.9, 'required': True}, 'CFG_ESS2_RESTORE_V_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_V_MAX_PU', 'property': 'Value', 'value': 1.1, 'required': True}, 'CFG_ESS2_RESTORE_DF_MAX_HZ': {'leaf': 'CFG_ESS2_RESTORE_DF_MAX_HZ', 'property': 'Value', 'value': 0.5, 'required': True}, 'CFG_ESS2_RESTORE_IREF_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_IREF_MAX_PU', 'property': 'Value', 'value': 0.05, 'required': True}, 'CFG_ESS2_RESTORE_IMEAS_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_IMEAS_MAX_PU', 'property': 'Value', 'value': 0.05, 'required': True}, 'CFG_ESS2_RESTORE_HEADROOM_MIN': {'leaf': 'CFG_ESS2_RESTORE_HEADROOM_MIN', 'property': 'Value', 'value': 0.05, 'required': True}, 'CFG_ESS2_RESTORE_READY_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_READY_DWELL_S', 'property': 'Value', 'value': 0.5, 'required': True}, 'CFG_ESS2_RESTORE_POST_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_POST_DWELL_S', 'property': 'Value', 'value': 0.2, 'required': True}, 'CFG_ESS2_RESTORE_RELEASE_RAMP_S': {'leaf': 'CFG_ESS2_RESTORE_RELEASE_RAMP_S', 'property': 'Value', 'value': 2.0, 'required': True}, 'CFG_ESS2_RESTORE_PHASE_GATE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_PHASE_GATE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_PHASE_COS_MIN': {'leaf': 'CFG_ESS2_RESTORE_PHASE_COS_MIN', 'property': 'Value', 'value': 0.984807753012208, 'required': True}, 'CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN': {'leaf': 'CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_VRATIO_MIN': {'leaf': 'CFG_ESS2_RESTORE_VRATIO_MIN', 'property': 'Value', 'value': 0.95, 'required': True}, 'CFG_ESS2_RESTORE_VRATIO_MAX': {'leaf': 'CFG_ESS2_RESTORE_VRATIO_MAX', 'property': 'Value', 'value': 1.05, 'required': True}, 'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE': {'leaf': 'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE', 'property': 'Value', 'value': 0.0, 'required': True}, 'CFG_ESS2_RESTORE_POST_I_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_I_MAX_PU', 'property': 'Value', 'value': 0.2, 'required': True}, 'CFG_ESS2_RESTORE_POST_V_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_V_MIN_PU', 'property': 'Value', 'value': 0.8, 'required': True}, 'CFG_ESS2_RESTORE_POST_V_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_POST_V_MAX_PU', 'property': 'Value', 'value': 1.2, 'required': True}, 'CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN': {'leaf': 'CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN', 'property': 'Value', 'value': 1.0, 'required': True}, 'CFG_ESS2_RESTORE_FNOM_HZ': {'leaf': 'CFG_ESS2_RESTORE_FNOM_HZ', 'property': 'Value', 'value': 50.0, 'required': True}, 'CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S', 'property': 'Value', 'value': 2.0, 'required': True}, 'CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU', 'property': 'Value', 'value': 0.0045, 'required': True}, 'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU', 'property': 'Value', 'value': 0.002, 'required': True}, 'CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S': {'leaf': 'CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S', 'property': 'Value', 'value': 3.0, 'required': True}, 'F7_VFF_GAIN': {'leaf': 'F7_VFF_GAIN', 'property': 'Gain', 'value': 1.0, 'required': False}, 'F11_CURRENT_REF_TEST_ENABLE': {'leaf': 'F11_CURRENT_REF_TEST_ENABLE', 'property': 'Value', 'value': 0.0, 'required': False}, 'F12_VFF_NOTCH_MODE': {'leaf': 'F12_VFF_NOTCH_MODE', 'property': 'Value', 'value': 0.0, 'required': False}, 'CFG_AA_switch_enable': {'leaf': 'CFG_AA_switch_enable', 'property': 'Value', 'value': 0.0, 'required': False}, 'CFG_ESS2_RESTORE_TS': {'leaf': 'CFG_ESS2_RESTORE_TS', 'property': 'Value', 'value': 0.0001, 'required': False}, 'DiagMasterRecord': {'path': 'SM_Master/AA15_BASETEST_ENABLE', 'property': 'Value', 'value': 1, 'required': True}, 'DiagSlaveRecord': {'path': 'SS_Slave2/AA15_BASETEST_ENABLE', 'property': 'Value', 'value': 1, 'required': True}, 'TargetSlaveRecord': {'path': 'SS_Slave2/AA15_BASETEST_TARGET_PU', 'property': 'Value', 'value': -0.005, 'required': True}, 'FileID27': {'path': 'SS_Slave2/AA15_BASETEST_G27_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True}, 'FileID29': {'path': 'SM_Master/AA15_BASETEST_G29_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True}, 'FileID30': {'path': 'SS_Slave2/AA15_BASETEST_G30_FILE_ID', 'property': 'Value', 'value': None, 'required': True, 'recording_only': True}}

MANDATORY_SIGNALS = {'Ppcc_kW': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain/port1', 'Qpcc_kvar': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain1/port1', 'Freq_Hz': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Saturation1/port1', 'Vab_rms_true_V': 'K26_K50_CLEAN_P1/SM_Master/J2_PCC_Measurements/Gain3/port1', 'J1_applied_close': 'K26_K50_CLEAN_P1/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_GATEA_J1_FORCE_OPEN_SWITCH/port1', 'executed_mode': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Grid_Mode_Execution_Manager/AA15_Grid_Mode_Execution_Core/port1', 'ESS1_final_droop': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port3', 'GridOn_1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port7', 'GridOn_2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port8', 'GridOn_3_ESS1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port9', 'GridOn_4': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port10', 'GridOn_5': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port11', 'GridOn_6': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port12', 'restore_state_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(1)', 'restore_ready_count_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(2)', 'restore_post_count_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(3)', 'restore_alpha_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(4)', 'restore_fail_code_z': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(5)', 'ess2_final_idref': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(3)', 'ess2_final_iqref': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(4)', 'ess2_idmeas': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(5)', 'ess2_iqmeas': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(6)', 'ess2_mod_index': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(15)', 'ess2_pmeas_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(16)', 'ess2_qmeas_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(17)', 'ess2_pll_hz': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(19)', 'ess2_vpu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(21)', 'ess2_pref_eff_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(26)', 'ess2_qref_eff_pu': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(28)', 'ess2_current_limit': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(35)', 'ess2_master_f_hz': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(37)', 'ess2_raw_mod_demand': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(42)', 'ess2_mod_headroom': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(43)', 'ESS2_final_breaker_cmd': 'K26_K50_CLEAN_P1/SS_Slave2/AA15_ESS2_RESTORE_BREAKER_ROUTER/port1', 'Pcmd_1_PV1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_1/port1', 'Pcmd_2_PV2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_2/port1', 'Pcmd_3_ESS1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_3/port1', 'Pcmd_4_ESS2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_4/port1', 'Pcmd_5_EV1': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_5/port1', 'Pcmd_6_EV2': 'K26_K50_CLEAN_P1/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_6/port1'}
OPTIONAL_SIGNALS = {'ESS1_Fout_direct': 'K26_K50_CLEAN_P1/SS_Slave2/ESS1_Control/Droop Control/Fout/port1', 's14_substate': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_SUBSTATE/port1', 's14_coarse_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_COARSE/port1', 's14_elapsed_s': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_ELAPSED/port1', 's14_restore_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_RESTORE_STAGE/port1', 's14_coord_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_COORD_STAGE/port1', 's14_gfl_stage': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_GFL_STAGE/port1', 's14_pickup_enable': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_PICKUP_ENABLE/port1', 's14_owner_request': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_OWNER_REQUEST/port1', 'p_s14_ramped_pu': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port2', 'p_coord_raw_pu': 'K26_K50_CLEAN_P1/SM_Master/P3_FROM_002_01/port1', 'p_final_applied_pu': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port1', 'handover_beta': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port3', 'ess2_available': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_AVAILABLE/port1', 'correction_gain': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_CORRECTION_GAIN/port1', 'secondary_enable': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_SECONDARY/port1', 's14_active': 'K26_K50_CLEAN_P1/SM_Master/AA15_S14V2_G29_ACTIVE/port1'}

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
        self.run_dir=os.path.join(root,"observe_"+self.stamp)
        os.makedirs(self.run_dir,exist_ok=False)
        self.logf=open(os.path.join(self.run_dir,"run.txt"),"w",encoding="utf-8",buffering=1)
        self.param_paths={}
        self.signal_paths={}
        self.optional_paths={}
        self.param_before={}
        self.expected={}
        self.written=[]
        self.clock=None
        self.t=0.0
        self.execute_attempted=False
        self.sys_ctrl=False
        self.par_ctrl=False
        self.observations=[]
        self.events=[]
        self.first_state6=None
        self.file_id=int(time.time()*1000)%1000000000
        self.status="CREATED"
        self.reason=""
        self.stop_before=None

    def log(self,s=""):
        text=str(s)
        print(text);sys.stdout.flush()
        self.logf.write(text+"\n");self.logf.flush()

    def event(self,kind,**kw):
        row={"event":kind,"target_clock_s":self.t,"host_time":datetime.now().isoformat()}
        row.update(kw);self.events.append(row)
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
        if not math.isfinite(v):
            raise ContractFail("目标时钟无效。")
        return v

    def discover(self):
        pdesc=list(RtlabApi.GetParametersDescription())
        srows=signal_rows()

        missing=[]
        for key,spec in EXPECTED_PARAMS.items():
            p=resolve_parameter(pdesc,spec)
            if p is None:
                if spec.get("required",True):
                    missing.append("parameter:"+key)
            else:
                self.param_paths[key]=p

        for key,path in MANDATORY_SIGNALS.items():
            p=resolve_signal(srows,path)
            if p is None:
                missing.append("signal:"+key)
            else:
                try:
                    scalar(RtlabApi.GetSignalsByName((p,)))
                    self.signal_paths[key]=p
                except Exception as e:
                    missing.append("signal:%s(%r)"%(key,e))

        for key,path in OPTIONAL_SIGNALS.items():
            p=resolve_signal(srows,path)
            if p is not None:
                try:
                    scalar(RtlabApi.GetSignalsByName((p,)))
                    self.optional_paths[key]=p
                except Exception:
                    pass

        for cand in [MODEL_KEY+"/SM_Master/Clock/port1",
                     MODEL_KEY+"/SM_Master/Board_HB_Time/port1",
                     MODEL_KEY+"/SM_Master/Clock1/port1"]:
            p=resolve_signal(srows,cand)
            if p:
                try:
                    scalar(RtlabApi.GetSignalsByName((p,)))
                    self.clock=p;break
                except Exception:
                    pass
        if self.clock is None:
            missing.append("target_clock")

        with open(os.path.join(self.run_dir,"discovery.json"),"w",encoding="utf-8") as f:
            json.dump({"mandatory":self.signal_paths,"optional":self.optional_paths,
                       "parameters":self.param_paths,"missing":missing},f,ensure_ascii=False,indent=2)
        if missing:
            raise ContractFail("精简脚本仍有必要接口未找到：%r"%missing)
        self.log("接口发现完成：参数%d，必要在线信号%d，可选在线信号%d。"
                 %(len(self.param_paths),len(self.signal_paths),len(self.optional_paths)))

    def require_zero(self):
        state,raw=split_state()
        if state!=RtlabApi.MODEL_PAUSED:
            raise ContractFail("请人工 Reset->Load once 后保持 MODEL_PAUSED；实际=%r"% (raw,))
        dt,factor=RtlabApi.GetTimeInfo()
        if not almost(dt,EXPECTED_STEP_S,1e-10):
            raise ContractFail("目标步长不是100微秒：%r"%dt)
        self.t=self.read_clock()
        if abs(self.t)>2.1*EXPECTED_STEP_S:
            raise ContractFail("目标机不是新加载零时刻，禁止在旧积分状态上重试：t=%g"%self.t)

    def get_param(self,key):
        return scalar(RtlabApi.GetParametersByName((self.param_paths[key],)))

    def set_param(self,key,value):
        if self.execute_attempted:
            raise ContractFail("正式 Execute 后禁止在线改控制参数："+key)
        p=self.param_paths[key];before=self.get_param(key)
        self.written.append(key)
        RtlabApi.SetParametersByName((p,),(float(value),))
        after=self.get_param(key)
        tol=0.1 if key.startswith("FileID") else max(1e-9,1e-8*abs(float(value)))
        if not almost(after,value,tol):
            raise ContractFail("参数回读不一致 %s: wanted=%r got=%r"%(key,value,after))
        self.expected[key]=float(value)

    def setup(self):
        self.require_zero()
        self.take_controls()
        keys=list(self.param_paths)
        vals=RtlabApi.GetParametersByName(tuple(self.param_paths[k] for k in keys))
        self.param_before=dict(zip(keys,map(float,vals)))
        with open(os.path.join(self.run_dir,"parameters_before.json"),"w",encoding="utf-8") as f:
            json.dump(self.param_before,f,ensure_ascii=False,indent=2)

        # 和成熟脚本一致：总使能最后打开。
        self.set_param("CFG15_MASTER_ENABLE",0.0)
        late=["CFG_AA_enable","CFG_AA_blackstart_enable","CFG15_EXEC_S14","CFG15_MASTER_ENABLE"]
        for key,spec in EXPECTED_PARAMS.items():
            if key not in self.param_paths or key in late:
                continue
            val=self.file_id if key in ("FileID27","FileID29","FileID30") else spec["value"]
            self.set_param(key,val)
        for key in late:
            self.set_param(key,EXPECTED_PARAMS[key]["value"])

        self.stop_before=scalar(RtlabApi.GetStopTime())
        RtlabApi.SetStopTime(120.0)
        if not almost(scalar(RtlabApi.GetStopTime()),120.0,1e-8):
            raise ContractFail("StopTime 回读失败。")
        self.require_zero()
        self.log("零时刻配置完成。G27/G29/G30 文件编号=%d"%self.file_id)
        self.log("本轮对应文件基名：base_power_r1_g27_%d.mat / base_power_r1_g29_%d.mat / base_power_r1_g30_%d.mat"
                 %(self.file_id,self.file_id,self.file_id))

    def restore_before_execute(self):
        if self.execute_attempted:
            return
        for key in reversed(list(dict.fromkeys(self.written))):
            try:
                p=self.param_paths[key]
                RtlabApi.SetParametersByName((p,),(self.param_before[key],))
            except Exception:
                pass
        if self.stop_before is not None:
            try:RtlabApi.SetStopTime(self.stop_before)
            except Exception:pass

    def read_signals(self):
        keys=list(self.signal_paths)+list(self.optional_paths)
        paths=[self.signal_paths[k] for k in self.signal_paths]+[self.optional_paths[k] for k in self.optional_paths]
        vals=RtlabApi.GetSignalsByName(tuple(paths))
        if len(vals)!=len(keys):
            raise ContractFail("在线信号批量读取长度不一致。")
        return dict(zip(keys,map(float,vals)))

    def run_to(self,target):
        state,raw=split_state()
        if state!=RtlabApi.MODEL_PAUSED:
            raise ContractFail("每段必须从暂停开始：%r"%(raw,))
        target=round(float(target)/EXPECTED_STEP_S)*EXPECTED_STEP_S
        before=self.read_clock()
        if target<=before+0.25*EXPECTED_STEP_S:
            return
        RtlabApi.SetPauseTime(target)
        if not almost(scalar(RtlabApi.GetPauseTime()),target,EXPECTED_STEP_S):
            raise ContractFail("PauseTime 回读失败。")
        self.execute_attempted=True
        RtlabApi.Execute(1.0)
        deadline=time.monotonic()+max(25.0,5.0*(target-before)+8.0)
        while time.monotonic()<deadline:
            state,raw=split_state()
            if state==RtlabApi.MODEL_PAUSED:
                got=self.read_clock()
                if got>=target-2.01*EXPECTED_STEP_S and got<=target+1.01*EXPECTED_STEP_S:
                    self.t=got;return
            time.sleep(0.005)
        raise ContractFail("未取得预期暂停确认。")

    def sample(self,tag):
        s=self.read_signals()
        t=self.read_clock();self.t=t
        row={"target_clock_s":t,"tag":tag};row.update(s)
        self.observations.append(row)

        rs=int(round(s["restore_state_z"]))
        alpha=s["restore_alpha_z"]
        fail=s["restore_fail_code_z"]
        p=s["ess2_pmeas_pu"];v=s["ess2_vpu"]
        pref=s["ess2_pref_eff_pu"]
        sub=s.get("s14_substate",float("nan"))
        pf=s.get("p_final_applied_pu",float("nan"))
        self.log("t=%7.3f | S14=%s | Restore=%d alpha=%.0f fail=%.0f | V=%.4f pu | Pmeas=%+.5f PrefEff=%+.5f Pcmd=%s"
                 %(t,("?" if not math.isfinite(sub) else "%d"%round(sub)),rs,alpha,fail,v,p,pref,
                   ("?" if not math.isfinite(pf) else "%+.5f"%pf)))

        self.validate(s)

        if rs==6 and self.first_state6 is None:
            self.first_state6=t;self.event("FIRST_RESTORE_STATE6_BASE_CONTROL_OPEN")
        return s

    def validate(self,s):
        needed=["Freq_Hz","Vab_rms_true_V","executed_mode","ESS1_final_droop",
                "restore_state_z","restore_alpha_z","restore_fail_code_z",
                "ess2_idmeas","ess2_iqmeas","ess2_mod_index","ess2_pmeas_pu",
                "ess2_pll_hz","ess2_vpu","ess2_current_limit","ESS2_final_breaker_cmd"]
        for k in needed:
            if not math.isfinite(s[k]):
                raise TrialStop("STOP_NONFINITE","必要在线量无效："+k)

        rs=int(round(s["restore_state_z"]))
        if rs==9 or s["restore_fail_code_z"]>0.5:
            raise TrialStop("STOP_MODEL_REPORTED_FAILURE",
                            "模型恢复执行器报告失败：state=%d fail=%g"%(rs,s["restore_fail_code_z"]))

        # 正式诊断不以普通电气幅值判据提前停止。
        # V/f/I/P、CurrentLimit、ModIndex、Headroom全部继续记录到计划结束。
        # t>=1s以后只检查最基本的运行身份，避免把前几个采样的跨任务延时误判。
        if self.t>=1.0:
            if not almost(s["executed_mode"],4,0.1):
                raise ContractFail("执行模式不是黑启动模式4。")
            if s["J1_applied_close"]>0.5:
                raise ContractFail("J1未保持开路。")
            if s["GridOn_3_ESS1"]>0.5 or s["ESS1_final_droop"]<0.5:
                raise ContractFail("ESS1不再是冻结的GFM构网方式。")
            for k in ("GridOn_1","GridOn_2","GridOn_4","GridOn_5","GridOn_6"):
                if s[k]<0.5:
                    raise ContractFail("非主设备控制模式发生改变："+k)
            for k in ("Pcmd_1_PV1","Pcmd_2_PV2","Pcmd_3_ESS1","Pcmd_4_ESS2","Pcmd_5_EV1","Pcmd_6_EV2"):
                if abs(s[k])>1e-5:
                    raise ContractFail("旧设备功率任务路径出现非零命令："+k+"="+repr(s[k]))

        # 可选信号若能读到，只做信息/明显越权检查，不作为脚本能否启动的必要接口。
        if "handover_beta" in s and math.isfinite(s["handover_beta"]) and abs(s["handover_beta"])>1e-6:
            raise TrialStop("STOP_UNEXPECTED_HANDOVER","本轮基础小功率试验不应出现协调器接管beta。")
        if "correction_gain" in s and math.isfinite(s["correction_gain"]) and abs(s["correction_gain"])>1e-6:
            raise TrialStop("STOP_UNEXPECTED_HANDOVER","本轮不应开启中央一次修正。")
        if "secondary_enable" in s and math.isfinite(s["secondary_enable"]) and abs(s["secondary_enable"])>1e-6:
            raise TrialStop("STOP_UNEXPECTED_HANDOVER","本轮不应开启中央二次修正。")

    def formal_run(self):
        # 不做单独记录回归；正式过程直接开始。
        checkpoints=[0.5,1.0,2.0,4.0,5.5,6.0,8.0,10.0,12.0]
        for t in checkpoints:
            if t>self.t+1e-9:
                self.run_to(t);self.sample("FORMAL")
        while self.t<MAX_RUN_S-1e-9:
            # R1F中state6是整个正式诊断的有功执行状态：
            # 约5 s零目标观察 + 约2 s命令斜坡 + 30 s平台。
            # host再给约2.5 s余量，总计state6后40 s受控暂停。
            if self.first_state6 is not None and self.t>=self.first_state6+POST_STATE6_OBSERVE_S-1e-9:
                self.status="CAPTURE_COMPLETE_AFTER_STATE6_40S_NO_ELECTRICAL_VERDICT"
                self.reason="state6后已继续观察40秒；普通V/f/I/P波动不由Runner判失败，最终由G27/G29/G30 MAT分析。"
                self.event("PLANNED_OBSERVATION_COMPLETE")
                return
            self.run_to(min(MAX_RUN_S,self.t+SAMPLE_STEP_S))
            self.sample("FORMAL")
        raise TrialStop("STOP_TIME_LIMIT",
                        "90秒内未完成计划观察；保留当前现场和MAT，不自动重试。")

    def preserve_pause(self):
        if not self.execute_attempted:
            return
        try:
            state,raw=split_state()
            if state!=RtlabApi.MODEL_PAUSED:
                RtlabApi.Pause()
                deadline=time.monotonic()+10.0
                while time.monotonic()<deadline:
                    state,raw=split_state()
                    if state==RtlabApi.MODEL_PAUSED:break
                    time.sleep(0.01)
            if state==RtlabApi.MODEL_PAUSED:
                self.t=self.read_clock()
        except Exception as e:
            self.log("暂停确认失败，请人工在RT-LAB界面立即确认Pause：%r"%e)

    def write_outputs(self):
        keys=[]
        for r in self.observations:
            for k in r:
                if k not in keys:keys.append(k)
        with open(os.path.join(self.run_dir,"online_snapshots.csv"),"w",encoding="utf-8-sig",newline="") as f:
            w=csv.DictWriter(f,fieldnames=keys);w.writeheader()
            for r in self.observations:w.writerow(r)
        manifest={
            "version":VERSION,"status":self.status,"reason":self.reason,
            "target_clock_s":self.t,"execute_attempted":self.execute_attempted,
            "first_state6_s":self.first_state6,
            "file_id":self.file_id,
            "expected_mat_files":{
                "G27":"base_power_r1_g27_%d.mat"%self.file_id,
                "G29":"base_power_r1_g29_%d.mat"%self.file_id,
                "G30":"base_power_r1_g30_%d.mat"%self.file_id,
            },
            "mandatory_signal_paths":self.signal_paths,
            "optional_signal_paths":self.optional_paths,
        }
        with open(os.path.join(self.run_dir,"manifest.json"),"w",encoding="utf-8") as f:
            json.dump(manifest,f,ensure_ascii=False,indent=2)
        self.log("结果目录："+self.run_dir)
        self.log("最终状态："+self.status)
        self.log("不要Reset；请先取得并上传上面三个MAT文件以及本结果目录。")

    def main(self):
        self.log("ESS2基础小功率正式检验 LEAN R2：单文件、无透明回归、无352信号硬门槛。")
        self.log("输出目录："+self.run_dir)
        try:
            connect_exact_model(self.log)
            self.discover()
            self.setup()
            self.formal_run()
        except TrialStop as e:
            self.status=e.status;self.reason=e.reason
            self.log("受控停止："+e.reason)
        except (Exception,KeyboardInterrupt) as e:
            self.status="FAILED_AFTER_EXECUTE" if self.execute_attempted else "BLOCKED_BEFORE_EXECUTE"
            self.reason=repr(e)
            self.log("停止：%r"%e)
            with open(os.path.join(self.run_dir,"traceback.txt"),"w",encoding="utf-8") as f:
                f.write(traceback.format_exc())
            if not self.execute_attempted:
                self.restore_before_execute()
        finally:
            if self.execute_attempted:
                self.preserve_pause()
            self.release_controls()
            self.write_outputs()
            self.logf.close()
        return {"status":self.status,"reason":self.reason,"run_dir":self.run_dir}

if __name__=="__main__":
    Runner().main()
