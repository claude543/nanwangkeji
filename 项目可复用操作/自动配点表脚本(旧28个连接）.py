# -*- coding: utf-8 -*-
"""
BOARD15 RT-LAB Configuration：旧28点自动精确连接 R8
================================================

R8修复R7的“Both data points have the same direction”根因。

【R7错误】
R7把Board→Model的OpInput连接到了：
    .../<OpInput块>/OpInput/port1
这个路径是OpInput块“输出到模型”的动态信号，方向为 out。
而Modbus Holding Register的“From master”也是向模型输出，方向同样为 out。
因此RT-LAB正确拒绝：
    Both data points have the same direction (in / out)

【官方正确OpInput连接点】
RT-LAB官方Configuration示例明确：
    OpInput应连接其：
    <OpInput块>/In1/Value
而不是：
    <OpInput块>/OpInput/port1

因此R8冻结：
Board -> Model 12点：
    <MODEL>/SM_Master/<OpInput块名>/In1/Value

Model -> Board 16点：
    <MODEL>/SM_Master/V31_RTLAB_To_Board_Test16/<OpOutput块名>/OpOutput/port1

【安全流程】
1. 确认R3成功的140条仍完整；
2. 导出PRE连接备份；
3. 先只拿Modbus_4001_raw做“canary”单点验证；
4. canary成功后才批量补其余27点；
5. 导出POST；
6. 验证168个I/O点名全部存在；
7. 任一步失败则恢复PRE。

不修改Simulink模型，不修改I/O Interfaces，不Build。
"""

import os
import re
import sys
from datetime import datetime
import RtlabApi

PROJECT_HINT = "yanshou_V5"
IO_NAME_HINT = "Modbus Slave"

OLD_400 = [
    "Modbus_4001_raw","Modbus_4002_raw","Modbus_4003_raw","Modbus_4004_raw",
    "Modbus_4005_raw","Modbus_4006_raw","Modbus_4007_raw","Modbus_4008_raw",
    "Modbus_4009_raw","EXT_AGC_ENABLE_raw","CMD_SEQ_raw","BOARD_HEARTBEAT_raw",
]

OLD_401 = [
    "Op40101","Op40102","Op40103","Op40104","Op40105","Op40106","Op40107",
    "Op40108","Op40109","Op40110","Op40111","Op40112","Op40113","Op40114",
    "MODEL_STATUS_raw","RTLAB_HEARTBEAT_raw",
]

OLD28 = OLD_400 + OLD_401

CMD_40013_40064 = [
"Op40013_PV1_QREF_raw","Op40014_PV2_QREF_raw","Op40015_ESS1_QREF_raw","Op40016_ESS2_QREF_raw",
"Op40017_EV1_QREF_raw","Op40018_EV2_QREF_raw","Op40019_GRIDON_MASK_raw","Op40020_DROOP_MASK_raw",
"Op40021_PCC_BREAKER_REQUEST_CLOSE_raw","Op40022_FREF_TRIM_HZ_raw","Op40023_SYSTEM_MODE_raw",
"Op40024_SELECTED_MASTER_raw","Op40025_CONFIG_APPLIED_SEQ_raw","Op40026_CONFIG_STATUS_raw",
"Op40027_P_COORDINATION_MODE_STATUS_raw","Op40028_STRATEGY_ACTIVE_MASK_raw","Op40029_DOMAIN_VALID_MASK_raw",
"Op40030_COMM_STATUS_raw","Op40031_PV1_P_EXPECTED_KW_raw","Op40032_PV2_P_EXPECTED_KW_raw",
"Op40033_ESS1_P_EXPECTED_KW_raw","Op40034_ESS2_P_EXPECTED_KW_raw","Op40035_EV1_P_EXPECTED_KW_raw",
"Op40036_EV2_P_EXPECTED_KW_raw","Op40037_PV1_EXEC_RESIDUAL_KW_raw","Op40038_PV2_EXEC_RESIDUAL_KW_raw",
"Op40039_ESS1_EXEC_RESIDUAL_KW_raw","Op40040_ESS2_EXEC_RESIDUAL_KW_raw","Op40041_EV1_EXEC_RESIDUAL_KW_raw",
"Op40042_EV2_EXEC_RESIDUAL_KW_raw","Op40043_EXEC_STATE_PACKED_raw","Op40044_RESOURCE_QUALIFIED_MASK_raw",
"Op40045_PV1_EFFECTIVE_CAP_KW_raw","Op40046_PV2_EFFECTIVE_CAP_KW_raw","Op40047_ESS1_EFFECTIVE_CAP_KW_raw",
"Op40048_ESS2_EFFECTIVE_CAP_KW_raw","Op40049_EV1_EFFECTIVE_CAP_KW_raw","Op40050_EV2_EFFECTIVE_CAP_KW_raw",
"Op40051_PV1_TRUST_PU_raw","Op40052_PV2_TRUST_PU_raw","Op40053_ESS1_TRUST_PU_raw",
"Op40054_ESS2_TRUST_PU_raw","Op40055_EV1_TRUST_PU_raw","Op40056_EV2_TRUST_PU_raw",
"Op40057_COORD_RECOVERY_STATE_raw","Op40058_REALLOC_ACTIVE_MASK_raw","Op40059_REALLOC_REMAIN_KW_raw",
"Op40060_PCC_RX_KW_raw","Op40061_METHOD_VARIANT_STATUS_raw","Op40062_RECON_EVENT_SEQ_raw",
"Op40063_FUTURE_DIAG_01_raw","Op40064_FUTURE_DIAG_02_raw"
]

MEAS_40117_40124 = [
"Op40117_PCC_PHASE_raw","Op40118_GRID_V_raw","Op40119_GRID_F_raw","Op40120_GRID_PHASE_raw",
"Op40121_PHASE_VALID_raw","Op40122_EXEC_MODE_STATUS_raw","Op40123_EXEC_SYSTEM_MODE_raw",
"Op40124_CONFIG_SEQ_raw"
]

RUNTIME_NAMES = [
"CONFIG_SEQ_ECHO","P_COORDINATION_MODE","STRATEGY_ENABLE_MASK","P_OBJECTIVE_MODE",
"CONTROL_MASTER_ENABLE","AGC_ENABLE","MODE_ACTUATION_ENABLE","PCC_BREAKER_ACTUATION_ENABLE",
"BLACKSTART_PREF_SEQUENCE_ENABLE","BLACKSTART_MASTER","ISLAND_MASTER","RECOVERY_REQUEST","Q_SIGN_GAIN",
"P_UNIT_KW","P_DEAD_KW","SOC_MIN","SOC_MAX","TS_AGC_MS","PV_INIT_KW","EV_INIT_KW",
"DEMAND_WINDOW_S","DEMAND_LIMIT_KW","AGC_ERROR_BAND_PCT","V_NOM_V","AVC_V_DEADBAND_PU",
"AVC_Q_LIMIT_KVAR","ANTI_REVERSE_LIMIT_KW","ANTI_REVERSE_DEADBAND_KW","ISLAND_FREQ_DEV_HZ",
"ISLAND_V_DEV_PU","SMOOTH_RATE_LIMIT_PCT_PER_MIN","PV_FLUCT_TRIGGER_PCT","TIE_TARGET_KW",
"UV_THRESHOLD_PU","UF_THRESHOLD_HZ","LOAD_SHED_STEP_KW","PEAK_THRESHOLD_KW","VALLEY_THRESHOLD_KW",
"PLAN_INTERVAL_S","EXPORT_LIMIT_KW","RENEWABLE_TARGET_PCT","BLACKSTART_ENABLE","SWITCH_ENABLE",
"OPT_WEIGHT_COST","OPT_WEIGHT_CARBON","OPT_WEIGHT_RENEWABLE","OPT_WEIGHT_TIE","OPT_WEIGHT_SOC",
"SYNC_DV_MAX_PU","SYNC_DF_MAX_HZ","SYNC_DTHETA_MAX_DEG","SYNC_STABLE_MS","RECLOSE_HOLD_MS",
"FREF_KTHETA_HZ_PER_DEG","FREF_KDF","FREF_TRIM_MAX_HZ","METHOD_VARIANT","EXEC_ERR_ENTER_PU",
"EXEC_ERR_CLEAR_PU","EXEC_CONFIRM_MS","RECOVERY_STABLE_MS","RESPONSE_TIMEOUT_MS",
"PV1_EXPECT_DELAY_MS","PV2_EXPECT_DELAY_MS","ESS1_EXPECT_DELAY_MS","ESS2_EXPECT_DELAY_MS",
"EV1_EXPECT_DELAY_MS","EV2_EXPECT_DELAY_MS","PV1_EXPECT_TAU_MS","PV2_EXPECT_TAU_MS",
"ESS1_EXPECT_TAU_MS","ESS2_EXPECT_TAU_MS","EV1_EXPECT_TAU_MS","EV2_EXPECT_TAU_MS",
"CAPABILITY_MIN_PU","CAPABILITY_RESERVE_PU","TRUST_ALPHA","RECON_BLEND_GAIN","SOC_WEIGHT_GAIN",
"CONTROLLER_RESET_SEQ"
]

RUNTIME_40201_40280 = [
    "Op%d_%s_raw" % (40201+i, n) for i,n in enumerate(RUNTIME_NAMES)
]

NEW140 = CMD_40013_40064 + MEAS_40117_40124 + RUNTIME_40201_40280
ALL168 = OLD28 + NEW140


def log(msg=""):
    print(msg)
    sys.stdout.flush()


def norm(v):
    return "" if v is None else str(v).strip()


def canonical(s):
    return re.sub(r"\s+","",norm(s).replace("\\","/").lower())


def is_mapping(obj):
    return isinstance(obj,dict) or (
        hasattr(obj,"keys") and hasattr(obj,"__getitem__")
    )


def map_get_nonempty(obj, keys, default=""):
    if not is_mapping(obj):
        return default
    try:
        ks=list(obj.keys())
    except Exception:
        return default
    lookup={norm(k).lower():k for k in ks}
    for wanted in keys:
        wk=wanted.lower()
        if wk not in lookup:
            continue
        try:
            v=obj[lookup[wk]]
        except Exception:
            continue
        if norm(v):
            return v
    return default


def scalar_strings(obj):
    out=[]
    if obj is None:
        return out
    if isinstance(obj,str):
        if obj.strip():
            out.append(obj.strip())
        return out
    if is_mapping(obj):
        try:
            ks=list(obj.keys())
        except Exception:
            ks=[]
        for k in ks:
            try:
                out.extend(scalar_strings(obj[k]))
            except Exception:
                pass
        return out
    if isinstance(obj,(tuple,list)):
        for x in obj:
            out.extend(scalar_strings(x))
    return out


def unpack_signal(item):
    if is_mapping(item):
        return {
            "path":norm(map_get_nonempty(item,["path"])),
            "label":norm(map_get_nonempty(item,["label","name"])),
            "raw":item
        }
    vals=list(item) if isinstance(item,(tuple,list)) else []
    return {
        "path":norm(vals[2]) if len(vals)>2 else "",
        "label":norm(vals[3]) if len(vals)>3 else "",
        "raw":item
    }


def unpack_io(item):
    if is_mapping(item):
        return {
            "name":norm(map_get_nonempty(item,["name","uiName","alias"])),
            "type":norm(map_get_nonempty(item,["type","ioType"])),
            "subsystem":norm(map_get_nonempty(item,["subsystem","system","assignedSubsystem"])),
            "raw":item
        }
    vals=list(item) if isinstance(item,(tuple,list)) else []
    return {
        "name":norm(vals[0]) if len(vals)>0 else "",
        "type":norm(vals[2]) if len(vals)>2 else "",
        "subsystem":norm(vals[3]) if len(vals)>3 else "",
        "raw":item
    }


def unpack_iopoint(item):
    if is_mapping(item):
        return {
            "path":norm(map_get_nonempty(item,["path"])),
            "name":norm(map_get_nonempty(item,["uiName","name","alias","caption","label"])),
            "direction":norm(map_get_nonempty(item,["direction"])),
            "strings":scalar_strings(item),
            "raw":item
        }
    vals=list(item) if isinstance(item,(tuple,list)) else []
    return {
        "path":norm(vals[1]) if len(vals)>1 else "",
        "name":norm(vals[4]) if len(vals)>4 else "",
        "direction":norm(vals[3]) if len(vals)>3 else "",
        "strings":scalar_strings(item),
        "raw":item
    }


def choose_modbus(interfaces):
    exact=[x for x in interfaces if canonical(x["name"])==canonical(IO_NAME_HINT)]
    if len(exact)==1:
        return exact[0]
    cand=[]
    for x in interfaces:
        blob="|".join([x["name"],x["type"],x["subsystem"]]).lower()
        if "modbus" in blob:
            cand.append(x)
    if len(cand)==1:
        return cand[0]
    sm=[x for x in cand if "sm_master" in x["subsystem"].lower()]
    if len(sm)==1:
        return sm[0]
    raise RuntimeError("Cannot uniquely select Modbus I/O: %r" %
        [(x["name"],x["type"],x["subsystem"]) for x in cand])


def resolve_io(points,target):
    tc=canonical(target)
    hits=[]
    for p in points:
        vals=p["strings"]+[p["path"],p["name"]]
        for s in vals:
            if canonical(s)==tc:
                hits.append(p)
                break
            ps=norm(s).replace("\\","/")
            if ps.endswith("/"+target) or ("/"+target+"/") in ps:
                hits.append(p)
                break
    by={}
    for p in hits:
        by[canonical(p["path"])]=p
    return list(by.values())


def export_connections(path):
    RtlabApi.ExportConnections(path,True)


def restore_connections(path):
    RtlabApi.ImportConnections(path,True,False)


def read_text(path):
    for enc in ("utf-8-sig","utf-8","cp1252","latin1"):
        try:
            with open(path,"r",encoding=enc,errors="strict") as f:
                return f.read()
        except Exception:
            pass
    with open(path,"rb") as f:
        return f.read().decode("latin1",errors="replace")


def presence(path,names):
    txt=read_text(path)
    return {n:(n in txt) for n in names}


def infer_model_root():
    raw=RtlabApi.GetSignalsDescription()
    sigs=[unpack_signal(x) for x in raw]
    roots=[]
    for s in sigs:
        p=s["path"].replace("\\","/")
        if "/SM_Master/" in p:
            roots.append(p.split("/SM_Master/",1)[0])
    roots=sorted(set(roots))
    if len(roots)!=1:
        raise RuntimeError("Cannot uniquely infer model root: %r" % roots)
    return roots[0]


def old_model_path(root,name):
    if name in OLD_400:
        # OFFICIAL OpInput model datapoint path:
        # <OpInput block>/In1/Value
        return "%s/SM_Master/%s/In1/Value" % (root,name)

    # R5 dump directly proved this OpOutput structure.
    return "%s/SM_Master/V31_RTLAB_To_Board_Test16/%s/OpOutput/port1" % (root,name)


# =============================================================================
# START
# =============================================================================

log("="*88)
log("BOARD15 OLD28 AUTO-CONNECT R8 — CORRECT OpInput DIRECTION")
log("="*88)

stamp=datetime.now().strftime("%Y%m%d_%H%M%S")
script_dir=os.path.dirname(os.path.abspath(__file__))

RtlabApi.OpenProject(PROJECT_HINT,returnOnAmbiguity=True)

MODEL_ROOT=infer_model_root()
log("[MODEL ROOT] %s" % MODEL_ROOT)

interfaces=[unpack_io(x) for x in RtlabApi.GetIOInterfaces()]
io=choose_modbus(interfaces)
io_points=[unpack_iopoint(x) for x in RtlabApi.GetConnectionPointsForIO(io["name"])]

io_map={}
io_bad=[]

for name in OLD28:
    hits=resolve_io(io_points,name)
    if len(hits)!=1:
        io_bad.append((name,hits))
    else:
        io_map[name]=hits[0]

log("\n[OLD28 I/O PREFLIGHT]")
log("  matched=%d bad=%d" % (len(io_map),len(io_bad)))
if io_bad:
    for name,hits in io_bad:
        log("  BAD %-22s hits=%d" % (name,len(hits)))
    raise RuntimeError("Old28 I/O side is not unique. NO WRITE.")

# Log direction split before writing.
log("\n[I/O DIRECTIONS]")
for name in OLD_400:
    log("  BOARD->MODEL %-22s io_direction=%r model_endpoint=.../In1/Value" %
        (name,io_map[name]["direction"]))
for name in OLD_401:
    log("  MODEL->BOARD %-22s io_direction=%r model_endpoint=.../OpOutput/port1" %
        (name,io_map[name]["direction"]))

model_map={name:old_model_path(MODEL_ROOT,name) for name in OLD28}

log("\n[MODEL ENDPOINTS — FROZEN]")
for name in OLD400 if False else []:
    pass
for name in OLD28:
    log("  %-22s -> %s" % (name,model_map[name]))

# PRE backup and protect current R3 140.
pre_csv=os.path.join(script_dir,"BOARD15_connections_PRE_OLD28_R8_%s.csv" % stamp)
canary_csv=os.path.join(script_dir,"BOARD15_connections_CANARY_R8_%s.csv" % stamp)
post_csv=os.path.join(script_dir,"BOARD15_connections_POST_ALL168_R8_%s.csv" % stamp)

export_connections(pre_csv)
st140=presence(pre_csv,NEW140)
missing140=[n for n in NEW140 if not st140[n]]

log("\n[PROTECT R3 140]")
log("  expected=140 missing=%d" % len(missing140))
if missing140:
    for n in missing140:
        log("  "+n)
    raise RuntimeError("R3 140 connections are not intact. R8 will not write.")

oldstate=presence(pre_csv,OLD28)
already=[n for n in OLD28 if oldstate[n]]
todo=[n for n in OLD28 if not oldstate[n]]

log("\n[OLD28 CURRENT]")
log("  already=%d to_create=%d" % (len(already),len(todo)))

if not todo:
    log("[INFO] old28 already complete; skipping CreateConnection.")
else:
    # -------------------------------------------------------------------------
    # CANARY: test exactly one Board->Model OpInput using official In1/Value path
    # before touching remaining points.
    # -------------------------------------------------------------------------
    canary="Modbus_4001_raw"

    if canary in todo:
        log("\n[CANARY]")
        log("  model = %s" % model_map[canary])
        log("  io    = %s" % io_map[canary]["path"])

        try:
            RtlabApi.CreateConnection(
                model_map[canary],
                io_map[canary]["path"],
                False
            )
        except Exception as exc:
            log("[CANARY FAILED] %r" % (exc,))
            log("[ROLLBACK] restoring PRE...")
            try:
                restore_connections(pre_csv)
                log("[ROLLBACK PASS]")
            except Exception as rex:
                log("[ROLLBACK ERROR] %r" % (rex,))
            raise RuntimeError(
                "Official OpInput /In1/Value canary failed. PRE restored; "
                "no remaining old connection was attempted."
            )

        export_connections(canary_csv)
        cstate=presence(canary_csv,[canary])
        if not cstate[canary]:
            log("[CANARY VERIFY FAILED] rollback PRE...")
            restore_connections(pre_csv)
            raise RuntimeError("Canary CreateConnection returned but export did not contain it.")

        log("[CANARY PASS] official OpInput endpoint direction is correct.")

    # Recompute remaining after canary.
    current_csv=canary_csv if os.path.exists(canary_csv) else pre_csv
    curr=presence(current_csv,OLD28)
    rest=[n for n in OLD28 if not curr[n]]

    if rest:
        log("\n[CREATE REMAINING OLD POINTS]")
        log("  exact pairs=%d" % len(rest))

        model_refs=tuple(model_map[n] for n in rest)
        io_refs=tuple(io_map[n]["path"] for n in rest)

        try:
            RtlabApi.CreateConnection(model_refs,io_refs,False)
        except Exception as exc:
            log("[CREATE FAILED] %r" % (exc,))
            log("[ROLLBACK] restoring PRE...")
            try:
                restore_connections(pre_csv)
                log("[ROLLBACK PASS]")
            except Exception as rex:
                log("[ROLLBACK ERROR] %r" % (rex,))
                log("PRE remains: "+pre_csv)
            raise

# POST verify all168.
export_connections(post_csv)
allstate=presence(post_csv,ALL168)
missing168=[n for n in ALL168 if not allstate[n]]

log("\n[POST VERIFY ALL168]")
log("  expected=168 missing=%d" % len(missing168))

if missing168:
    for n in missing168:
        log("  "+n)
    log("[VERIFY FAILED] restoring PRE...")
    try:
        restore_connections(pre_csv)
        log("[ROLLBACK PASS]")
    except Exception as rex:
        log("[ROLLBACK ERROR] %r" % (rex,))
    raise RuntimeError("POST ALL168 verification failed; PRE restored.")

log("\n"+"="*88)
log("BOARD15 OLD28 AUTO-CONNECT R8 PASS")
log("="*88)
log("R3 new140 preserved = 140")
log("Old28 complete       = 28")
log("ALL168 verified      = 168")
log("")
log("PRE : "+pre_csv)
log("POST: "+post_csv)
log("")
log("NEXT:")
log("  1) Refresh RT-LAB Configuration.")
log("  2) Spot-check:")
log("       Modbus_4001_raw")
log("       EXT_AGC_ENABLE_raw")
log("       CMD_SEQ_raw")
log("       BOARD_HEARTBEAT_raw")
log("       Op40101")
log("       MODEL_STATUS_raw")
log("       RTLAB_HEARTBEAT_raw")
log("  3) If GUI matches, Configuration layer is complete.")
log("="*88)
