#include "strategy15_core_BOARD15_C01_V0_1.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

static double dmax(double a, double b)
{
    return (a > b) ? a : b;
}

static double dmin(double a, double b)
{
    return (a < b) ? a : b;
}

static double matlab_mod_positive_period(double x, double period)
{
    double r = fmod(x, period);
    if (r < 0.0) {
        r += period;
    }
    return r;
}

static void output_zero(Strategy15Output *output)
{
    (void)memset(output, 0, sizeof(*output));
}

static void initialize_state(
    Strategy15State *state,
    const Strategy15Input *input)
{
    state->initialized = 1u;
    state->last_t = input->time_s;
    state->demand_avg = 0.0;
    state->peak_power = 0.0;
    state->pv_prev =
        input->pv1_available_kw + input->pv2_available_kw;
    state->self_use_energy = 0.0;
    state->export_energy = 0.0;
    state->pv_energy = 0.0;
    state->curtailed_energy = 0.0;
    state->black_state = 0.0;
    state->switch_timer = 0.0;
}

void strategy15_reset(Strategy15State *state)
{
    if (state != NULL) {
        (void)memset(state, 0, sizeof(*state));
    }
}

int strategy15_step(
    Strategy15State *state,
    const Strategy15Input *input,
    const Strategy15Config *config,
    Strategy15Output *output)
{
    double dt;
    double p_unit;
    double p_rated;
    double v_nom;
    double vpu;
    double pv_avail;
    double p_import;
    double p_export;
    double soc_avg;

    double alpha;
    double forecast_demand;

    double agc_err;

    double v_err;
    double q_cmd;

    double reverse_over;
    double island_score;

    double pv_rate_pct_per_min;

    double tie_err;

    double shed_stage;

    double plan_index;
    double day_t;

    double self_use_rate;

    double curtailed;
    double renew_rate;

    double cost_norm;
    double carbon_norm;
    double renew_norm;
    double tie_norm;
    double soc_norm;
    double score;

    if ((state == NULL) || (input == NULL) ||
        (config == NULL) || (output == NULL)) {
        return -1;
    }

    output_zero(output);

    if (state->initialized == 0u) {
        initialize_state(state, input);
    }

    if (input->time_s < state->last_t) {
        initialize_state(state, input);
    }

    dt = dmax(input->time_s - state->last_t, 0.0);

    p_unit = dmax(fabs(config->p_unit_kw), 1.0e-6);
    p_rated = 2.0 * p_unit;
    v_nom = dmax(fabs(config->v_nom_v), 1.0);

    vpu = input->pcc_v_rms_v / v_nom;

    pv_avail =
        dmax(input->pv1_available_kw, 0.0) +
        dmax(input->pv2_available_kw, 0.0);

    p_import = dmax(-input->pcc_p_kw, 0.0);
    p_export = dmax(input->pcc_p_kw, 0.0);

    soc_avg = 0.5 * (input->ess1_soc + input->ess2_soc);

    /* Exact frozen source behavior when the original strategy enable is off. */
    if (input->evaluate_enable <= 0.5) {
        state->last_t = input->time_s;
        return 0;
    }

    /* ------------------------------------------------------------------ */
    /* S1 Demand control                                                  */
    /* ------------------------------------------------------------------ */
    alpha = dmin(
        dt / dmax(config->demand_window_s, 1.0),
        1.0);

    state->demand_avg =
        (1.0 - alpha) * state->demand_avg +
        alpha * p_import;

    state->peak_power =
        dmax(state->peak_power, p_import);

    forecast_demand =
        dmax(state->demand_avg, p_import);

    output->metric[0] =
        100.0 * forecast_demand /
        dmax(fabs(dmax(config->demand_limit_kw, 1.0)), 1.0e-6);

    output->alarm[0] =
        (forecast_demand > 0.95 * config->demand_limit_kw) ? 1.0 : 0.0;

    output->cmd[0] =
        dmax(forecast_demand - config->demand_limit_kw, 0.0);

    output->status[0] =
        (output->cmd[0] > 0.0) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S2 AGC tracking KPI                                                */
    /* ------------------------------------------------------------------ */
    agc_err = fabs(config->p_target_kw - input->pcc_p_kw);

    output->metric[1] =
        100.0 * agc_err /
        dmax(fabs(dmax(fabs(config->p_target_kw), p_rated)), 1.0e-6);

    output->alarm[1] =
        (output->metric[1] > config->agc_error_band_pct) ? 1.0 : 0.0;

    output->cmd[1] =
        config->p_target_kw - input->pcc_p_kw;

    output->status[1] =
        (output->alarm[1] < 0.5) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S3 AVC                                                             */
    /* ------------------------------------------------------------------ */
    v_err = 1.0 - vpu;

    q_cmd =
        dmin(
            dmax(
                v_err /
                dmax(config->avc_v_deadband_pu, 1.0e-6) *
                config->avc_q_limit_kvar,
                -config->avc_q_limit_kvar),
            config->avc_q_limit_kvar);

    output->metric[2] =
        fabs(v_err) * 100.0 +
        0.001 * fabs(input->pcc_q_kvar - q_cmd);

    output->alarm[2] =
        (fabs(v_err) > 0.02) ? 1.0 : 0.0;

    output->cmd[2] = q_cmd;

    output->status[2] =
        (fabs(q_cmd) > 0.0) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S4 Anti-reverse power                                              */
    /* ------------------------------------------------------------------ */
    reverse_over =
        dmax(
            p_export -
            config->anti_reverse_limit_kw -
            config->anti_reverse_deadband_kw,
            0.0);

    output->metric[3] = reverse_over;
    output->alarm[3] = (reverse_over > 0.0) ? 1.0 : 0.0;
    output->cmd[3] = reverse_over;
    output->status[3] = output->alarm[3];

    /* ------------------------------------------------------------------ */
    /* S5 Anti-islanding                                                  */
    /* ------------------------------------------------------------------ */
    island_score =
        ((fabs(input->pcc_freq_hz - 50.0) >
              config->island_freq_dev_hz) ||
         (fabs(vpu - 1.0) >
              config->island_v_dev_pu) ||
         (input->comm_ok < 0.5))
            ? 1.0
            : 0.0;

    output->metric[4] = island_score;
    output->alarm[4] = island_score;
    output->cmd[4] = island_score;
    output->status[4] = island_score;

    /* ------------------------------------------------------------------ */
    /* S6 Smoothing control                                               */
    /* ------------------------------------------------------------------ */
    pv_rate_pct_per_min =
        100.0 *
        fabs(pv_avail - state->pv_prev) /
        dmax(fabs(dmax(p_rated, 1.0)), 1.0e-6) *
        60.0 /
        dmax(dt, 1.0e-6);

    output->metric[5] = pv_rate_pct_per_min;

    output->alarm[5] =
        (pv_rate_pct_per_min >
         config->pv_fluct_trigger_pct)
            ? 1.0
            : 0.0;

    output->cmd[5] =
        dmax(
            pv_rate_pct_per_min -
            config->smooth_rate_limit_pct_per_min,
            0.0);

    output->status[5] =
        (output->cmd[5] > 0.0) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S7 Tie-line power control                                          */
    /* ------------------------------------------------------------------ */
    tie_err =
        input->pcc_p_kw - config->p_target_kw;

    output->metric[6] =
        100.0 * fabs(tie_err) /
        dmax(fabs(dmax(fabs(config->p_target_kw), p_rated)), 1.0e-6);

    output->alarm[6] =
        (output->metric[6] >
         config->agc_error_band_pct)
            ? 1.0
            : 0.0;

    output->cmd[6] = -tie_err;

    output->status[6] =
        (output->alarm[6] < 0.5) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S8 Low-voltage / low-frequency load shedding                       */
    /* ------------------------------------------------------------------ */
    shed_stage = 0.0;

    if (vpu < config->uv_threshold_pu) {
        shed_stage += 1.0;
    }

    if (input->pcc_freq_hz < config->uf_threshold_hz) {
        shed_stage += 1.0;
    }

    output->metric[7] = shed_stage;
    output->alarm[7] = (shed_stage > 0.0) ? 1.0 : 0.0;
    output->cmd[7] =
        shed_stage * config->load_shed_step_kw;
    output->status[7] = shed_stage;

    /* ------------------------------------------------------------------ */
    /* S9 Peak-valley                                                     */
    /* ------------------------------------------------------------------ */
    if ((p_import > config->peak_threshold_kw) &&
        (soc_avg > 0.25)) {
        output->cmd[8] =
            dmin(
                p_import - config->peak_threshold_kw,
                p_rated);
    } else if ((p_import < config->valley_threshold_kw) &&
               (soc_avg < 0.95)) {
        output->cmd[8] =
            -dmin(
                config->valley_threshold_kw - p_import,
                p_rated);
    } else {
        output->cmd[8] = 0.0;
    }

    output->metric[8] =
        100.0 *
        dmax(
            state->peak_power - config->peak_threshold_kw,
            0.0) /
        dmax(fabs(dmax(config->peak_threshold_kw, 1.0)), 1.0e-6);

    output->alarm[8] =
        (p_import > config->peak_threshold_kw) ? 1.0 : 0.0;

    output->status[8] =
        (fabs(output->cmd[8]) > 0.0) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S10 Periodic plan                                                  */
    /* ------------------------------------------------------------------ */
    day_t =
        matlab_mod_positive_period(input->time_s, 86400.0);

    plan_index =
        floor(day_t / dmax(config->plan_interval_s, 1.0)) +
        1.0;

    output->metric[9] = plan_index;

    output->cmd[9] =
        config->p_target_kw +
        0.10 * p_rated *
        sin(
            2.0 *
            3.141592653589793238462643383279502884 *
            day_t /
            86400.0);

    output->alarm[9] =
        (fabs(input->pcc_p_kw - output->cmd[9]) >
         0.08 * dmax(fabs(output->cmd[9]), p_rated))
            ? 1.0
            : 0.0;

    output->status[9] = 1.0;

    /* ------------------------------------------------------------------ */
    /* S11 Self-consumption with surplus export                           */
    /* ------------------------------------------------------------------ */
    state->pv_energy +=
        pv_avail * dt / 3600.0;

    state->export_energy +=
        p_export * dt / 3600.0;

    state->self_use_energy =
        dmax(
            state->pv_energy -
            state->export_energy,
            0.0);

    self_use_rate =
        100.0 *
        state->self_use_energy /
        dmax(state->pv_energy, 1.0e-6);

    output->metric[10] = self_use_rate;

    output->alarm[10] =
        (p_export > config->export_limit_kw) ? 1.0 : 0.0;

    output->cmd[10] =
        dmax(
            p_export - config->export_limit_kw,
            0.0);

    output->status[10] =
        (output->cmd[10] > 0.0) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S12 Renewable maximum absorption                                   */
    /* ------------------------------------------------------------------ */
    curtailed =
        dmax(
            pv_avail -
            dmax(p_import + p_export, 0.0) -
            p_rated * (1.0 - soc_avg),
            0.0);

    state->curtailed_energy +=
        curtailed * dt / 3600.0;

    renew_rate =
        100.0 *
        dmax(
            state->pv_energy -
            state->curtailed_energy,
            0.0) /
        dmax(state->pv_energy, 1.0e-6);

    output->metric[11] = renew_rate;

    output->alarm[11] =
        (renew_rate < config->renewable_target_pct) ? 1.0 : 0.0;

    output->cmd[11] =
        dmin(curtailed, p_rated);

    output->status[11] =
        (output->alarm[11] < 0.5) ? 1.0 : 0.0;

    /* ------------------------------------------------------------------ */
    /* S13 Multi-objective optimization score                             */
    /* ------------------------------------------------------------------ */
    cost_norm =
        dmin(
            dmax(
                p_import /
                dmax(config->peak_threshold_kw, 1.0),
                0.0),
            2.0);

    carbon_norm =
        dmin(
            dmax(
                p_export /
                dmax(config->export_limit_kw + 1.0, 1.0),
                0.0),
            2.0);

    renew_norm =
        dmin(
            dmax(
                (100.0 - renew_rate) / 100.0,
                0.0),
            1.0);

    tie_norm =
        dmin(
            dmax(
                fabs(tie_err) /
                dmax(p_rated, 1.0),
                0.0),
            2.0);

    soc_norm =
        fabs(soc_avg - 0.60);

    score =
        config->opt_weight_cost * cost_norm +
        config->opt_weight_carbon * carbon_norm +
        config->opt_weight_renewable * renew_norm +
        config->opt_weight_tie * tie_norm +
        config->opt_weight_soc * soc_norm;

    output->metric[12] = score;

    output->alarm[12] =
        (score > 0.5) ? 1.0 : 0.0;

    output->cmd[12] =
        -p_rated *
        dmin(dmax(score, -1.0), 1.0);

    output->status[12] = 1.0;

    /* ------------------------------------------------------------------ */
    /* S14 Black start - source-equivalent judgment only                  */
    /* ------------------------------------------------------------------ */
    if (config->blackstart_enable > 0.5) {
        if (state->black_state < 1.0) {
            state->black_state = 1.0;
        }

        if (soc_avg < 0.25) {
            state->black_state = -1.0;
        } else if ((input->time_s > 20.0) &&
                   (state->black_state < 2.0)) {
            state->black_state = 2.0;
        } else if ((input->time_s > 40.0) &&
                   (state->black_state < 3.0)) {
            state->black_state = 3.0;
        } else if ((input->time_s > 60.0) &&
                   (state->black_state < 4.0)) {
            state->black_state = 4.0;
        }
    } else {
        state->black_state = 0.0;
    }

    output->metric[13] = state->black_state;
    output->alarm[13] =
        (state->black_state < 0.0) ? 1.0 : 0.0;
    output->cmd[13] = state->black_state;
    output->status[13] = state->black_state;

    /* ------------------------------------------------------------------ */
    /* S15 Grid/island switch - source-equivalent judgment only           */
    /* ------------------------------------------------------------------ */
    if ((config->switch_enable > 0.5) &&
        (island_score > 0.5)) {
        state->switch_timer += dt;
        output->status[14] = 2.0;
        output->cmd[14] = 1.0;
    } else {
        state->switch_timer = 0.0;
        output->status[14] = 1.0;
        output->cmd[14] = 0.0;
    }

    output->metric[14] =
        state->switch_timer;

    output->alarm[14] =
        (state->switch_timer > 5.0) ? 1.0 : 0.0;

    state->pv_prev = pv_avail;
    state->last_t = input->time_s;

    return 0;
}
