#ifndef BOARD15_STRATEGY15_CORE_C01_V0_1_H
#define BOARD15_STRATEGY15_CORE_C01_V0_1_H

/*
 * BOARD15 C01 - strategy15_core
 * Source-equivalent migration of Advanced_Strategy_Core1.m
 *
 * Reference semantics:
 * - Device/platform-independent.
 * - PCC active-power sign: + export, - import.
 * - PV1/PV2 inputs are the current strategy inputs used by the frozen model;
 *   in K26_V5 these correspond to PV available/max-power signals.
 * - This module evaluates the original S1~S15 judgment layer only.
 * - It does NOT perform arbitration, AGC allocation, S6/S8 execution,
 *   Q allocation, breaker actuation, black-start execution sequencing,
 *   or S15 resynchronization execution.
 */

#include <stdint.h>

#define STRATEGY15_COUNT 15u

typedef struct
{
    double time_s;

    double pcc_p_kw;
    double pcc_q_kvar;
    double pcc_v_rms_v;
    double pcc_freq_hz;

    double ess1_soc;
    double ess2_soc;

    double pv1_available_kw;
    double pv2_available_kw;

    double comm_ok;
    double evaluate_enable;
} Strategy15Input;

typedef struct
{
    double p_unit_kw;

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

    double p_target_kw;

    double uv_threshold_pu;
    double uf_threshold_hz;
    double load_shed_step_kw;

    double peak_threshold_kw;
    double valley_threshold_kw;

    double plan_interval_s;
    double export_limit_kw;
    double renewable_target_pct;

    double blackstart_enable;
    double switch_enable;

    double opt_weight_cost;
    double opt_weight_carbon;
    double opt_weight_renewable;
    double opt_weight_tie;
    double opt_weight_soc;
} Strategy15Config;

typedef struct
{
    uint8_t initialized;

    double last_t;
    double demand_avg;
    double peak_power;
    double pv_prev;

    double self_use_energy;
    double export_energy;
    double pv_energy;
    double curtailed_energy;

    double black_state;
    double switch_timer;
} Strategy15State;

typedef struct
{
    double status[STRATEGY15_COUNT];
    double alarm[STRATEGY15_COUNT];
    double metric[STRATEGY15_COUNT];
    double cmd[STRATEGY15_COUNT];
} Strategy15Output;

/* Clears all state. Next step reproduces MATLAB first-call initialization. */
void strategy15_reset(Strategy15State *state);

/*
 * Executes one source-equivalent evaluation step.
 *
 * Return:
 *   0  success
 *  -1  null pointer
 *
 * NOTE:
 * C01 intentionally reproduces the frozen MATLAB judgment semantics.
 * BOARD15 communication-gap / reconnect / candidate-commit lifecycle
 * semantics are applied by the higher-level controller in later integration.
 */
int strategy15_step(
    Strategy15State *state,
    const Strategy15Input *input,
    const Strategy15Config *config,
    Strategy15Output *output);

#endif /* BOARD15_STRATEGY15_CORE_C01_V0_1_H */
