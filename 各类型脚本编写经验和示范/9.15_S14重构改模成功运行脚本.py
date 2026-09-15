# -*- coding: utf-8 -*-
r"""
RUN_K26_K50_LOCAL_S14V2_ESS2_PICKUP_HANDOVER_PRIMARY_R1.py
==========================================================

K26_K50_CLEAN_P1 / LOCAL15 / Strategy-14 V2（策略14第二版黑启动）
ESS2（储能2）固定小功率承担 -> S14/Coordinator（策略14/正常孤岛协调器）
平滑接管 -> Primary-only（仅一次有功-频率协调）正式单轮 Runner（运行脚本）R1
日期：2026-09-15

本轮唯一目标
------------
Build（构建）已经成功。本脚本不做transparent regression（透明回归），直接执行正式物理试验：

    ESS1（储能1）dead-bus formation（死母线建压）
    -> S14 V2自动Stage1 PREPARE（阶段1孤岛准备）
    -> 自动Stage2 pre-close stabilization（阶段2合闸前稳定）
    -> ESS2真实同步/物理合闸
    -> state4 / state5零功率稳定接入
    -> S14固定小功率目标 -0.005 pu缓慢承担
    -> Executor（恢复执行器）用真实P跟踪+V/f+I+CurrentLimit+Headroom连续3 s确认state7
    -> 同一轮自动beta（接管比例）0->1平滑交给正常岛内Coordinator（协调器）
    -> Correction Gain（一次协调修正增益）缓慢0->1
    -> Primary-only（仅一次P-f协调）观察
    -> PAUSED（暂停），保留G27/G29/G30 MAT供DirectMAT分析

本轮明确不做
------------
- 不做透明回归；
- 不由Python手工推进AA15_FINAL_SYSTEM_STAGE（统一工程阶段）；
- 不由Python发MANUAL_COMMIT（手动合闸）或MANUAL_RELEASE（手动功率释放）；
- 不由Python在线写beta或Correction Gain；
- 不开启Secondary（正常二次频率/电压恢复）；
- 不恢复PV1/PV2/EV1/EV2；
- 不Reset（复位）、不Load（加载）、不Build（构建）模型；
- 不用host sleep（上位机休眠）定义物理时间；
- 不写死Parameter ID / Signal ID（参数/信号数字编号）；
- Python不宣判最终电气PASS，最终结论由G27/G29/G30 DirectMAT给出。

成功经验复用
------------
1) R5/R6.1/R7成熟RT-LAB Runner：
   - current-Build（当前构建）重新发现参数/信号；
   - split_state()兼容(MODEL_PAUSED, SOFT_SIM_MODE)；
   - Macro Priority（宏脚本优先级）；
   - SetPauseTime（目标暂停时刻）+ Target clock（目标机时钟）；
   - 所有t=0参数写入立即readback（回读）；
   - Execute以后ordinary V/f/I异常先保留证据，不自动Reset。
2) R6.1/R7已证明的电气成功时序已经写入模型S14 V2：
   - Stage1 PREPARE驻留2.5 s；
   - Stage2在COMMIT前额外驻留4.0 s；
   - state0~5真实同步、合闸、零功率稳定语义不重做。
3) 本轮新增控制全部由模型内部自动完成：
   - 固定小功率Rate Limiter（斜率限制器）；
   - state6固定小功率健康驻留；
   - state7本机恢复完成；
   - beta平滑接管；
   - Correction Gain缓慢开启Primary。

Operator contract（操作约束）
-----------------------------
A) 运行前人工 Reset -> Load once -> MODEL_PAUSED（模型暂停）@ t≈0；
B) 不要手工Execute（执行）；
C) 脚本期间不要手工修改Variables Table（变量表）；
D) 完成或受控停止后不要Reset，先保存/分析G27/G29/G30 MAT；
E) RT-LAB Overrun（超时运行）人工确认=0。

正常结束状态
------------
CAPTURE_COMPLETE_S14V2_PICKUP_HANDOVER_PRIMARY_NO_ELECTRICAL_VERDICT
"""
import os
import sys
import re
import csv
import json
import math
import time
import hashlib
import traceback
from datetime import datetime

import RtlabApi

VERSION = "K26_K50_LOCAL_S14V2_ESS2_PICKUP_HANDOVER_PRIMARY_R1_20260915"
PROJECT_KEY = "yanshou_V7"
MODEL_KEY = "K26_K50_CLEAN_P1"
EXPECTED_STEP_S = 1e-4
NOMINAL_V_LL = 10000.0

KNOWN_CURRENT_PROJECT_FILE = os.path.join(
    r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace",
    PROJECT_KEY, PROJECT_KEY + ".llp"
)
KNOWN_CURRENT_MODEL_FILE = os.path.join(
    r"D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace",
    PROJECT_KEY, "models", MODEL_KEY, MODEL_KEY + ".slx"
)
KNOWN_MODEL_ROOT = os.path.dirname(KNOWN_CURRENT_MODEL_FILE)
SOURCE_SHA_POLICY = "RECORD_ONLY_NOT_A_HARD_GATE"

# Model-internal timing is state/event driven. Python only samples evidence.
EARLY_OBSERVE_TIMES = (0.5, 2.0, 4.0, 5.5, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0)
DENSE_STEP_S = 0.5
GLOBAL_DEADLINE_S = 45.0
POST_LOCAL_RESTORED_OBSERVE_S = 12.0
PRIMARY_MIN_OBSERVE_S = 6.0

# Only catastrophic / interpretation-invalid guards.
V_ABS_MAX_V = 25000.0
FREQ_ABS_MAX_HZ = 200.0
ESS2_I_ABS_MAX_PU = 5.0
ESS2_MOD_ABS_MAX = 5.0

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RUN_STAMP = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
RUN_BASE = os.path.join(SCRIPT_DIR, "K50_LOCAL_S14V2_ESS2_PICKUP_HANDOVER")
RUN_DIR = os.path.join(RUN_BASE, "FORMAL_" + RUN_STAMP)
os.makedirs(RUN_DIR, exist_ok=True)

LOG_FILE = os.path.join(RUN_DIR, "run.txt")
MANIFEST_FILE = os.path.join(RUN_DIR, "manifest.json")
HOST_CSV = os.path.join(RUN_DIR, "host_samples.csv")
EVENT_CSV = os.path.join(RUN_DIR, "runtime_events.csv")
PAUSE_JSONL = os.path.join(RUN_DIR, "pause_clock.jsonl")
MAT_PRE_JSON = os.path.join(RUN_DIR, "mat_inventory_pre.json")
MAT_POST_JSON = os.path.join(RUN_DIR, "mat_inventory_post.json")

_log = None
param_paths = {}
optional_param_paths = {}
signal_paths = {}
optional_signal_paths = {}
signal_resolution_records = {}
original_params = {}
host_rows = []
event_rows = []

sys_ctrl = False
par_ctrl = False
started = False
runtime_written = False
current_sim_time = 0.0
clock_path = None
manifest = {}
first_state5_observed_s = None
first_state6_observed_s = None
first_state7_observed_s = None
first_substate50_observed_s = None
first_substate60_observed_s = None
first_full_correction_observed_s = None

current_eng_stage = 0.0
commit_issued = False
release_issued = False
release_time_s = None
zero_power_health_streak_start_s = None
zero_power_healthy_observations = 0


class ContractFail(RuntimeError):
    pass


class NumericalFail(RuntimeError):
    pass


class GateStop(RuntimeError):
    def __init__(self, status, message):
        super(GateStop, self).__init__(message)
        self.status = str(status)
        self.message = str(message)


def log(s=""):
    global _log
    text = str(s)
    print(text)
    sys.stdout.flush()
    if _log is not None:
        _log.write(text + "\n")
        _log.flush()


def normalize_path(x):
    p = str(x).replace("\\", "/")
    p = re.sub(r"\s+", " ", p).strip()
    p = re.sub(r"\s*/\s*", "/", p)
    return p.rstrip("/")


def host_norm(path):
    return os.path.normcase(
        os.path.normpath(str(path).replace("/", os.sep).replace("\\", os.sep))
    )


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def clean_json(x):
    if isinstance(x, float) and not math.isfinite(x):
        return repr(x)
    if isinstance(x, dict):
        return {str(k): clean_json(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [clean_json(v) for v in x]
    return x


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(clean_json(data), f, ensure_ascii=False, indent=2, allow_nan=False)
    os.replace(tmp, path)


def split_state(raw=None):
    if raw is None:
        raw = RtlabApi.GetModelState()
    if isinstance(raw, (tuple, list)):
        return raw[0], (raw[1] if len(raw) > 1 else None), raw
    return raw, None, raw


# ---------------------------------------------------------------------------
# Current single-model V7 connection policy - copied from proven Stage1 R2
# ---------------------------------------------------------------------------

def _looks_like_model_info(x):
    return (
        isinstance(x, (tuple, list))
        and len(x) >= 3
        and isinstance(x[0], str)
    )


def _normalize_models_field(models, declared_count=None):
    if models is None:
        return []
    if _looks_like_model_info(models):
        if isinstance(models[0], str):
            return [tuple(models)]
    if isinstance(models, (tuple, list)):
        out = [tuple(x) for x in models if _looks_like_model_info(x)]
        if out:
            return out
    return []


def _parse_project_info(item):
    if not isinstance(item, (tuple, list)) or len(item) < 6:
        raise RuntimeError("Unexpected GetActiveProjects tuple: %r" % (item,))
    models = _normalize_models_field(item[5], item[4])
    try:
        n_decl = int(item[4])
    except Exception:
        n_decl = len(models)
    if n_decl != len(models):
        raise RuntimeError(
            "GetActiveProjects model-count mismatch: declared=%r parsed=%d project=%r"
            % (item[4], len(models), item[0])
        )
    return {
        "project_path": item[0],
        "project_id": item[1],
        "declared_model_count": n_decl,
        "models": models,
        "raw": item,
    }


def _is_workspace_project_llp(project_path):
    p = host_norm(project_path)
    return (
        os.path.basename(p).lower() == PROJECT_KEY.lower() + ".llp"
        and os.path.basename(os.path.dirname(p)).lower() == PROJECT_KEY.lower()
    )


def _current_model_exact(cur):
    if cur is None or not isinstance(cur, (tuple, list)) or len(cur) < 2:
        return False
    mp, mn = cur[0], cur[1]
    token_ok = (
        MODEL_KEY.lower() in str(mp).lower()
        or MODEL_KEY.lower() in str(mn).lower()
    )
    if not token_ok:
        return False

    candidates = []
    for x in (mp, mn):
        if x is None:
            continue
        s = str(x).strip()
        if not s:
            continue
        candidates.append(s)
        if not s.lower().endswith(".slx"):
            candidates.append(s + ".slx")
            if os.path.isdir(s):
                candidates.append(os.path.join(s, MODEL_KEY + ".slx"))
    for c in candidates:
        try:
            if host_norm(c) == host_norm(KNOWN_CURRENT_MODEL_FILE):
                return True
        except Exception:
            pass

    return token_ok


def connect():
    try:
        cur = RtlabApi.GetCurrentModel()
    except Exception:
        cur = None

    if cur is not None and _current_model_exact(cur):
        log("[API CONNECT PASS] reuse current exact target: %r" % (cur,))
        return cur

    active = list(RtlabApi.GetActiveProjects() or [])
    projects = []
    parse_errors = []
    for item in active:
        try:
            p = _parse_project_info(item)
        except Exception as exc:
            parse_errors.append((repr(item), repr(exc)))
            continue
        if _is_workspace_project_llp(p["project_path"]):
            projects.append(p)

    if len(projects) != 1:
        raise ContractFail(
            "Need exactly one canonical yanshou_V7 workspace LLP; got %d. "
            "Model-local LLP rows are intentionally ignored. projects=%r parse_errors=%r"
            % (len(projects), [p["project_path"] for p in projects], parse_errors)
        )

    proj = projects[0]
    if proj["declared_model_count"] != 1 or len(proj["models"]) != 1:
        raise ContractFail(
            "yanshou_V7 must remain the frozen single-model project. models=%r"
            % (proj["models"],)
        )
    model_path = str(proj["models"][0][0])
    if MODEL_KEY.lower() not in model_path.lower():
        raise ContractFail(
            "The sole yanshou_V7 model is not K26_K50_CLEAN_P1: %r" % model_path
        )

    pid = RtlabApi.OpenProject(
        project=proj["project_path"], returnOnAmbiguity=True
    )
    log(
        "[API PROJECT OPEN PASS] ref=%r projectId=%r"
        % (proj["project_path"], pid)
    )

    deadline = time.monotonic() + 3.0
    last = None
    while time.monotonic() <= deadline:
        try:
            cur = RtlabApi.GetCurrentModel()
            if _current_model_exact(cur):
                log("[API CONNECT PASS] exact current model: %r" % (cur,))
                return cur
            last = RuntimeError("Unexpected current model: %r" % (cur,))
        except Exception as exc:
            last = exc
        time.sleep(0.10)
    raise ContractFail("Could not attach exact K26_K50_CLEAN_P1: %r" % (last,))


def require_paused_at_zero():
    state, mode, raw = split_state()
    log("[MODEL STATE] %r" % (raw,))
    if state != RtlabApi.MODEL_PAUSED:
        if state == getattr(RtlabApi, "MODEL_LOADABLE", object()):
            raise ContractFail(
                "MODEL_LOADABLE: manually click Load once, wait MODEL_PAUSED, "
                "do not Execute, then rerun."
            )
        raise ContractFail("Need MODEL_PAUSED after Load; got %r" % (raw,))

    calc_step, time_factor = RtlabApi.GetTimeInfo()
    log("[RT-LAB] calculation step=%r time factor=%r" % (calc_step, time_factor))
    if abs(float(calc_step) - EXPECTED_STEP_S) > 1e-10:
        raise ContractFail("Expected 100-us calculation step.")

    t0 = read_clock()
    log("[TARGET CLOCK BEFORE WRITE] %.9f s" % t0)
    if abs(t0) > 2.1 * EXPECTED_STEP_S:
        raise ContractFail(
            "The loaded target clock is not at t=0 (clock=%.9f s). "
            "Operator must Reset -> Load once -> do not Execute." % t0
        )


def take_controls():
    global sys_ctrl, par_ctrl
    RtlabApi.TakeFunctionControl(
        RtlabApi.OP_FB_SYSTEM, 0, RtlabApi.OP_CTRL_PRIO_MACRO
    )
    sys_ctrl = True
    RtlabApi.TakeFunctionControl(
        RtlabApi.OP_FB_PARAMETER, 0, RtlabApi.OP_CTRL_PRIO_MACRO
    )
    par_ctrl = True
    log("[CONTROL] System + Parameter control acquired.")


def release_controls():
    global sys_ctrl, par_ctrl
    if par_ctrl:
        try:
            RtlabApi.ReleaseFunctionControl(RtlabApi.OP_FB_PARAMETER, 0)
            log("[CONTROL] Parameter control released.")
        except Exception as exc:
            log("[WARNING] parameter-control release failed: %r" % exc)
        par_ctrl = False
    if sys_ctrl:
        try:
            RtlabApi.ReleaseFunctionControl(RtlabApi.OP_FB_SYSTEM, 0)
            log("[CONTROL] System control released.")
        except Exception as exc:
            log("[WARNING] system-control release failed: %r" % exc)
        sys_ctrl = False


def verify_source_slx():
    if not os.path.isfile(KNOWN_CURRENT_MODEL_FILE):
        raise ContractFail(
            "Current source SLX is missing at canonical V7 path: %s"
            % KNOWN_CURRENT_MODEL_FILE
        )
    got = sha256_file(KNOWN_CURRENT_MODEL_FILE)
    log("[SOURCE SLX] %s" % KNOWN_CURRENT_MODEL_FILE)
    log("[SOURCE SHA256 CURRENT] %s" % got)
    log("[SOURCE SHA POLICY] %s" % SOURCE_SHA_POLICY)
    return {
        "current_sha256": got,
        "policy": SOURCE_SHA_POLICY,
    }



# ---------------------------------------------------------------------------
# Current-Build parameter discovery
# ---------------------------------------------------------------------------

BASE_PARAM_SPECS = {
    "CFG_GATEA_ENABLE": "Value",
    "CFG_GATEA_FREF_HZ": "Value",
    "CFG15_MASTER_ENABLE": "Value",
    "CFG15_CONTROL_SOURCE": "Value",
    "CFG15_P_OBJECTIVE_MODE": "Value",
    **{"CFG15_EXEC_S%02d" % n: "Value" for n in range(1, 16)},
    "CFG15_MODE_ACTUATION_ENABLE": "Value",
    "CFG15_PCC_BREAKER_ACTUATION_ENABLE": "Value",
    "CFG15_DIAG_MODE_BREAKER_DECOUPLE": "Value",
    "CFG15_ISLAND_MASTER": "Value",
    "CFG15_BLACKSTART_MASTER": "Value",
    "CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE": "Value",
    "CFG15_S15_RECOVERY_REQUEST": "Value",
    "CFG_AA_enable": "Value",
    "CFG_AA_blackstart_enable": "Value",
    "CFG_AA_tie_target_kW": "Value",
    "CFG_AA_v_nom_V": "Value",
    "CFG_AA_island_freq_dev_Hz": "Value",
    "CFG_AA_island_v_dev_pu": "Value",
    "AA15_COMM_OK": "Value",

    "CFG_DIAG_AC_CONNECT_PV1": "Value",
    "CFG_DIAG_AC_CONNECT_PV2": "Value",
    "CFG_DIAG_AC_CONNECT_ESS2": "Value",
    "CFG_DIAG_AC_CONNECT_EV1": "Value",
    "CFG_DIAG_AC_CONNECT_EV2": "Value",

    "CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE": "Value",
    "CFG_DIAG_P_SCALE_PV1": "Value",
    "CFG_DIAG_P_SCALE_PV2": "Value",
    "CFG_DIAG_P_SCALE_ESS2": "Value",
    "CFG_DIAG_P_SCALE_EV1": "Value",
    "CFG_DIAG_P_SCALE_EV2": "Value",
    "CFG_DIAG_Q_SCALE_PV1": "Value",
    "CFG_DIAG_Q_SCALE_PV2": "Value",
    "CFG_DIAG_Q_SCALE_ESS2": "Value",
    "CFG_DIAG_Q_SCALE_EV1": "Value",
    "CFG_DIAG_Q_SCALE_EV2": "Value",

    "F1_FILTER_MODE": "Value",
    "F1_AD_ENABLE": "Value",
    "F1_K_AD": "Value",
    "F2_FAST_FB_MODE": "Value",
    "F2_IL_SIGN": "Value",
    "F2_RFF_LOCAL": "Value",
    "F2_LFF_LOCAL": "Value",
    "F2_PHASE_LOCAL_RAD": "Value",
    "F3_VREG_STATE_MODE": "Value",
    "F4_ANGLE_SYNC_MODE": "Value",
    "F4_SYNC_OFFSET_RAD": "Value",
    "F6_SHAPED_AD_ENABLE": "Value",
    "F6_SHAPED_AD_MODE": "Value",
    "F6_SHAPED_AD_GAIN": "Gain",
    "F6_SHAPED_AD_SIGN": "Gain",
    "F8_ENABLE": "Value",
    "F8_IOUT_GAIN": "Gain",
    "F8_CAP_GAIN": "Value",
    "F8_BC_PU": "Value",
    "F8_IOUT_FILTER_MODE": "Value",
    "F9_VREG_MAP_MODE": "Value",
    "F10_INNER_VRAW_MODE": "Value",
    "F10_INNER_IRAW_MODE": "Value",

    "F20_IOUT_MODE": "Value",
    "F20_IOUT_RELEASE_TIME_S": "Value",
    "F20_V2_ENABLE": "Value",
    "F20_V2_CAPTURE_REQ": "Value",
    "F20_V2_CLEAR_REQ": "Value",
    "F21_CURRENT_PI_RESET_ENABLE": "Value",
    "F22_ENABLE": "Value",
    "F22_HANDOVER_MODE": "Value",
    "F22_SUPPORT_ENABLE": "Value",
    "F22_SUPPORT_GAIN": "Value",
    "F23_ENABLE": "Value",
    "F23_ARM": "Value",
    "F23_COMMIT_REQ": "Value",
    "F23_CLEAR_REQ": "Value",
    "F24_ENABLE": "Value",
    "F24_ARM": "Value",
    "F24_RELEASE_ENABLE": "Value",
    "F24_CLEAR_REQ": "Value",
    "F25_ENABLE": "Value",
    "F25_PREPARE_ARM": "Value",
    "F25_PREPARE_COMMIT_REQ": "Value",
    "F25_EDGE_ARM_REQ": "Value",
    "F25_CLEAR_REQ": "Value",

    "CFG_PLAN_COMMIT_ENABLE": "Value",
    "CFG_PLAN_COMMIT_HOLD_REQ": "Value",

    # S14 V2 formal pickup/handover parameters added by the successful Build.
    "AA15_S14V2_CFG_PICKUP_TARGET_PU": "Value",
    "AA15_S14V2_CFG_ESS2_COORD_AUTH_PU": "Value",
}

RESTORE_PARAM_SPECS = {
    "CFG_ESS2_RESTORE_MASTER_ENABLE": "Value",
    "CFG_ESS2_RESTORE_CONTROL_SOURCE": "Value",
    "CFG_ESS2_RESTORE_MANUAL_REQUEST": "Value",
    "CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE": "Value",
    "CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE": "Value",
    "CFG_ESS2_RESTORE_MANUAL_COMMIT": "Value",
    "CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE": "Value",
    "CFG_ESS2_RESTORE_MANUAL_RELEASE": "Value",
    "CFG_ESS2_RESTORE_V_MIN_PU": "Value",
    "CFG_ESS2_RESTORE_V_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_DF_MAX_HZ": "Value",
    "CFG_ESS2_RESTORE_IREF_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_IMEAS_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_HEADROOM_MIN": "Value",
    "CFG_ESS2_RESTORE_READY_DWELL_S": "Value",
    "CFG_ESS2_RESTORE_POST_DWELL_S": "Value",
    "CFG_ESS2_RESTORE_RELEASE_RAMP_S": "Value",
    "CFG_ESS2_RESTORE_PHASE_GATE_ENABLE": "Value",
    "CFG_ESS2_RESTORE_PHASE_COS_MIN": "Value",
    "CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE": "Value",
    "CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN": "Value",
    "CFG_ESS2_RESTORE_VRATIO_MIN": "Value",
    "CFG_ESS2_RESTORE_VRATIO_MAX": "Value",
    "CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE": "Value",
    "CFG_ESS2_RESTORE_POST_I_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_POST_V_MIN_PU": "Value",
    "CFG_ESS2_RESTORE_POST_V_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN": "Value",
    "CFG_ESS2_RESTORE_FNOM_HZ": "Value",
    "CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S": "Value",
    "CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU": "Value",
    "CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU": "Value",
    "CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S": "Value",
}

OPTIONAL_RESTORE_PARAMS = {"CFG_ESS2_RESTORE_TS": "Value"}
OPTIONAL_BASE_PARAMS = {
    "F7_VFF_GAIN": "Gain",
    "F11_CURRENT_REF_TEST_ENABLE": "Value",
    "F12_VFF_NOTCH_MODE": "Value",
    "CFG_AA_switch_enable": "Value",
}
PARAM_SPECS = {}
PARAM_SPECS.update(BASE_PARAM_SPECS)
PARAM_SPECS.update(RESTORE_PARAM_SPECS)
OPTIONAL_PARAMS = {}
OPTIONAL_PARAMS.update(OPTIONAL_BASE_PARAMS)
OPTIONAL_PARAMS.update(OPTIONAL_RESTORE_PARAMS)

FINAL_STAGE_SUFFIX = (
    "/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_SYSTEM_STAGE"
)


def _desc_rows():
    return list(RtlabApi.GetParametersDescription())


def discover_parameters():
    rows = _desc_rows()
    result = {}
    optional = {}
    problems = []
    wanted_all = dict(PARAM_SPECS)
    wanted_all.update(OPTIONAL_PARAMS)

    for key, prop in wanted_all.items():
        hits = []
        for item in rows:
            try:
                block_path = normalize_path(item[1])
                pname = str(item[2]).strip()
                leaf = block_path.split("/")[-1]
            except Exception:
                continue
            if leaf == key and pname.lower() == prop.lower():
                hits.append(item)
        if len(hits) == 1:
            full = str(hits[0][1]).rstrip("/\\") + "/" + str(hits[0][2])
            if key in PARAM_SPECS:
                result[key] = full
            else:
                optional[key] = full
        elif key in PARAM_SPECS:
            problems.append((key, prop, len(hits), hits))
        else:
            log("[OPTIONAL PARAM NOT EXPOSED] %s/%s" % (key, prop))

    # Fallback global stage remains an explicit hard t=0 contract, but Python
    # never advances it after Execute. S14 V2 internal switches own effective stages.
    stage_hits = []
    for item in rows:
        try:
            block_path = normalize_path(item[1])
            pname = str(item[2]).strip()
        except Exception:
            continue
        if block_path.lower().endswith(FINAL_STAGE_SUFFIX.lower()) and pname.lower() == "value":
            stage_hits.append(item)
    if len(stage_hits) != 1:
        problems.append(("AA15_FINAL_SYSTEM_STAGE", "Value", len(stage_hits), stage_hits))
    else:
        result["AA15_FINAL_SYSTEM_STAGE"] = (
            str(stage_hits[0][1]).rstrip("/\\") + "/" + str(stage_hits[0][2])
        )

    if problems:
        log("\n[PARAMETER PREFLIGHT FAILED]")
        for key, prop, n, hits in problems:
            log("  %s/%s -> %d hits" % (key, prop, n))
            for rec in hits[:8]:
                log("    %r" % (rec,))
        raise ContractFail(
            "Mandatory current-Build parameter discovery failed for %d item(s). "
            "No parameter was written and model was not executed." % len(problems)
        )
    log("[PARAMETER PREFLIGHT PASS] mandatory=%d optional-exposed=%d" % (len(result), len(optional)))
    return result, optional


def parse_single_value(ret):
    if isinstance(ret, (tuple, list)) and len(ret) == 1:
        return float(ret[0])
    return float(ret)


def read_path(path):
    return parse_single_value(RtlabApi.GetParametersByName((path,)))


def write_path(path, value):
    RtlabApi.SetParametersByName((path,), (float(value),))
    got = read_path(path)
    tol = max(1e-9, 1e-8 * max(abs(float(value)), 1.0))
    if abs(got - float(value)) > tol:
        raise ContractFail("Parameter readback mismatch: %s wanted=%.12g got=%.12g" % (path, value, got))
    return got


def read_key(key):
    if key in param_paths:
        return read_path(param_paths[key])
    if key in optional_param_paths:
        return read_path(optional_param_paths[key])
    raise KeyError(key)


def set_key(key, value, event=""):
    if key in param_paths:
        path = param_paths[key]
    elif key in optional_param_paths:
        path = optional_param_paths[key]
    else:
        log("[OPTIONAL PARAM SKIP] %s" % key)
        return None
    before = read_path(path)
    after = write_path(path, value)
    log("%-46s : %.12g -> %.12g" % (key, before, after))
    if event:
        event_rows.append({
            "event": event,
            "request_time_s": current_sim_time,
            "target_clock_s": read_clock() if clock_path else float("nan"),
            "key": key,
            "path": path,
            "before": before,
            "after": after,
        })
    return after


def snapshot_original_parameters():
    original_params.clear()
    for key, path in param_paths.items():
        original_params[key] = read_path(path)
    for key, path in optional_param_paths.items():
        original_params[key] = read_path(path)


def restore_preexecute_parameters():
    if started or not original_params:
        return
    log("[PRE-EXECUTE RESTORE] restoring original runtime parameter values.")
    errors = []
    for key, old in original_params.items():
        path = param_paths.get(key, optional_param_paths.get(key))
        if not path:
            continue
        try:
            write_path(path, old)
        except Exception as exc:
            errors.append((key, repr(exc)))
    if errors:
        raise ContractFail("Pre-execute parameter restore failed: %r" % errors)
    log("[PRE-EXECUTE RESTORE PASS]")


INITIAL_VALUES = {
    "CFG_GATEA_ENABLE": 1.0,
    "CFG_GATEA_FREF_HZ": 50.0,
    "CFG15_MASTER_ENABLE": 1.0,
    "CFG15_CONTROL_SOURCE": 1.0,
    "CFG15_P_OBJECTIVE_MODE": 0.0,
    **{"CFG15_EXEC_S%02d" % n: (1.0 if n == 14 else 0.0) for n in range(1, 16)},
    "CFG15_MODE_ACTUATION_ENABLE": 1.0,
    "CFG15_PCC_BREAKER_ACTUATION_ENABLE": 1.0,
    "CFG15_DIAG_MODE_BREAKER_DECOUPLE": 0.0,
    "CFG15_ISLAND_MASTER": 1.0,
    "CFG15_BLACKSTART_MASTER": 1.0,
    "CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE": 1.0,
    "CFG15_S15_RECOVERY_REQUEST": 0.0,

    "CFG_AA_enable": 1.0,
    "CFG_AA_blackstart_enable": 1.0,
    "CFG_AA_tie_target_kW": 0.0,
    "CFG_AA_v_nom_V": 10000.0,
    "CFG_AA_island_freq_dev_Hz": 0.5,
    "CFG_AA_island_v_dev_pu": 0.10,
    "AA15_COMM_OK": 1.0,

    "CFG_DIAG_AC_CONNECT_PV1": 0.0,
    "CFG_DIAG_AC_CONNECT_PV2": 0.0,
    "CFG_DIAG_AC_CONNECT_ESS2": 0.0,
    "CFG_DIAG_AC_CONNECT_EV1": 0.0,
    "CFG_DIAG_AC_CONNECT_EV2": 0.0,
    "CFG_DIAG_ISLAND_PQ_OVERRIDE_ENABLE": 0.0,
    "CFG_DIAG_P_SCALE_PV1": 1.0,
    "CFG_DIAG_P_SCALE_PV2": 1.0,
    "CFG_DIAG_P_SCALE_ESS2": 1.0,
    "CFG_DIAG_P_SCALE_EV1": 1.0,
    "CFG_DIAG_P_SCALE_EV2": 1.0,
    "CFG_DIAG_Q_SCALE_PV1": 1.0,
    "CFG_DIAG_Q_SCALE_PV2": 1.0,
    "CFG_DIAG_Q_SCALE_ESS2": 1.0,
    "CFG_DIAG_Q_SCALE_EV1": 1.0,
    "CFG_DIAG_Q_SCALE_EV2": 1.0,

    # Proven ESS1 black-start/GFM baseline from R5/R6.1/R7.
    "F1_FILTER_MODE": 1.0,
    "F1_AD_ENABLE": 0.0,
    "F1_K_AD": 0.0,
    "F2_FAST_FB_MODE": 2.0,
    "F2_IL_SIGN": 1.0,
    "F2_RFF_LOCAL": 0.0015,
    "F2_LFF_LOCAL": 0.125,
    "F2_PHASE_LOCAL_RAD": 0.0,
    "F3_VREG_STATE_MODE": 1.0,
    "F4_ANGLE_SYNC_MODE": 1.0,
    "F4_SYNC_OFFSET_RAD": -2.0 * math.pi / 3.0,
    "F6_SHAPED_AD_ENABLE": 0.0,
    "F6_SHAPED_AD_MODE": 1.0,
    "F6_SHAPED_AD_GAIN": 0.0,
    "F6_SHAPED_AD_SIGN": -1.0,
    "F8_ENABLE": 1.0,
    "F8_IOUT_GAIN": -1.0,
    "F8_CAP_GAIN": 1.0,
    "F8_BC_PU": 0.05,
    "F8_IOUT_FILTER_MODE": 0.0,
    "F9_VREG_MAP_MODE": 1.0,
    "F10_INNER_VRAW_MODE": 1.0,
    "F10_INNER_IRAW_MODE": 0.0,
    "F20_IOUT_MODE": 1.0,
    "F20_IOUT_RELEASE_TIME_S": 6.2,
    "F20_V2_ENABLE": 0.0,
    "F20_V2_CAPTURE_REQ": 0.0,
    "F20_V2_CLEAR_REQ": 0.0,
    "F21_CURRENT_PI_RESET_ENABLE": 0.0,
    "F22_ENABLE": 0.0,
    "F22_HANDOVER_MODE": 0.0,
    "F22_SUPPORT_ENABLE": 0.0,
    "F22_SUPPORT_GAIN": 0.0,
    "F23_ENABLE": 0.0,
    "F23_ARM": 0.0,
    "F23_COMMIT_REQ": 0.0,
    "F23_CLEAR_REQ": 0.0,
    "F24_ENABLE": 0.0,
    "F24_ARM": 0.0,
    "F24_RELEASE_ENABLE": 0.0,
    "F24_CLEAR_REQ": 0.0,
    "F25_ENABLE": 0.0,
    "F25_PREPARE_ARM": 0.0,
    "F25_PREPARE_COMMIT_REQ": 0.0,
    "F25_EDGE_ARM_REQ": 0.0,
    "F25_CLEAR_REQ": 0.0,
    "CFG_PLAN_COMMIT_ENABLE": 0.0,
    "CFG_PLAN_COMMIT_HOLD_REQ": 0.0,

    # Fallback only. S14 V2 internal stage switches own the effective stages.
    "AA15_FINAL_SYSTEM_STAGE": 0.0,

    # New S14 V2 pickup/Coordinator authority contract.
    "AA15_S14V2_CFG_PICKUP_TARGET_PU": -0.005,
    "AA15_S14V2_CFG_ESS2_COORD_AUTH_PU": 0.010,

    # Restore executor is now fully model-driven by S14 V2 detailed Restore Stage.
    "CFG_ESS2_RESTORE_MASTER_ENABLE": 1.0,
    "CFG_ESS2_RESTORE_CONTROL_SOURCE": 1.0,
    "CFG_ESS2_RESTORE_MANUAL_REQUEST": 0.0,
    "CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE": 0.0,
    "CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE": 1.0,
    "CFG_ESS2_RESTORE_MANUAL_COMMIT": 0.0,
    "CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE": 1.0,
    "CFG_ESS2_RESTORE_MANUAL_RELEASE": 0.0,
    "CFG_ESS2_RESTORE_V_MIN_PU": 0.90,
    "CFG_ESS2_RESTORE_V_MAX_PU": 1.10,
    "CFG_ESS2_RESTORE_DF_MAX_HZ": 0.50,
    "CFG_ESS2_RESTORE_IREF_MAX_PU": 0.05,
    "CFG_ESS2_RESTORE_IMEAS_MAX_PU": 0.05,
    "CFG_ESS2_RESTORE_HEADROOM_MIN": 0.05,
    "CFG_ESS2_RESTORE_READY_DWELL_S": 0.50,
    "CFG_ESS2_RESTORE_POST_DWELL_S": 0.20,
    "CFG_ESS2_RESTORE_RELEASE_RAMP_S": 2.00,
    "CFG_ESS2_RESTORE_PHASE_GATE_ENABLE": 1.0,
    "CFG_ESS2_RESTORE_PHASE_COS_MIN": 0.984807753012208,
    "CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE": 1.0,
    "CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN": 1.0,
    "CFG_ESS2_RESTORE_VRATIO_MIN": 0.95,
    "CFG_ESS2_RESTORE_VRATIO_MAX": 1.05,
    "CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE": 0.0,
    "CFG_ESS2_RESTORE_POST_I_MAX_PU": 0.20,
    "CFG_ESS2_RESTORE_POST_V_MIN_PU": 0.80,
    "CFG_ESS2_RESTORE_POST_V_MAX_PU": 1.20,
    "CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN": 1.0,
    "CFG_ESS2_RESTORE_FNOM_HZ": 50.0,
    "CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S": 2.0,
    "CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU": 0.0045,
    "CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU": 0.0020,
    "CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S": 3.0,
}

OPTIONAL_INITIAL_VALUES = {
    "F7_VFF_GAIN": 1.0,
    "F11_CURRENT_REF_TEST_ENABLE": 0.0,
    "F12_VFF_NOTCH_MODE": 0.0,
    "CFG_AA_switch_enable": 0.0,
    "CFG_ESS2_RESTORE_TS": 1e-4,
}


def write_initial_contract():
    for key, value in INITIAL_VALUES.items():
        set_key(key, value)
    for key, value in OPTIONAL_INITIAL_VALUES.items():
        if key in optional_param_paths:
            set_key(key, value)


def assert_key(key, expected, tol=1e-9):
    got = read_key(key)
    if abs(got - float(expected)) > tol:
        raise ContractFail("%s interlock failed: expected %.12g got %.12g" % (key, expected, got))


def hard_interlock_preexecute():
    for key, expected in INITIAL_VALUES.items():
        assert_key(key, expected, 1e-9)
    for key, expected in OPTIONAL_INITIAL_VALUES.items():
        if key in optional_param_paths:
            assert_key(key, expected, 1e-9)

    log("[PRE-EXECUTE HARD INTERLOCK PASS]")
    log("  GateA=1; only S14 executes; ESS1 is the black-start master.")
    log("  J1 physical actuation enabled; PV1/PV2/ESS2/EV1/EV2 legacy AC commands OPEN.")
    log("  S14 V2 owns Stage sequencing; fallback AA15_FINAL_SYSTEM_STAGE stays 0.")
    log("  ESS2 restore source=S14(1); manual request/commit/release all 0; AUTO=0.")
    log("  Restore Stage1 may qualify READY; COMMIT interlock requires Restore Stage>=2.")
    log("  Fixed pickup target=-0.005 pu; Coordinator ESS2 correction authority=0.010 pu.")
    log("  Pickup local qualification: |PrefEff|>=0.0045, |P-PrefEff|<=0.002, dwell=3 s.")
    log("  Secondary frequency/voltage restoration is model-disabled throughout R1.")

# ---------------------------------------------------------------------------
# Current-Build online signal discovery
# ---------------------------------------------------------------------------

MANDATORY_SIGNALS = {
    "Ppcc_kW": MODEL_KEY + "/SM_Master/J2_PCC_Measurements/Gain/port1",
    "Qpcc_kvar": MODEL_KEY + "/SM_Master/J2_PCC_Measurements/Gain1/port1",
    "Freq_Hz": MODEL_KEY + "/SM_Master/J2_PCC_Measurements/Saturation1/port1",
    "Vab_rms_true_V": MODEL_KEY + "/SM_Master/J2_PCC_Measurements/Gain3/port1",
    "J1_applied_close": MODEL_KEY + "/SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_GATEA_J1_FORCE_OPEN_SWITCH/port1",
    "executed_mode": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Grid_Mode_Execution_Manager/AA15_Grid_Mode_Execution_Core/port1",
    "ESS1_final_droop": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port3",
    "GridOn_1": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port7",
    "GridOn_2": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port8",
    "GridOn_3_ESS1": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port9",
    "GridOn_4": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port10",
    "GridOn_5": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port11",
    "GridOn_6": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_Device_Mode_Router/AA15_Device_Mode_Router_Core/port12",

    # Legacy final command vector must remain zero throughout S14 V2 physical recovery.
    "Pcmd_1_PV1": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_1/port1",
    "Pcmd_2_PV2": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_2/port1",
    "Pcmd_3_ESS1": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_3/port1",
    "Pcmd_4_ESS2": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_4/port1",
    "Pcmd_5_EV1": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_5/port1",
    "Pcmd_6_EV2": MODEL_KEY + "/SM_Master/AA15_LOCAL_CONTROL_STACK/AA15_PLAN_P_COMMIT_HOLD/ROUTER_6/port1",

    # Executor persistent state and delayed control diagnostics proven callable in R5/R6.1/R7.
    "restore_state_z": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(1)",
    "restore_ready_count_z": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(2)",
    "restore_post_count_z": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(3)",
    "restore_alpha_z": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(4)",
    "restore_fail_code_z": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/StateZ/port1(5)",
    "ess2_final_idref": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(3)",
    "ess2_final_iqref": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(4)",
    "ess2_idmeas": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(5)",
    "ess2_iqmeas": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(6)",
    "ess2_mod_index": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(15)",
    "ess2_pmeas_pu": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(16)",
    "ess2_qmeas_pu": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(17)",
    "ess2_pll_hz": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(19)",
    "ess2_vpu": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(21)",
    "ess2_pref_eff_pu": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(26)",
    "ess2_qref_eff_pu": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(28)",
    "ess2_current_limit": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(35)",
    "ess2_master_f_hz": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(37)",
    "ess2_raw_mod_demand": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(42)",
    "ess2_mod_headroom": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/Diag48_Z1/port1(43)",
    "ESS2_final_breaker_cmd": MODEL_KEY + "/SS_Slave2/AA15_ESS2_RESTORE_BREAKER_ROUTER/port1",
}

# New S14 V2 system-level diagnostics are intentionally optional for host gating:
# G29 records them authoritatively even if RT-LAB does not expose every internal scalar.
OPTIONAL_SIGNALS = {
    "ESS1_Fout_direct": MODEL_KEY + "/SS_Slave2/ESS1_Control/Droop Control/Fout/port1",
    "s14_substate": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_SUBSTATE/port1",
    "s14_coarse_stage": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_COARSE/port1",
    "s14_elapsed_s": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_ELAPSED/port1",
    "s14_restore_stage": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_RESTORE_STAGE/port1",
    "s14_coord_stage": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_COORD_STAGE/port1",
    "s14_gfl_stage": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_GFL_STAGE/port1",
    "s14_pickup_enable": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_PICKUP_ENABLE/port1",
    "s14_owner_request": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_OWNER_REQUEST/port1",
    "p_s14_ramped_pu": MODEL_KEY + "/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port2",
    "p_coord_raw_pu": MODEL_KEY + "/SM_Master/P3_FROM_002_01/port1",
    "p_final_applied_pu": MODEL_KEY + "/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port1",
    "handover_beta": MODEL_KEY + "/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/port3",
    "ess2_available": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_AVAILABLE/port1",
    "correction_gain": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_CORRECTION_GAIN/port1",
    "secondary_enable": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_SECONDARY/port1",
    "s14_active": MODEL_KEY + "/SM_Master/AA15_S14V2_G29_ACTIVE/port1",
}


def signal_rows():
    """
    Current-Build dynamic-signal rows.

    IMPORTANT repository lesson:
    GetSignalsDescription may contain duplicate description ROWS for the same
    normalized path. A semantic ambiguity is therefore:
        >1 DISTINCT normalized paths,
    not merely >1 description rows.
    """
    rows = []
    for rec in list(RtlabApi.GetSignalsDescription()):
        try:
            sig_id = int(rec[1])
            path = normalize_path(rec[2])
            label = str(rec[3])
        except Exception:
            continue
        rows.append({
            "id": sig_id,
            "path": path,
            "label": label,
            "raw": rec,
        })
    return rows


def _unique_path_groups(rows):
    groups = {}
    for r in rows:
        key = r["path"].lower()
        groups.setdefault(key, {
            "path": r["path"],
            "rows": [],
        })
        groups[key]["rows"].append(r)
    return groups


def _suffix_of(raw_path):
    path = normalize_path(raw_path)
    for root in (
        "/SM_Master/", "/SS_Slave/", "/SS_Slave2/",
        "/SS_Slave3/", "/SC_Console/"
    ):
        pos = path.find(root)
        if pos >= 0:
            return path[pos:]
    return None


def _read_scalar_signal_path(path):
    vals = RtlabApi.GetSignalsByName((path,))
    if len(vals) != 1:
        raise ContractFail(
            "GetSignalsByName length mismatch for %s: %r" % (path, vals)
        )
    value = float(vals[0])
    if not math.isfinite(value):
        raise ContractFail(
            "Current-Build signal is callable but non-finite before Execute: "
            "%s=%r" % (path, vals[0])
        )
    return value


def resolve_signal_current_build(all_rows, raw_path):
    """
    Resolve one semantic scalar signal using current-Build description.

    Resolution order:
      1. exact normalized path;
      2. unique subsystem suffix.

    Duplicate description rows are collapsed by normalized path.
    Every accepted path is then proven callable with GetSignalsByName().
    """
    path = normalize_path(raw_path)

    exact_rows = [r for r in all_rows if r["path"].lower() == path.lower()]
    exact_groups = _unique_path_groups(exact_rows)

    if len(exact_groups) == 1:
        g = next(iter(exact_groups.values()))
        value = _read_scalar_signal_path(g["path"])
        return g["path"], "exact", g["rows"], value

    if len(exact_groups) > 1:
        return None, "ambiguous-exact-distinct-paths", exact_rows, None

    suffix = _suffix_of(path)
    if suffix is None:
        return None, "no-suffix", [], None

    suffix_rows = [
        r for r in all_rows
        if r["path"].lower().endswith(suffix.lower())
    ]
    suffix_groups = _unique_path_groups(suffix_rows)

    if len(suffix_groups) == 1:
        g = next(iter(suffix_groups.values()))
        value = _read_scalar_signal_path(g["path"])
        return g["path"], "unique-suffix", g["rows"], value

    if len(suffix_groups) == 0:
        return None, "not-exposed", [], None

    return None, "ambiguous-suffix-distinct-paths", suffix_rows, None


def _signal_resolver_selftest():
    # Same path repeated twice is NOT semantic ambiguity.
    rows = [
        {"id": 1, "path": "M/A/port1", "label": "y", "raw": ()},
        {"id": 2, "path": "M/A/port1", "label": "signal1", "raw": ()},
    ]
    groups = _unique_path_groups(rows)
    if len(groups) != 1:
        raise RuntimeError("Signal resolver selftest failed: duplicate-row collapse.")

    # Two distinct paths remain ambiguous.
    rows2 = [
        {"id": 1, "path": "M/A/port1", "label": "a", "raw": ()},
        {"id": 2, "path": "M/B/port1", "label": "b", "raw": ()},
    ]
    if len(_unique_path_groups(rows2)) != 2:
        raise RuntimeError("Signal resolver selftest failed: distinct-path ambiguity.")


def bind_clock(all_rows):
    global clock_path

    suffixes = (
        "/SM_Master/Clock/port1",
        "/SM_Master/Board_HB_Time/port1",
        "/SM_Master/Clock1/port1",
    )

    for tail in suffixes:
        hits = [
            r for r in all_rows
            if r["path"].lower().endswith(tail.lower())
        ]
        groups = _unique_path_groups(hits)
        if len(groups) == 1:
            g = next(iter(groups.values()))
            _read_scalar_signal_path(g["path"])
            clock_path = g["path"]
            log(
                "[TARGET CLOCK] %s (description_rows=%d)"
                % (clock_path, len(g["rows"]))
            )
            return

    raise ContractFail(
        "No unique callable target-side clock is exposed; host time will not "
        "be substituted."
    )


def discover_signals():
    global signal_resolution_records

    _signal_resolver_selftest()

    all_rows = signal_rows()
    bind_clock(all_rows)

    mandatory = {}
    optional = {}
    problems = []
    signal_resolution_records = {}

    log("\n--- CURRENT-BUILD MANDATORY ONLINE SIGNAL CONTRACT ---")

    for key, raw in MANDATORY_SIGNALS.items():
        try:
            actual, how, matched_rows, value = resolve_signal_current_build(
                all_rows, raw
            )
        except Exception as exc:
            problems.append((key, raw, "call-failed", repr(exc)))
            continue

        if actual is None:
            problems.append((key, raw, how, [
                (r["id"], r["path"], r["label"])
                for r in matched_rows[:12]
            ]))
            continue

        mandatory[key] = actual
        rec = {
            "requested": normalize_path(raw),
            "actual": actual,
            "method": how,
            "description_row_count": len(matched_rows),
            "ids": [r["id"] for r in matched_rows],
            "labels": [r["label"] for r in matched_rows],
            "initial_readback": value,
        }
        signal_resolution_records[key] = rec

        log(
            "[SIG OK] %-28s via=%-13s rows=%-2d IDs=%s path=%s value=%+.9g"
            % (
                key,
                how,
                len(matched_rows),
                rec["ids"],
                actual,
                value,
            )
        )

    if problems:
        log("[MANDATORY SIGNAL CONTRACT FAILED]")
        for row in problems:
            log("  %r" % (row,))
        raise ContractFail(
            "Mandatory current-Build semantic signal discovery failed for "
            "%d item(s); no parameter write / Execute." % len(problems)
        )

    log("\n--- OPTIONAL ONLINE SIGNALS ---")
    for key, raw in OPTIONAL_SIGNALS.items():
        try:
            actual, how, matched_rows, value = resolve_signal_current_build(
                all_rows, raw
            )
        except Exception as exc:
            log("[OPTIONAL CALL FAIL] %-24s %r" % (key, exc))
            continue

        if actual is None:
            log("[OPTIONAL NOT EXPOSED] %-24s via=%s" % (key, how))
            continue

        optional[key] = actual
        signal_resolution_records[key] = {
            "requested": normalize_path(raw),
            "actual": actual,
            "method": how,
            "description_row_count": len(matched_rows),
            "ids": [r["id"] for r in matched_rows],
            "labels": [r["label"] for r in matched_rows],
            "initial_readback": value,
        }
        log(
            "[OPTIONAL SIG OK] %-24s via=%-13s rows=%d path=%s"
            % (key, how, len(matched_rows), actual)
        )

    # Re-read all accepted names in one batch. This catches any API behavior
    # difference between individual and batched calls before any write/Execute.
    all_paths = list(mandatory.values()) + list(optional.values())
    vals = RtlabApi.GetSignalsByName(tuple(all_paths))
    if len(vals) != len(all_paths):
        raise ContractFail(
            "Batched signal read length mismatch before Execute: %d vs %d"
            % (len(vals), len(all_paths))
        )

    for p, v in zip(all_paths, vals):
        if not math.isfinite(float(v)):
            raise ContractFail(
                "Batched current-Build signal read non-finite: %s=%r" % (p, v)
            )

    log(
        "[SIGNAL CONTRACT PASS] mandatory=%d optional=%d/%d; all callable"
        % (len(mandatory), len(optional), len(OPTIONAL_SIGNALS))
    )
    return mandatory, optional


def read_clock():
    if not clock_path:
        raise ContractFail("Target clock is not bound.")
    v = RtlabApi.GetSignalsByName((clock_path,))
    if len(v) != 1 or not math.isfinite(float(v[0])):
        raise ContractFail("Target clock readback invalid.")
    return float(v[0])


def read_signal_dict():
    keys = list(signal_paths)
    paths = [signal_paths[k] for k in keys]
    vals = RtlabApi.GetSignalsByName(tuple(paths))

    if len(vals) != len(keys):
        raise ContractFail("Mandatory signal read length mismatch.")

    out = {k: float(v) for k, v in zip(keys, vals)}

    if optional_signal_paths:
        okeys = list(optional_signal_paths)
        ovals = RtlabApi.GetSignalsByName(
            tuple(optional_signal_paths[k] for k in okeys)
        )
        if len(ovals) != len(okeys):
            raise ContractFail("Optional signal read length mismatch.")
        out.update({k: float(v) for k, v in zip(okeys, ovals)})

    return out



# ---------------------------------------------------------------------------
# RT-LAB simulation-time scheduling - proven Stage1 R2 pattern
# ---------------------------------------------------------------------------

def wait_state(target, timeout=240.0):
    t0 = time.monotonic()
    while True:
        state, _, raw = split_state()
        if state == target:
            return
        if time.monotonic() - t0 > timeout:
            raise TimeoutError("Timeout waiting for state; current=%r" % (raw,))
        time.sleep(0.01)


def quantize_time(t):
    x = float(t)
    if not math.isfinite(x) or x < 0:
        raise ContractFail("Pause target must be finite and nonnegative.")
    return round(x / EXPECTED_STEP_S) * EXPECTED_STEP_S


def pause_sample_matches(before_clock, after_clock, target):
    if not all(math.isfinite(x) for x in (before_clock, after_clock, target)):
        return False

    progressed = after_clock - before_clock >= 0.25 * EXPECTED_STEP_S
    in_window = (
        target - 2.01 * EXPECTED_STEP_S
        <= after_clock
        <= target + 1.01 * EXPECTED_STEP_S
    )
    return progressed and in_window


def run_to_pause(abs_time):
    global current_sim_time, started

    state, _, raw = split_state()
    if state != RtlabApi.MODEL_PAUSED:
        raise ContractFail("Expected PAUSED before Execute; got %r" % (raw,))

    target = quantize_time(abs_time)
    if target <= current_sim_time + 0.25 * EXPECTED_STEP_S:
        raise ContractFail(
            "Pause target did not advance: %.9f <= %.9f"
            % (target, current_sim_time)
        )

    before = read_clock()
    if before > target + EXPECTED_STEP_S:
        raise ContractFail(
            "Target clock already beyond requested pause: before=%.9f target=%.9f"
            % (before, target)
        )

    RtlabApi.SetPauseTime(target)
    got = float(RtlabApi.GetPauseTime())
    if abs(got - target) > EXPECTED_STEP_S:
        raise ContractFail(
            "PauseTime readback mismatch wanted=%.9f got=%.9f" % (target, got)
        )

    log("[RUN] %.6f -> %.6f s" % (current_sim_time, target))
    RtlabApi.Execute(1.0)
    started = True

    deadline = time.monotonic() + 240.0
    last = before
    stable_since = None
    stable_value = None

    while time.monotonic() < deadline:
        state, _, raw = split_state()

        if state == RtlabApi.MODEL_PAUSED:
            last = read_clock()

            if pause_sample_matches(before, last, target):
                current_sim_time = target

                with open(PAUSE_JSONL, "a", encoding="utf-8") as f:
                    f.write(
                        json.dumps(
                            {
                                "request_s": target,
                                "clock_before_s": before,
                                "clock_after_s": last,
                                "clock_minus_request_steps":
                                    (last - target) / EXPECTED_STEP_S,
                            },
                            ensure_ascii=False,
                        )
                        + "\n"
                    )

                log(
                    "[PAUSE] request=%.6f target_clock=%.6f"
                    % (target, last)
                )
                return

            if (
                stable_value is None
                or abs(last - stable_value) > 0.1 * EXPECTED_STEP_S
            ):
                stable_value = last
                stable_since = time.monotonic()
            elif (
                stable_since is not None
                and time.monotonic() - stable_since > 5.0
            ):
                raise ContractFail(
                    "Target is PAUSED but clock did not reach request: "
                    "before=%.9f request=%.9f after=%.9f"
                    % (before, target, last)
                )

        else:
            stable_since = None
            stable_value = None

            if state == getattr(RtlabApi, "MODEL_LOADABLE", object()):
                raise ContractFail(
                    "Model became MODEL_LOADABLE during run; no automatic Load."
                )

        time.sleep(0.005)

    raise ContractFail(
        "Timeout waiting PAUSED at %.6f; last clock=%.9f state=%r"
        % (target, last, raw)
    )



# ---------------------------------------------------------------------------
# Evidence / gates
# ---------------------------------------------------------------------------

def _near(x, target, tol=0.1):
    return abs(float(x) - float(target)) <= float(tol)


def _all_finite(s):
    for k, v in s.items():
        if not math.isfinite(float(v)):
            raise NumericalFail("Non-finite online signal %s=%r" % (k, v))


def augment_restore_semantics(s):
    state = int(round(s["restore_state_z"]))
    alpha = min(max(float(s["restore_alpha_z"]), 0.0), 1.0)
    fail = max(float(s["restore_fail_code_z"]), 0.0)
    iref = math.hypot(s["ess2_final_idref"], s["ess2_final_iqref"])
    imeas = math.hypot(s["ess2_idmeas"], s["ess2_iqmeas"])
    p_err = s["ess2_pmeas_pu"] - s["ess2_pref_eff_pu"]

    f_nom = INITIAL_VALUES["CFG_ESS2_RESTORE_FNOM_HZ"]
    df_nom_hz = abs(s["ess2_pll_hz"] - f_nom)
    df_bus_hz = abs(s["ess2_pll_hz"] - s["Freq_Hz"])
    vmin = INITIAL_VALUES["CFG_ESS2_RESTORE_V_MIN_PU"]
    vmax = INITIAL_VALUES["CFG_ESS2_RESTORE_V_MAX_PU"]
    dfmax = INITIAL_VALUES["CFG_ESS2_RESTORE_DF_MAX_HZ"]
    imeasmax = INITIAL_VALUES["CFG_ESS2_RESTORE_IMEAS_MAX_PU"]
    headmin = INITIAL_VALUES["CFG_ESS2_RESTORE_HEADROOM_MIN"]
    post_vmin = INITIAL_VALUES["CFG_ESS2_RESTORE_POST_V_MIN_PU"]
    post_vmax = INITIAL_VALUES["CFG_ESS2_RESTORE_POST_V_MAX_PU"]
    post_imax = INITIAL_VALUES["CFG_ESS2_RESTORE_POST_I_MAX_PU"]
    pickup_pref_min = INITIAL_VALUES["CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU"]
    pickup_perr_max = INITIAL_VALUES["CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU"]

    zero_stable_now = (
        vmin <= s["ess2_vpu"] <= vmax
        and imeas <= imeasmax
        and s["ess2_current_limit"] < 0.5
        and s["ess2_mod_headroom"] >= headmin
    )
    pickup_ok_now = (
        abs(s["ess2_pref_eff_pu"]) >= pickup_pref_min
        and abs(p_err) <= pickup_perr_max
        and vmin <= s["ess2_vpu"] <= vmax
        and df_nom_hz <= dfmax
        and iref <= post_imax
        and imeas <= post_imax
        and s["ess2_current_limit"] < 0.5
        and s["ess2_mod_headroom"] >= headmin
    )
    pickup_severe_now = (
        iref > post_imax or imeas > post_imax
        or s["ess2_vpu"] < post_vmin or s["ess2_vpu"] > post_vmax
        or s["ess2_current_limit"] > 0.5
    )

    zero_dwell = INITIAL_VALUES["CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S"]
    state5_dwell_done = (
        state == 5
        and s["restore_ready_count_z"] * EXPECTED_STEP_S + EXPECTED_STEP_S >= zero_dwell
    )

    s["restore_state"] = float(state)
    s["restore_alpha"] = alpha
    s["restore_fail_code"] = fail
    s["restore_hold"] = 1.0 if (state <= 3 or state == 9) else 0.0
    s["restore_release_allowed"] = 1.0 if (state in (6, 7) or state5_dwell_done) else 0.0
    s["restore_iref_mag"] = iref
    s["restore_imeas_mag"] = imeas
    s["restore_p_error"] = p_err
    s["restore_df_nom_hz"] = df_nom_hz
    s["restore_df_bus_hz"] = df_bus_hz
    s["restore_zero_stable_now"] = 1.0 if zero_stable_now else 0.0
    s["restore_pickup_ok_now"] = 1.0 if pickup_ok_now else 0.0
    s["restore_pickup_severe_now"] = 1.0 if pickup_severe_now else 0.0
    return s


def assert_runtime_config():
    checks = {
        "CFG15_MASTER_ENABLE": 1.0,
        "CFG15_CONTROL_SOURCE": 1.0,
        "CFG15_EXEC_S14": 1.0,
        "CFG15_BLACKSTART_MASTER": 1.0,
        "CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE": 1.0,
        "CFG_DIAG_AC_CONNECT_PV1": 0.0,
        "CFG_DIAG_AC_CONNECT_PV2": 0.0,
        "CFG_DIAG_AC_CONNECT_ESS2": 0.0,
        "CFG_DIAG_AC_CONNECT_EV1": 0.0,
        "CFG_DIAG_AC_CONNECT_EV2": 0.0,
        "AA15_FINAL_SYSTEM_STAGE": 0.0,
        "AA15_S14V2_CFG_PICKUP_TARGET_PU": -0.005,
        "AA15_S14V2_CFG_ESS2_COORD_AUTH_PU": 0.010,
        "CFG_ESS2_RESTORE_MASTER_ENABLE": 1.0,
        "CFG_ESS2_RESTORE_CONTROL_SOURCE": 1.0,
        "CFG_ESS2_RESTORE_MANUAL_REQUEST": 0.0,
        "CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE": 0.0,
        "CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE": 1.0,
        "CFG_ESS2_RESTORE_MANUAL_COMMIT": 0.0,
        "CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE": 1.0,
        "CFG_ESS2_RESTORE_MANUAL_RELEASE": 0.0,
        "CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE": 0.0,
        "CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN": 1.0,
        "CFG_ESS2_RESTORE_FNOM_HZ": 50.0,
        "CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S": 2.0,
        "CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU": 0.0045,
        "CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU": 0.0020,
        "CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S": 3.0,
    }
    for key, wanted in checks.items():
        got = read_key(key)
        if abs(got - wanted) > 1e-9:
            raise ContractFail(
                "Runtime control contract drift: %s wanted=%.12g got=%.12g" % (key, wanted, got)
            )


def _check_common_blackstart_contract(s):
    if not _near(s["executed_mode"], 4.0, 0.1):
        raise ContractFail("Applied system mode is not BLACK_START(4): %.6g" % s["executed_mode"])
    if s["J1_applied_close"] > 0.5:
        raise ContractFail("J1 applied is CLOSED during black start.")
    if s["GridOn_3_ESS1"] > 0.5:
        raise ContractFail("ESS1 is not in GFM mode (GridOn must be 0).")
    if s["ESS1_final_droop"] < 0.5:
        raise ContractFail("ESS1 Droop is not enabled.")
    for k in ("GridOn_1", "GridOn_2", "GridOn_4", "GridOn_5", "GridOn_6"):
        if s[k] < 0.5:
            raise ContractFail("Non-master device unexpectedly not in GFL control mode: %s=%g" % (k, s[k]))
    if abs(s["Vab_rms_true_V"]) > V_ABS_MAX_V:
        raise NumericalFail("Catastrophic PCC voltage magnitude: %.3f V" % s["Vab_rms_true_V"])
    if abs(s["Freq_Hz"]) > FREQ_ABS_MAX_HZ:
        raise NumericalFail("Catastrophic frequency value: %.6f Hz" % s["Freq_Hz"])
    if s["restore_iref_mag"] > ESS2_I_ABS_MAX_PU or s["restore_imeas_mag"] > ESS2_I_ABS_MAX_PU:
        raise NumericalFail("Catastrophic ESS2 current magnitude.")
    if abs(s["ess2_mod_index"]) > ESS2_MOD_ABS_MAX:
        raise NumericalFail("Catastrophic ESS2 modulation magnitude.")


def assert_legacy_pref_zero(s):
    for k in (
        "Pcmd_1_PV1", "Pcmd_2_PV2", "Pcmd_3_ESS1",
        "Pcmd_4_ESS2", "Pcmd_5_EV1", "Pcmd_6_EV2",
    ):
        if abs(s[k]) > 1e-5:
            raise ContractFail("S14 V2 legacy Pref leaked during physical black start: %s=%+.9f" % (k, s[k]))


def assert_restore_topology_semantics(s):
    st = int(round(s["restore_state"]))
    br = s["ESS2_final_breaker_cmd"]
    alpha = s["restore_alpha"]
    if st <= 3:
        if br > 0.5:
            raise ContractFail("ESS2 breaker closed before state4: state=%d br=%g" % (st, br))
        if alpha > 1e-6:
            raise ContractFail("RestoreAlpha nonzero before state6: state=%d alpha=%g" % (st, alpha))
    elif st in (4, 5):
        if br < 0.5:
            raise ContractFail("ESS2 breaker open in connected zero-power state%d" % st)
        if alpha > 1e-6:
            raise ContractFail("RestoreAlpha nonzero in state%d" % st)
    elif st in (6, 7):
        if br < 0.5:
            raise ContractFail("ESS2 breaker open in power/restored state%d" % st)
        if alpha < 0.999:
            raise ContractFail("S14 V2 state%d requires binary RestoreAlpha=1; got %.6g" % (st, alpha))
    elif st == 9:
        if br > 0.5:
            raise ContractFail("Executor state9 but breaker remains closed.")


def _physical_quality_warning(tag, s):
    notes = []
    vpu = s["Vab_rms_true_V"] / NOMINAL_V_LL
    if not (0.80 <= vpu <= 1.20):
        notes.append("PCC_V=%.4fpu outside 0.80..1.20" % vpu)
    if not (48.0 <= s["Freq_Hz"] <= 52.0):
        notes.append("PCC_f=%.5fHz outside 48..52" % s["Freq_Hz"])
    if abs(s["ess2_mod_index"]) >= 0.999:
        notes.append("ESS2 ModIndex≈saturated %.6g" % s["ess2_mod_index"])
    if s["ess2_current_limit"] > 0.5:
        notes.append("ESS2 CurrentLimit active")
    if s["ess2_mod_headroom"] < 0.0:
        notes.append("ESS2 ModHeadroom negative %.6g" % s["ess2_mod_headroom"])
    if notes:
        log("[PHYSICAL QUALITY WARNING @ %s] %s" % (tag, "; ".join(notes)))
    return notes


def checkpoint(tag):
    global first_state5_observed_s, first_state6_observed_s, first_state7_observed_s
    global first_substate50_observed_s, first_substate60_observed_s
    global first_full_correction_observed_s

    s = augment_restore_semantics(read_signal_dict())
    _all_finite(s)
    _check_common_blackstart_contract(s)
    assert_runtime_config()
    assert_legacy_pref_zero(s)
    assert_restore_topology_semantics(s)
    quality_notes = _physical_quality_warning(tag, s)

    st = int(round(s["restore_state"]))
    if st == 5 and first_state5_observed_s is None:
        first_state5_observed_s = current_sim_time
    if st == 6 and first_state6_observed_s is None:
        first_state6_observed_s = current_sim_time
    if st == 7 and first_state7_observed_s is None:
        first_state7_observed_s = current_sim_time

    if "s14_substate" in s:
        ss = int(round(s["s14_substate"]))
        if ss == 50 and first_substate50_observed_s is None:
            first_substate50_observed_s = current_sim_time
        if ss == 60 and first_substate60_observed_s is None:
            first_substate60_observed_s = current_sim_time
        if ss == 90:
            controlled_stop("CONTROLLED_STOP_S14_FAIL_STATE", "S14 V2 entered FAIL substate90.")
    if "correction_gain" in s and s["correction_gain"] >= 0.999 and first_full_correction_observed_s is None:
        first_full_correction_observed_s = current_sim_time
    if "secondary_enable" in s and s["secondary_enable"] > 0.5:
        raise ContractFail("SecondaryEnable unexpectedly became 1 during R1 primary-only trial.")

    row = {
        "tag": tag,
        "request_time_s": current_sim_time,
        "target_clock_s": read_clock(),
        "quality_warning": " | ".join(quality_notes),
    }
    row.update(s)
    host_rows.append(row)

    new_fields = []
    for key in (
        "s14_substate", "s14_restore_stage", "s14_coord_stage", "s14_gfl_stage",
        "s14_pickup_enable", "s14_owner_request", "p_s14_ramped_pu",
        "p_coord_raw_pu", "p_final_applied_pu", "handover_beta",
        "ess2_available", "correction_gain", "secondary_enable", "s14_active",
    ):
        if key in s:
            new_fields.append("%s=%+.5f" % (key, s[key]))

    log(
        "[%s @ %.6f] V=%.2fV f=%.5fHz Ppcc=%+.3fkW Qpcc=%+.3fkvar "
        "Restore{state=%.0f alpha=%.1f fail=%.0f br=%.0f Iref=%.5f Imeas=%.5f "
        "P=%+.5f PrefEff=%+.5f Perr=%+.5f pickupOK=%.0f severe=%.0f head=%.5f MI=%.5f} %s"
        % (
            tag, current_sim_time, s["Vab_rms_true_V"], s["Freq_Hz"],
            s["Ppcc_kW"], s["Qpcc_kvar"], s["restore_state"], s["restore_alpha"],
            s["restore_fail_code"], s["ESS2_final_breaker_cmd"],
            s["restore_iref_mag"], s["restore_imeas_mag"], s["ess2_pmeas_pu"],
            s["ess2_pref_eff_pu"], s["restore_p_error"], s["restore_pickup_ok_now"],
            s["restore_pickup_severe_now"], s["ess2_mod_headroom"], s["ess2_mod_index"],
            " ".join(new_fields),
        )
    )

    if s["restore_fail_code"] > 0.5:
        controlled_stop(
            "CONTROLLED_STOP_RESTORE_FAILCODE",
            "ESS2 Restore Executor declared failCode=%.0f at %.6f s."
            % (s["restore_fail_code"], current_sim_time),
        )
    if st == 9:
        controlled_stop("CONTROLLED_STOP_RESTORE_STATE9", "ESS2 Restore Executor entered state9.")
    return s


def controlled_stop(status, reason):
    raise GateStop(status, reason)


def next_dense_target(t):
    return quantize_time(t + DENSE_STEP_S)


def final_target_after_state7(t7):
    return min(GLOBAL_DEADLINE_S, quantize_time(t7 + POST_LOCAL_RESTORED_OBSERVE_S))


# ---------------------------------------------------------------------------
# Host evidence and MAT inventory
# ---------------------------------------------------------------------------

MAT_STEMS = (
    "rootdiag_ev12_data",
    "rootdiag_ess2_data",
    "rootdiag_pv12_data",
    "d1_gfm_superpack_data",
    "freqdiag_ess1_data",
)


def mat_inventory():
    rows = []
    if not os.path.isdir(KNOWN_MODEL_ROOT):
        return rows

    for root, dirs, files in os.walk(KNOWN_MODEL_ROOT):
        if os.path.basename(root).lower() != "opredhawktarget":
            continue

        for fn in files:
            low = fn.lower()
            if not low.endswith(".mat"):
                continue
            if not any(low.startswith(stem.lower()) for stem in MAT_STEMS):
                continue

            fp = os.path.join(root, fn)
            try:
                st = os.stat(fp)
            except OSError:
                continue

            rows.append({
                "relative_path": os.path.relpath(fp, KNOWN_MODEL_ROOT),
                "size_bytes": int(st.st_size),
                "mtime_ns": int(getattr(st, "st_mtime_ns", int(st.st_mtime * 1e9))),
            })

    rows.sort(key=lambda x: x["relative_path"].lower())
    return rows


def write_host_csv():
    if not host_rows:
        return

    fields = []
    seen = set()
    for row in host_rows:
        for k in row:
            if k not in seen:
                seen.add(k)
                fields.append(k)

    with open(HOST_CSV, "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.DictWriter(f, fieldnames=fields)
        wr.writeheader()
        for row in host_rows:
            wr.writerow(row)


def write_event_csv():
    if not event_rows:
        return

    fields = []
    seen = set()
    for row in event_rows:
        for k in row:
            if k not in seen:
                seen.add(k)
                fields.append(k)

    with open(EVENT_CSV, "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.DictWriter(f, fieldnames=fields)
        wr.writeheader()
        for row in event_rows:
            wr.writerow(row)


def preserve_pause(reason):
    log("[PRESERVE] %s" % reason)
    try:
        state, _, raw = split_state()
        if started and state != RtlabApi.MODEL_PAUSED:
            RtlabApi.Pause()
            wait_state(RtlabApi.MODEL_PAUSED, 10.0)

        state, _, raw = split_state()
        if state == RtlabApi.MODEL_PAUSED:
            log("[PRESERVE PASS] Model remains PAUSED; NO Reset / NO auto-reconnect.")
            return

        log("[PRESERVE WARNING] final state=%r" % (raw,))
    except Exception as exc:
        log("[PRESERVE WARNING] could not confirm PAUSED: %r" % exc)


def finalize_manifest(status, notes=None):
    global manifest

    try:
        final_clock = read_clock()
    except Exception:
        final_clock = float("nan")

    try:
        post_inventory = mat_inventory()
        write_json(MAT_POST_JSON, post_inventory)
    except Exception as exc:
        post_inventory = []
        log("[WARNING] post MAT inventory failed: %r" % exc)

    manifest["status"] = status
    manifest["final_target_clock_s"] = final_clock
    manifest["current_sim_time_s"] = current_sim_time
    manifest["host_samples_csv"] = HOST_CSV
    manifest["runtime_events_csv"] = EVENT_CSV
    manifest["pause_clock_jsonl"] = PAUSE_JSONL
    manifest["mat_inventory_pre_json"] = MAT_PRE_JSON
    manifest["mat_inventory_post_json"] = MAT_POST_JSON
    manifest["host_samples"] = host_rows
    manifest["runtime_events"] = event_rows
    manifest["notes"] = list(notes or [])
    manifest["electrical_verdict"] = "NOT_EVALUATED_BY_RUNNER"

    write_host_csv()
    write_event_csv()
    write_json(MANIFEST_FILE, manifest)



# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def assert_experiment_constants():
    if not (0.0 < DENSE_STEP_S <= 1.0):
        raise RuntimeError("DENSE_STEP_S must be in (0,1].")
    if GLOBAL_DEADLINE_S < 30.0:
        raise RuntimeError("GLOBAL_DEADLINE_S is too short for pickup + handover + primary observation.")
    if INITIAL_VALUES["AA15_S14V2_CFG_PICKUP_TARGET_PU"] >= 0.0:
        raise RuntimeError("R1 pickup target must remain the frozen small charging test (<0).")
    if abs(INITIAL_VALUES["AA15_S14V2_CFG_PICKUP_TARGET_PU"]) > 0.02 + 1e-12:
        raise RuntimeError("Pickup target exceeds frozen ±0.02 pu diagnostic hard bound.")
    if INITIAL_VALUES["AA15_S14V2_CFG_ESS2_COORD_AUTH_PU"] > 0.02 + 1e-12:
        raise RuntimeError("ESS2 Coordinator authority exceeds frozen 0.02 pu hard bound.")
    if INITIAL_VALUES["CFG_ESS2_RESTORE_CONTROL_SOURCE"] != 1.0:
        raise RuntimeError("Formal R1 must use S14 model-side Restore Stage source.")
    for key in ("CFG_ESS2_RESTORE_MANUAL_REQUEST", "CFG_ESS2_RESTORE_MANUAL_COMMIT", "CFG_ESS2_RESTORE_MANUAL_RELEASE"):
        if INITIAL_VALUES[key] != 0.0:
            raise RuntimeError("Formal R1 forbids host/manual restore events: %s" % key)


def main():
    assert_experiment_constants()
    global _log, param_paths, optional_param_paths
    global signal_paths, optional_signal_paths, runtime_written, manifest

    _log = open(LOG_FILE, "w", encoding="utf-8", buffering=1)
    log("=" * 118)
    log("K26_K50 LOCAL S14 V2 — ESS2 FIXED-P PICKUP + SMOOTH HANDOVER + PRIMARY-ONLY R1")
    log("VERSION     : %s" % VERSION)
    log("__file__    : %s" % os.path.abspath(__file__))
    log("PROJECT_KEY : %s" % PROJECT_KEY)
    log("MODEL_KEY   : %s" % MODEL_KEY)
    log("RUN_DIR     : %s" % RUN_DIR)
    log("SCOPE       : model-driven S14 V2 -> fixed -0.005 pu -> state7 -> beta handover -> primary-only.")
    log("NO transparent regression. NO manual stage/commit/release writes after Execute. NO Secondary. NO PV/EV reconnect.")
    log("=" * 118)

    model_cur = connect()
    log("[GetCurrentModel] %r" % (model_cur,))
    source_identity = verify_source_slx()

    param_paths, optional_param_paths = discover_parameters()
    signal_paths, optional_signal_paths = discover_signals()
    require_paused_at_zero()
    initial_signal_snapshot = read_signal_dict()

    take_controls()
    snapshot_original_parameters()

    try:
        log("\n--- WRITE COMPLETE FINAL t=0 CONTRACT WHILE PAUSED ---")
        write_initial_contract()
        runtime_written = True

        log("\n--- PRE-EXECUTE HARD INTERLOCK ---")
        hard_interlock_preexecute()
        tcheck = read_clock()
        if abs(tcheck) > 2.1 * EXPECTED_STEP_S:
            raise ContractFail("Target clock moved before first Execute: %.9f s" % tcheck)

        pre_inventory = mat_inventory()
        write_json(MAT_PRE_JSON, pre_inventory)

        manifest = {
            "version": VERSION,
            "status": "PREEXECUTE_READY",
            "run_stamp": RUN_STAMP,
            "project": PROJECT_KEY,
            "model": MODEL_KEY,
            "source_model_file": KNOWN_CURRENT_MODEL_FILE,
            "source_sha256": source_identity["current_sha256"],
            "source_sha_policy": source_identity["policy"],
            "step_s": EXPECTED_STEP_S,
            "trial": {
                "transparent_regression": False,
                "pickup_target_pu": INITIAL_VALUES["AA15_S14V2_CFG_PICKUP_TARGET_PU"],
                "ess2_coord_authority_pu": INITIAL_VALUES["AA15_S14V2_CFG_ESS2_COORD_AUTH_PU"],
                "pickup_pref_min_pu": INITIAL_VALUES["CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU"],
                "pickup_perr_max_pu": INITIAL_VALUES["CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU"],
                "pickup_stable_dwell_s": INITIAL_VALUES["CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S"],
                "post_state7_observe_s": POST_LOCAL_RESTORED_OBSERVE_S,
                "global_deadline_s": GLOBAL_DEADLINE_S,
                "secondary_enabled": False,
            },
            "timing_policy": {
                "model_internal": "S14 V2 state/event driven; proven Stage1=2.5s and Stage2 pre-close=4.0s are inside model",
                "python": "Target-clock checkpoints only; no host-wall-clock physical timing",
                "adaptive_end": "first local state7 + 12s when possible, bounded by 45s",
            },
            "parameter_paths": dict(param_paths),
            "optional_parameter_paths": dict(optional_param_paths),
            "initial_values": dict(INITIAL_VALUES),
            "optional_initial_values": {k: v for k, v in OPTIONAL_INITIAL_VALUES.items() if k in optional_param_paths},
            "mandatory_signal_paths": dict(signal_paths),
            "optional_signal_paths": dict(optional_signal_paths),
            "signal_resolution_records": dict(signal_resolution_records),
            "initial_signal_snapshot_before_write": initial_signal_snapshot,
            "opwrite_expected_current_build": {
                "G26": {"rows_including_target_time": 97, "dt_s": 0.0004, "var": "rootdiag_ev12_data"},
                "G27": {"rows_including_target_time": 63, "dt_s": 0.0004, "var": "rootdiag_ess2_data"},
                "G28": {"rows_including_target_time": 97, "dt_s": 0.0004, "var": "rootdiag_pv12_data"},
                "G29": {"rows_including_target_time": 69, "dt_s": 0.0004, "var": "d1_gfm_superpack_data"},
                "G30": {"rows_including_target_time": 129, "dt_s": 0.0010, "var": "freqdiag_ess1_data"},
            },
            "identity_policy": {
                "hard_gates": [
                    "canonical yanshou_V7 single-model project",
                    "current model K26_K50_CLEAN_P1",
                    "100-us target step and PAUSED t=0",
                    "current-Build parameter uniqueness and readback",
                    "current-Build mandatory signals unique/callable",
                    "BLACK_START mode/J1 open/ESS1 GFM/nonmasters GFL",
                    "legacy six-device Pref stays zero during S14 V2 physical recovery",
                    "Restore state/breaker/alpha semantic consistency",
                    "Secondary remains disabled",
                ],
                "record_only": ["whole-file SLX SHA256", "ordinary post-action V/f/I quality"],
            },
            "mat_inventory_pre_count": len(pre_inventory),
            "electrical_verdict": "NOT_EVALUATED_BY_RUNNER",
        }
        write_json(MANIFEST_FILE, manifest)

        # Formal trial: no host-side physical actions after first Execute.
        log("\n--- FORMAL MODEL-DRIVEN S14 V2 TRIAL START ---")
        for t in EARLY_OBSERVE_TIMES:
            run_to_pause(t)
            checkpoint("OBS_%s" % (("%.2f" % t).replace(".", "P")))

        target_after_state7 = None
        t = current_sim_time
        while t < GLOBAL_DEADLINE_S - 0.25 * EXPECTED_STEP_S:
            if first_state7_observed_s is not None and target_after_state7 is None:
                target_after_state7 = final_target_after_state7(first_state7_observed_s)
                log("[LOCAL RESTORED] first state7 @ %.6f s; adaptive final target=%.6f s" % (first_state7_observed_s, target_after_state7))

            if target_after_state7 is not None and t >= target_after_state7 - 0.25 * EXPECTED_STEP_S:
                break

            next_t = next_dense_target(t)
            if target_after_state7 is not None:
                next_t = min(next_t, target_after_state7)
            next_t = min(next_t, GLOBAL_DEADLINE_S)
            run_to_pause(next_t)
            checkpoint("OBS_%s" % (("%.2f" % next_t).replace(".", "P")))
            t = current_sim_time

        # If no state7 was observed, keep evidence and stop without inventing a PASS.
        if first_state7_observed_s is None:
            controlled_stop(
                "CAPTURE_COMPLETE_PICKUP_NOT_RESTORED_NO_ELECTRICAL_VERDICT",
                "ESS2 never reached model-qualified state7 before the formal observation deadline.",
            )

        # Final host-side semantic checks. Detailed handover chronology is authoritative in G29.
        s = checkpoint("FINAL_PAUSE")
        if int(round(s["restore_state"])) != 7:
            controlled_stop(
                "CAPTURE_COMPLETE_LOCAL_RESTORE_LOST_NO_ELECTRICAL_VERDICT",
                "ESS2 reached state7 earlier but did not remain in state7 at final pause.",
            )
        if s["restore_fail_code"] > 0.5:
            controlled_stop(
                "CAPTURE_COMPLETE_RESTORE_FAILCODE_NO_ELECTRICAL_VERDICT",
                "Restore failCode became nonzero before final pause.",
            )

        if "s14_substate" in s and int(round(s["s14_substate"])) != 60:
            controlled_stop(
                "CAPTURE_COMPLETE_HANDOVER_NOT_AT_PRIMARY_NO_ELECTRICAL_VERDICT",
                "S14 V2 did not finish in substate60 Primary-only; observed %.3f." % s["s14_substate"],
            )
        if "handover_beta" in s and s["handover_beta"] < 0.999:
            controlled_stop(
                "CAPTURE_COMPLETE_HANDOVER_BETA_INCOMPLETE_NO_ELECTRICAL_VERDICT",
                "Handover beta did not reach 1 by final pause.",
            )
        if "secondary_enable" in s and s["secondary_enable"] > 0.5:
            raise ContractFail("Secondary unexpectedly enabled at final pause.")

        manifest["formal_observation_result"] = {
            "first_state5_observed_s": first_state5_observed_s,
            "first_state6_observed_s": first_state6_observed_s,
            "first_state7_observed_s": first_state7_observed_s,
            "first_s14_substate50_observed_s": first_substate50_observed_s,
            "first_s14_substate60_observed_s": first_substate60_observed_s,
            "first_full_correction_observed_s": first_full_correction_observed_s,
            "final_restore_state": s["restore_state"],
            "final_restore_alpha": s["restore_alpha"],
            "final_restore_fail_code": s["restore_fail_code"],
            "final_breaker_cmd": s["ESS2_final_breaker_cmd"],
            "final_pmeas_pu": s["ess2_pmeas_pu"],
            "final_pref_eff_pu": s["ess2_pref_eff_pu"],
            "interpretation": (
                "Host proves only model/control chronology and preservation. "
                "G27/G29/G30 DirectMAT must judge fixed-P stability, beta handover quality, "
                "primary-only response, modal behavior, saturation and ESS1 burden."
            ),
        }
        finalize_manifest(
            "CAPTURE_COMPLETE_S14V2_PICKUP_HANDOVER_PRIMARY_NO_ELECTRICAL_VERDICT",
            notes=[
                "Single formal run only; no transparent regression.",
                "No host manual Stage/COMMIT/RELEASE/beta/correction writes after Execute.",
                "PV1/PV2/EV1/EV2 stayed physically isolated.",
                "Secondary frequency/voltage restoration stayed disabled.",
                "Model intentionally remains PAUSED; do NOT Reset before G27/G29/G30 DirectMAT.",
                "Check RT-LAB Overrun=0 manually.",
            ],
        )
        log("\n" + "=" * 118)
        log("S14 V2 FIXED-P PICKUP + SMOOTH HANDOVER + PRIMARY-ONLY CAPTURE COMPLETE")
        log("[NO ELECTRICAL VERDICT] Final judgment requires G27/G29/G30 DirectMAT.")
        log("[PAUSE] Model intentionally remains PAUSED at %.6f s." % current_sim_time)
        log("[DO NOT] Reset before preserving/analyzing MAT files.")
        log("[RUN DIR] %s" % RUN_DIR)
        log("=" * 118)

    except GateStop as gs:
        preserve_pause(gs.message)
        finalize_manifest(
            gs.status,
            notes=[
                gs.message,
                "Controlled stop: no host-side recovery action was issued.",
                "No automatic Reset/reconnect was issued.",
                "Preserve PAUSED state and analyze G27/G29/G30 MAT.",
            ],
        )
        log("\n" + "=" * 118)
        log("CONTROLLED STOP — EVIDENCE PRESERVED")
        log("STATUS : %s" % gs.status)
        log("REASON : %s" % gs.message)
        log("[DO NOT] Reset automatically.")
        log("[RUN DIR] %s" % RUN_DIR)
        log("=" * 118)
        return

    except Exception as exc:
        if not started:
            try:
                restore_preexecute_parameters()
            except Exception as restore_exc:
                log("[RESTORE FAILURE] %r" % restore_exc)
        else:
            preserve_pause("Runner exception after Execute; preserve evidence, no automatic Reset.")
            try:
                finalize_manifest(
                    "FAILED_POSTEXECUTE_EVIDENCE_PRESERVED",
                    notes=[
                        "Unexpected post-Execute runner/API exception: %r" % exc,
                        "Model was preserved PAUSED when possible.",
                        "No automatic Reset/reconnect was issued.",
                        "G27/G29/G30 DirectMAT may still be used for forensic evidence.",
                    ],
                )
            except Exception as manifest_exc:
                log("[WARNING] post-Execute evidence manifest failed: %r" % manifest_exc)
        raise


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        try:
            if _log is None:
                _log = open(LOG_FILE, "a", encoding="utf-8", buffering=1)
        except Exception:
            pass
        log("\nFAILED: %r" % exc)
        log(traceback.format_exc())
        try:
            if started:
                preserve_pause("Unhandled post-Execute exception.")
        except Exception:
            pass
        failure = {
            "version": VERSION,
            "status": "FAILED",
            "exception": repr(exc),
            "started": started,
            "runtime_written": runtime_written,
            "current_sim_time_s": current_sim_time,
            "run_dir": RUN_DIR,
        }
        try:
            write_host_csv()
            write_event_csv()
            write_json(os.path.join(RUN_DIR, "failure.json"), failure)
        except Exception:
            pass
    finally:
        release_controls()
        if _log is not None:
            try:
                _log.close()
            except Exception:
                pass
