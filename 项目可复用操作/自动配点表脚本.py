# -*- coding: utf-8 -*-
"""
BOARD15 RT-LAB Configuration 自动精确连接 R3
===========================================

R3针对RT-LAB 2024.1实际返回结构进一步加固：

【R2失败的根因】
RT-LAB datapoint dict 可能同时包含：
    uiName = ""
    name   = "Op40274_EV2_EXPECT_TAU_MS_raw"
R2看到uiName键存在就返回空字符串，没有继续读取name，造成GUI明明有点，
脚本却把这些点判成missing。

【R3三层唯一匹配】
1. exact text：目标名与raw dict中任意非空字符串字段精确相等；
2. canonical name：去空格/大小写/斜杠后精确匹配；
3. register token：从目标提取40013/40117/40274这类五位寄存器号，
   在raw datapoint所有字符串字段中寻找唯一同号点。

只有140/140全部唯一匹配，才会执行任何CreateConnection。

【额外保护】
- 连接前ExportConnections备份；
- 支持partial run，只补缺失连接；
- CreateConnection失败自动回滚；
- 成功后POST ExportConnections；
- POST CSV必须包含全部140个目标alias，否则自动回滚；
- 任何preflight失败都会导出：
    BOARD15_IO_POINT_DUMP_R3_*.txt
  里面保存GetIOInterfaces和GetConnectionPointsForIO的完整raw返回，便于一次定位。

本轮只连接新增140点：
  40013~40064 = 52
  40117~40124 = 8
  40201~40280 = 80

旧28点保持原连接不动。
"""

import os
import re
import sys
from datetime import datetime

import RtlabApi


# ============================================================================
# 0. CONFIG
# ============================================================================

PROJECT_HINT = "yanshou_V5"
IO_NAME_HINT = "Modbus Slave"
CONNECT_OLD_28 = False


# ============================================================================
# 1. TARGETS
# ============================================================================

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
    "Op%d_%s_raw" % (40201+i, n)
    for i, n in enumerate(RUNTIME_NAMES)
]

OLD_400 = [
"Modbus_4001_raw","Modbus_4002_raw","Modbus_4003_raw","Modbus_4004_raw","Modbus_4005_raw",
"Modbus_4006_raw","Modbus_4007_raw","Modbus_4008_raw","Modbus_4009_raw","EXT_AGC_ENABLE_raw",
"CMD_SEQ_raw","BOARD_HEARTBEAT_raw"
]

OLD_401 = [
"Op40101","Op40102","Op40103","Op40104","Op40105","Op40106","Op40107","Op40108",
"Op40109","Op40110","Op40111","Op40112","Op40113","Op40114","MODEL_STATUS_raw","RTLAB_HEARTBEAT_raw"
]


# ============================================================================
# 2. BASIC HELPERS
# ============================================================================

def log(msg=""):
    print(msg)
    sys.stdout.flush()


def norm(v):
    if v is None:
        return ""
    return str(v).strip()


def canonical(s):
    s = norm(s).replace("\\", "/").lower()
    # Remove whitespace only; preserve underscores/digits because they are meaningful.
    return re.sub(r"\s+", "", s)


def reg_token(name):
    m = re.search(r"(?<!\d)(40[012]\d{2})(?!\d)", norm(name))
    return m.group(1) if m else ""


def is_mapping(obj):
    return isinstance(obj, dict) or (
        hasattr(obj, "keys") and hasattr(obj, "__getitem__")
    )


def iter_scalar_strings(obj):
    """
    Recursively collect all scalar string-like content from dict/tuple/list/object repr.
    This intentionally does NOT trust one particular RT-LAB field name.
    """
    out = []

    if obj is None:
        return out

    if isinstance(obj, str):
        if obj.strip():
            out.append(obj.strip())
        return out

    if isinstance(obj, bytes):
        try:
            v = obj.decode("utf-8", errors="replace").strip()
            if v:
                out.append(v)
        except Exception:
            pass
        return out

    if is_mapping(obj):
        try:
            keys = list(obj.keys())
        except Exception:
            keys = []

        for k in keys:
            # Key names are diagnostic only; do not use them to match target names.
            try:
                v = obj[k]
            except Exception:
                continue
            out.extend(iter_scalar_strings(v))
        return out

    if isinstance(obj, (tuple, list)):
        for v in obj:
            out.extend(iter_scalar_strings(v))
        return out

    # Numeric/bool/etc are not useful for name matching.
    return out


def mapping_get_nonempty_ci(obj, keys, default=""):
    """
    Important R3 fix:
    If uiName exists but is empty, continue to name/alias/caption instead of returning "".
    """
    if not is_mapping(obj):
        return default

    try:
        real_keys = list(obj.keys())
    except Exception:
        return default

    lookup = {norm(k).lower(): k for k in real_keys}

    for wanted in keys:
        wk = wanted.lower()
        if wk not in lookup:
            continue

        try:
            value = obj[lookup[wk]]
        except Exception:
            continue

        if norm(value) != "":
            return value

    return default


# ============================================================================
# 3. RT-LAB RETURN PARSERS
# ============================================================================

def unpack_io_info(item):
    if is_mapping(item):
        return {
            "name": norm(mapping_get_nonempty_ci(item, ["name", "uiName", "alias"])),
            "guid": norm(mapping_get_nonempty_ci(item, ["guid", "id"])),
            "type": norm(mapping_get_nonempty_ci(item, ["type", "ioType"])),
            "subsystem": norm(mapping_get_nonempty_ci(
                item, ["subsystem", "system", "assignedSubsystem"]
            )),
            "strings": iter_scalar_strings(item),
            "raw": item,
        }

    if isinstance(item, (tuple, list)):
        vals = list(item)
        return {
            "name": norm(vals[0]) if len(vals)>0 else "",
            "guid": norm(vals[1]) if len(vals)>1 else "",
            "type": norm(vals[2]) if len(vals)>2 else "",
            "subsystem": norm(vals[3]) if len(vals)>3 else "",
            "strings": iter_scalar_strings(item),
            "raw": item,
        }

    return {
        "name": "",
        "guid": "",
        "type": "",
        "subsystem": "",
        "strings": iter_scalar_strings(item),
        "raw": item,
    }


def unpack_point(item):
    if is_mapping(item):
        return {
            "path": norm(mapping_get_nonempty_ci(item, ["path", "Path"])),
            "uiName": norm(mapping_get_nonempty_ci(
                item, ["uiName", "name", "alias", "caption", "label"]
            )),
            "name": norm(mapping_get_nonempty_ci(
                item, ["name", "uiName", "alias", "caption", "label"]
            )),
            "alias": norm(mapping_get_nonempty_ci(item, ["alias"])),
            "direction": norm(mapping_get_nonempty_ci(item, ["direction"])),
            "type": norm(mapping_get_nonempty_ci(item, ["type"])),
            "strings": iter_scalar_strings(item),
            "raw": item,
        }

    if isinstance(item, (tuple, list)):
        vals = list(item)
        return {
            "path": norm(vals[1]) if len(vals)>1 else "",
            "uiName": norm(vals[4]) if len(vals)>4 else "",
            "name": "",
            "alias": "",
            "direction": norm(vals[3]) if len(vals)>3 else "",
            "type": norm(vals[2]) if len(vals)>2 else "",
            "strings": iter_scalar_strings(item),
            "raw": item,
        }

    return {
        "path": "",
        "uiName": "",
        "name": "",
        "alias": "",
        "direction": "",
        "type": "",
        "strings": iter_scalar_strings(item),
        "raw": item,
    }


def choose_modbus_interface(interfaces):
    exact = [
        x for x in interfaces
        if canonical(x["name"]) == canonical(IO_NAME_HINT)
    ]
    if len(exact) == 1:
        return exact[0]

    candidates = []
    for x in interfaces:
        blob = " | ".join(x["strings"] + [x["name"], x["type"], x["subsystem"]]).lower()
        if "modbus" in blob:
            candidates.append(x)

    if len(candidates) == 1:
        return candidates[0]

    sm = [
        x for x in candidates
        if "sm_master" in x["subsystem"].lower()
    ]
    if len(sm) == 1:
        return sm[0]

    raise RuntimeError(
        "Cannot uniquely select Modbus interface. Candidates=%r"
        % [(x["name"], x["type"], x["subsystem"]) for x in candidates]
    )


# ============================================================================
# 4. THREE-LAYER DATAPOINT MATCHING
# ============================================================================

def exact_strings(point):
    vals = []
    vals.extend(point["strings"])
    vals.extend([
        point["path"], point["uiName"], point["name"],
        point["alias"], point["direction"], point["type"]
    ])
    return [norm(x) for x in vals if norm(x)]


def match_score(point, target):
    """
    Return (score, reason)
      300 exact raw-field equality
      200 canonical exact equality / path terminal match
      100 unique same five-digit register token
        0 no match
    """
    target_n = norm(target)
    target_c = canonical(target_n)
    strings = exact_strings(point)

    # Layer 1: exact equality.
    for s in strings:
        if s == target_n:
            return 300, "exact-field"

    # Layer 2: canonical equality or path contains exact node.
    for s in strings:
        cs = canonical(s)
        if cs == target_c:
            return 200, "canonical-exact"

        ps = s.replace("\\", "/")
        if ps.endswith("/" + target_n) or ("/" + target_n + "/") in ps:
            return 200, "path-node"

    # Layer 3: register token.
    tr = reg_token(target_n)
    if tr:
        tokens = set()
        for s in strings:
            for m in re.finditer(r"(?<!\d)(40[012]\d{2})(?!\d)", s):
                tokens.add(m.group(1))
        if tr in tokens:
            return 100, "register-token"

    return 0, ""


def unique_match(points, target):
    scored = []
    for p in points:
        score, reason = match_score(p, target)
        if score > 0:
            scored.append((score, reason, p))

    if not scored:
        return None, [], "missing"

    best = max(x[0] for x in scored)
    best_hits = [x for x in scored if x[0] == best]

    if len(best_hits) != 1:
        return None, best_hits, "duplicate"

    return best_hits[0], best_hits, "ok"


# ============================================================================
# 5. CSV BACKUP / POST CHECK
# ============================================================================

def export_connections(path):
    RtlabApi.ExportConnections(path, True)


def restore_connections(path):
    RtlabApi.ImportConnections(path, True, False)


def read_text(path):
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin1"):
        try:
            with open(path, "r", encoding=enc, errors="strict") as f:
                return f.read()
        except Exception:
            pass

    with open(path, "rb") as f:
        return f.read().decode("latin1", errors="replace")


def alias_presence(path, targets):
    txt = read_text(path)
    return {t: (t in txt) for t in targets}


# ============================================================================
# 6. DIAGNOSTIC DUMP
# ============================================================================

def write_raw_dump(script_dir, stamp, interfaces_raw, points_raw, points):
    path = os.path.join(
        script_dir,
        "BOARD15_IO_POINT_DUMP_R3_%s.txt" % stamp
    )

    with open(path, "w", encoding="utf-8") as f:
        f.write("=== GetIOInterfaces RAW ===\n")
        for i, x in enumerate(interfaces_raw):
            f.write("[%d] type=%s\n%r\n\n" % (i, type(x).__name__, x))

        f.write("\n=== GetConnectionPointsForIO RAW ===\n")
        for i, x in enumerate(points_raw):
            f.write("[%d] type=%s\n%r\n\n" % (i, type(x).__name__, x))

        f.write("\n=== PARSED POINT SUMMARY ===\n")
        for i, p in enumerate(points):
            f.write(
                "[%d] path=%r uiName=%r name=%r alias=%r direction=%r type=%r\n"
                % (
                    i, p["path"], p["uiName"], p["name"],
                    p["alias"], p["direction"], p["type"]
                )
            )
            f.write("     strings=%r\n" % p["strings"])

    return path


# ============================================================================
# 7. START
# ============================================================================

log("="*82)
log("BOARD15 RT-LAB CONFIGURATION AUTO-CONNECT R3")
log("="*82)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
script_dir = os.path.dirname(os.path.abspath(__file__))

project_id = RtlabApi.OpenProject(
    PROJECT_HINT,
    returnOnAmbiguity=True
)
log("[PROJECT] OpenProject OK: %s" % project_id)


# ============================================================================
# 8. IO INTERFACE
# ============================================================================

interfaces_raw = RtlabApi.GetIOInterfaces()
interfaces = [unpack_io_info(x) for x in interfaces_raw]

log("\n[I/O INTERFACES]")
for i, x in enumerate(interfaces):
    log(
        "  %d. name=%r type=%r subsystem=%r raw_type=%s"
        % (
            i+1, x["name"], x["type"], x["subsystem"],
            type(x["raw"]).__name__
        )
    )

if not interfaces:
    raise RuntimeError("GetIOInterfaces returned no interface.")

io = choose_modbus_interface(interfaces)

log("\n[SELECTED MODBUS]")
log("  name      = %r" % io["name"])
log("  type      = %r" % io["type"])
log("  subsystem = %r" % io["subsystem"])


# ============================================================================
# 9. DATAPOINTS
# ============================================================================

points_raw = RtlabApi.GetConnectionPointsForIO(io["name"])
points = [unpack_point(x) for x in points_raw]

log("\n[DATAPOINTS]")
log("  raw count    = %d" % len(points_raw))
log("  parsed count = %d" % len(points))

if not points:
    raise RuntimeError("GetConnectionPointsForIO returned no datapoint.")

log("\n[FIRST 10 PARSED POINTS]")
for i, p in enumerate(points[:10]):
    log(
        "  %2d path=%r | uiName=%r | name=%r | alias=%r | dir=%r"
        % (
            i+1, p["path"], p["uiName"], p["name"],
            p["alias"], p["direction"]
        )
    )


# ============================================================================
# 10. TARGET PREFLIGHT
# ============================================================================

targets = []
targets.extend(CMD_40013_40064)
targets.extend(MEAS_40117_40124)
targets.extend(RUNTIME_40201_40280)

if CONNECT_OLD_28:
    targets.extend(OLD_400)
    targets.extend(OLD_401)

expected = 168 if CONNECT_OLD_28 else 140

if len(targets) != expected:
    raise RuntimeError(
        "Internal target count wrong: %d != %d"
        % (len(targets), expected)
    )

if len(set(targets)) != len(targets):
    raise RuntimeError("Internal target list contains duplicates.")

mapping = []
missing = []
dupes = []

score_counts = {300:0, 200:0, 100:0}

for t in targets:
    hit, candidates, status = unique_match(points, t)

    if status == "missing":
        missing.append(t)
        continue

    if status == "duplicate":
        dupes.append((t, candidates))
        continue

    score, reason, p = hit
    score_counts[score] += 1

    if not p["path"]:
        missing.append(t + " [matched but datapoint path empty]")
        continue

    mapping.append((t, p["path"], score, reason, p))

log("\n[PREFLIGHT]")
log("  targets       = %d" % len(targets))
log("  matched       = %d" % len(mapping))
log("  missing       = %d" % len(missing))
log("  duplicates    = %d" % len(dupes))
log("  exact-field   = %d" % score_counts[300])
log("  canonical     = %d" % score_counts[200])
log("  register-only = %d" % score_counts[100])

if missing:
    log("\n[MISSING]")
    for x in missing:
        log("  " + x)

if dupes:
    log("\n[DUPLICATES]")
    for t, candidates in dupes:
        log("  " + t)
        for score, reason, p in candidates:
            log(
                "    score=%d reason=%s path=%r uiName=%r name=%r alias=%r"
                % (
                    score, reason, p["path"], p["uiName"],
                    p["name"], p["alias"]
                )
            )

if missing or dupes or len(mapping) != len(targets):
    dump = write_raw_dump(
        script_dir, stamp, interfaces_raw, points_raw, points
    )
    log("\n[NO WRITE] preflight failed; no connection created.")
    log("[RAW DUMP] %s" % dump)

    raise RuntimeError(
        "R3 preflight did not uniquely resolve all target datapoints. "
        "NO CONNECTION HAS BEEN CREATED."
    )


# ============================================================================
# 11. SAFETY RULE FOR REGISTER-ONLY FALLBACK
# ============================================================================

# Register-token matching is allowed only if the matched IO point contains the exact
# same five-digit register token and it is unique. Print every fallback so user can audit.
fallbacks = [x for x in mapping if x[2] == 100]

if fallbacks:
    log("\n[REGISTER-TOKEN FALLBACKS]")
    for t, path, score, reason, p in fallbacks:
        log("  %-46s -> %s" % (t, path))

log("\n[MAPPING SAMPLE]")
sample = mapping[:6] + mapping[-6:]
for t, path, score, reason, p in sample:
    log(
        "  MODEL %-46s <-> IO %-60s [%s]"
        % (t, path, reason)
    )


# ============================================================================
# 12. PRE CONNECTION BACKUP
# ============================================================================

pre_csv = os.path.join(
    script_dir,
    "BOARD15_connections_PRE_R3_%s.csv" % stamp
)

post_csv = os.path.join(
    script_dir,
    "BOARD15_connections_POST_R3_%s.csv" % stamp
)

export_connections(pre_csv)

log("\n[PRE BACKUP]")
log("  " + pre_csv)


# ============================================================================
# 13. PARTIAL-RUN SUPPORT
# ============================================================================

pre_presence = alias_presence(pre_csv, targets)

already = [t for t in targets if pre_presence[t]]
todo = [t for t in targets if not pre_presence[t]]

map_by_target = {
    t: path for t, path, score, reason, p in mapping
}

log("\n[CURRENT CONNECTION STATE]")
log("  target total    = %d" % len(targets))
log("  already present = %d" % len(already))
log("  to create       = %d" % len(todo))


# ============================================================================
# 14. CREATE EXACT PAIRS
# ============================================================================

if todo:
    model_paths = tuple(todo)
    io_paths = tuple(map_by_target[t] for t in todo)

    log("\n[CREATE]")
    log("  exact pairs = %d" % len(todo))

    try:
        RtlabApi.CreateConnection(
            model_paths,
            io_paths,
            False
        )

    except Exception as exc:
        log("\n[CREATE FAILED] %r" % (exc,))
        log("[ROLLBACK] restoring PRE connections...")

        try:
            restore_connections(pre_csv)
            log("[ROLLBACK PASS]")
        except Exception as rex:
            log("[ROLLBACK ERROR] %r" % (rex,))
            log("PRE CSV remains at: %s" % pre_csv)

        raise
else:
    log("\n[CREATE] nothing to add; all targets already present.")


# ============================================================================
# 15. POST EXPORT + VERIFY
# ============================================================================

export_connections(post_csv)

post_presence = alias_presence(post_csv, targets)
post_missing = [t for t in targets if not post_presence[t]]

log("\n[POST VERIFY]")
log("  expected target aliases = %d" % len(targets))
log("  missing in POST CSV      = %d" % len(post_missing))

if post_missing:
    for t in post_missing:
        log("  " + t)

    log("[POST VERIFY FAILED] rolling back PRE connections...")

    try:
        restore_connections(pre_csv)
        log("[ROLLBACK PASS]")
    except Exception as rex:
        log("[ROLLBACK ERROR] %r" % (rex,))
        log("PRE CSV remains at: %s" % pre_csv)

    raise RuntimeError(
        "POST export does not contain all target aliases; "
        "connections rolled back."
    )


# ============================================================================
# 16. FINAL
# ============================================================================

try:
    desc = RtlabApi.GetConnectionsDescription()
    log(
        "[GetConnectionsDescription] total current connections=%d"
        % len(desc)
    )
except Exception as exc:
    log(
        "[WARNING] GetConnectionsDescription check unavailable: %r"
        % (exc,)
    )

log("\n" + "="*82)
log("BOARD15 CONFIGURATION AUTO-CONNECT R3 PASS")
log("="*82)
log("Target verified      = %d" % len(targets))
log("Already before run   = %d" % len(already))
log("Newly created        = %d" % len(todo))
log("Exact field matches  = %d" % score_counts[300])
log("Canonical matches    = %d" % score_counts[200])
log("Register fallbacks   = %d" % score_counts[100])
log("")
log("PRE backup : %s" % pre_csv)
log("POST export: %s" % post_csv)
log("")
log("NEXT:")
log("  1) Return to Configuration and Refresh/Force Refresh.")
log("  2) Spot-check:")
log("       Op40013_PV1_QREF_raw")
log("       Op40117_PCC_PHASE_raw")
log("       Op40201_CONFIG_SEQ_ECHO_raw")
log("       Op40280_CONTROLLER_RESET_SEQ_raw")
log("  3) Do NOT Build until these spot-checks are correct.")
log("="*82)
