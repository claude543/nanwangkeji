#ifndef BOARD15_CONTROLLER_API_V0_1_H
#define BOARD15_CONTROLLER_API_V0_1_H

/*
 * BOARD15 controller public data interface
 * Design06 V0.1 - interface freeze candidate
 *
 * IMPORTANT:
 * - No Modbus addresses/raw counts in this header.
 * - Internal PCC sign: + export, - import.
 * - Device order: PV1, PV2, ESS1, ESS2, EV1, EV2.
 * - This is an interface skeleton for C-migration review, not yet the
 *   final board build package.
 */

#include <stdint.h>

#define CTRL_DEVICE_COUNT   6u
#define CTRL_STRATEGY_COUNT 15u

typedef enum
{
    DEV_PV1 = 0,
    DEV_PV2 = 1,
    DEV_ESS1 = 2,
    DEV_ESS2 = 3,
    DEV_EV1 = 4,
    DEV_EV2 = 5
} DeviceIndex;

typedef enum
{
    SYS_GRID_CONNECTED_NORMAL = 0,
    SYS_GRID_CONNECTED_EMERGENCY = 1,
    SYS_ISLANDING = 2,
    SYS_ISLANDED = 3,
    SYS_BLACK_START = 4,
    SYS_RESYNCHRONIZATION = 5,
    SYS_FAULT_SAFE = 6
} SystemMode;

typedef enum
{
    MASTER_NONE = 0,
    MASTER_ESS1 = 1,
    MASTER_ESS2 = 2
} SelectedMaster;

typedef enum
{
    P_COORD_BASELINE = 0,
    P_COORD_EXECUTION_AWARE = 1
} PCoordinationMode;

typedef enum
{
    METHOD_BASELINE = 0,
    METHOD_ASSESSMENT = 1,
    METHOD_ASSESSMENT_RECOVERY = 2,
    METHOD_FULL = 3
} MethodVariant;

enum
{
    SIG_VALID_PCC_P        = (1u << 0),
    SIG_VALID_PCC_Q        = (1u << 1),
    SIG_VALID_PCC_V        = (1u << 2),
    SIG_VALID_PCC_F        = (1u << 3),
    SIG_VALID_PV_MAX       = (1u << 4),
    SIG_VALID_ESS_SOC      = (1u << 5),
    SIG_VALID_P_MEAS       = (1u << 6),
    SIG_VALID_GRID_V       = (1u << 7),
    SIG_VALID_GRID_F       = (1u << 8),
    SIG_VALID_PCC_PHASE    = (1u << 9),
    SIG_VALID_GRID_PHASE   = (1u << 10),
    SIG_VALID_PHASE_FLAG   = (1u << 11),
    SIG_VALID_EXEC_MODE    = (1u << 12),
    SIG_VALID_EXEC_SYS     = (1u << 13),
    SIG_VALID_MODEL_STATUS = (1u << 14),
    SIG_VALID_RT_HEARTBEAT = (1u << 15)
};

typedef struct
{
    double monotonic_time_s;

    double pcc_p_kw;       /* + export, - import */
    double pcc_q_kvar;
    double pcc_v_rms_v;
    double pcc_freq_hz;
    double pcc_phase_deg;

    double grid_v_rms_v;
    double grid_freq_hz;
    double grid_phase_deg;
    uint8_t phase_valid;

    double pv_max_kw[2];
    double ess_soc[2];
    double p_meas_kw[CTRL_DEVICE_COUNT];

    uint16_t exec_mode_status_raw;
    uint8_t exec_system_mode;

    uint8_t snapshot_fresh;
    uint8_t snapshot_transport_valid;
    uint32_t signal_valid_mask;

    uint8_t measurement_channel_valid;
    uint8_t command_channel_valid;
    uint8_t controller_enabled;
    uint8_t comm_ok_for_strategy;

    uint16_t model_status_raw;
    uint16_t rtlab_heartbeat;

} ControllerInput;

typedef struct
{
    uint8_t p_coordination_mode;
    uint16_t strategy_enable_mask;
    uint8_t p_objective_mode;

    uint8_t control_master_enable;
    uint8_t agc_enable;

    uint8_t mode_actuation_enable;
    uint8_t pcc_breaker_actuation_enable;

    int8_t q_sign_gain;
} FrameworkConfig;

typedef struct
{
    uint8_t blackstart_pref_sequence_enable;
    uint8_t blackstart_master;
    uint8_t island_master;
    uint8_t recovery_request;
} ModeExecutionConfig;

typedef struct
{
    double demand_window_s;
    double demand_limit_kw;
    double agc_error_band_pct;

    double v_nom_v;
    double avc_v_deadband_pu;
    double avc_q_limit_kvar;

    double anti_reverse_limit_kw;
    double anti_reverse_deadband_kw;

    double island_freq_dev_hz;
    double island_v_dev_pu;

    double smooth_rate_limit_pct_per_min;
    double pv_fluct_trigger_pct;

    double tie_target_kw;

    double uv_threshold_pu;
    double uf_threshold_hz;
    double load_shed_step_kw;

    double peak_threshold_kw;
    double valley_threshold_kw;

    double plan_interval_s;
    double export_limit_kw;
    double renewable_target_pct;

    uint8_t blackstart_enable;
    uint8_t switch_enable;

    double opt_weight_cost;
    double opt_weight_carbon;
    double opt_weight_renewable;
    double opt_weight_tie;
    double opt_weight_soc;
} StrategyConfig;

typedef struct
{
    double p_unit_kw;
    double p_dead_kw;
    double soc_min;
    double soc_max;
    double ts_agc_s;
    double pv_init_kw;
    double ev_init_kw;
} BaselineAgcConfig;

typedef struct
{
    double sync_dv_max_pu;
    double sync_df_max_hz;
    double sync_dtheta_max_deg;

    double sync_stable_s;
    double reclose_hold_s;

    double fref_ktheta_hz_per_deg;
    double fref_kdf;
    double fref_trim_max_hz;
} ResyncConfig;

typedef struct
{
    uint8_t method_variant;

    double exec_err_enter_pu;
    double exec_err_clear_pu;

    double exec_confirm_s;
    double recovery_stable_s;
    double response_timeout_s;

    double expect_delay_s[CTRL_DEVICE_COUNT];
    double expect_tau_s[CTRL_DEVICE_COUNT];

    double capability_min_pu;
    double capability_reserve_pu;
    double trust_alpha;
    double recon_blend_gain;
    double soc_weight_gain;
} ExecutionAwareConfig;

typedef struct
{
    uint16_t config_seq;
    uint16_t controller_reset_seq;

    FrameworkConfig framework;
    ModeExecutionConfig mode_execution;
    StrategyConfig strategy;
    BaselineAgcConfig baseline_agc;
    ResyncConfig resync;
    ExecutionAwareConfig execution_aware;
} ControllerConfig;

typedef struct
{
    double pref_pu[CTRL_DEVICE_COUNT];
    double qref_pu[CTRL_DEVICE_COUNT];

    uint8_t grid_on[CTRL_DEVICE_COUNT];       /* 1=GFL, 0=GFM */
    uint8_t droop_enable[CTRL_DEVICE_COUNT];

    uint8_t pcc_breaker_request_close;

    double fref_trim_hz;

    uint8_t system_mode;
    uint8_t selected_master;

    int8_t agc_status;
    double agc_dp_kw;
    double agc_remain_kw;

    uint8_t output_valid;
} ControllerOutput;

typedef struct
{
    double strategy_status[CTRL_STRATEGY_COUNT];
    double strategy_alarm[CTRL_STRATEGY_COUNT];
    double strategy_metric[CTRL_STRATEGY_COUNT];
    double strategy_cmd[CTRL_STRATEGY_COUNT];

    uint16_t strategy_active_mask;
    uint16_t domain_valid_mask;

    uint8_t p_objective_source;
    uint16_t p_constraint_mask;
    double objective_dp_kw;
    double effective_dp_kw;

    double q_request_kvar;
    double q_applied_kvar;
    double q_unserved_kvar;

    double s6_request_kw;
    double s6_applied_kw;
    double s6_unserved_kw;

    double s8_request_kw;
    double s8_applied_kw;
    double s8_unserved_kw;

    uint8_t raw_system_mode;
    uint8_t final_system_mode;
    uint8_t mode_reason;
    uint8_t selected_master;
    uint8_t breaker_request_close;

    double delta_v_pu;
    double delta_f_hz;
    double delta_theta_deg;
    double sync_timer_s;
    double reclose_timer_s;
    double fref_trim_hz;

    double p_expected_kw[CTRL_DEVICE_COUNT];
    double execution_residual_kw[CTRL_DEVICE_COUNT];
    uint16_t execution_state_packed;
    uint16_t resource_qualified_mask;

    double effective_cap_kw[CTRL_DEVICE_COUNT];
    double trust[CTRL_DEVICE_COUNT];

    uint8_t coord_recovery_state;
    uint16_t realloc_active_mask;
    double realloc_remain_kw;

    double pcc_rx_kw;
    uint8_t method_variant_status;
    uint16_t reconstruction_event_seq;
} ControllerDiagnostics;

typedef enum
{
    CTRL_OK = 0,
    CTRL_ERR_NULL = -1,
    CTRL_ERR_NOT_INITIALIZED = -2,
    CTRL_ERR_INPUT_INVALID = -3,
    CTRL_ERR_CONFIG_INVALID = -4,
    CTRL_ERR_UNSUPPORTED_P_MODE = -5,
    CTRL_ERR_NUMERIC = -6,
    CTRL_ERR_STATE = -7
} ControllerStatus;

typedef enum
{
    CTRL_STEP_ERROR = -1,
    CTRL_STEP_MONITOR_ONLY = 0,
    CTRL_STEP_HELD = 1,
    CTRL_STEP_CANDIDATE = 2,
    CTRL_STEP_RETRY_PENDING = 3
} ControllerStepCode;

typedef struct
{
    ControllerStepCode code;

    uint8_t output_valid;
    uint8_t pending_valid;

    uint8_t command_state_changed;
    uint8_t control_content_changed;

    uint8_t agc_updated;
    uint8_t retrying_pending;
} ControllerStepResult;

#endif /* BOARD15_CONTROLLER_API_V0_1_H */
