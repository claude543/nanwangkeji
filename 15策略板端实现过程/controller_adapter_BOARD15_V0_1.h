#ifndef BOARD15_CONTROLLER_ADAPTER_V0_1_H
#define BOARD15_CONTROLLER_ADAPTER_V0_1_H

/*
 * BOARD15 Controller Adapter API
 * Design06 V0.1 - interface freeze candidate
 *
 * The engineering main program calls ONLY these lifecycle/step functions.
 * Internal strategy / AGC / recovery modules are not called by main.
 */

#include "controller_api_BOARD15_V0_1.h"

/*
 * Full ControllerContext will be defined in controller_context.h during
 * C-migration. It contains explicit Project15 states, committed output,
 * and pending candidate state. No hidden mutable global state is allowed.
 */
typedef struct ControllerContext ControllerContext;

void controller_reset(
    ControllerContext *ctx);

ControllerStatus controller_init(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *config);

ControllerStatus controller_reconfigure(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *old_config,
    const ControllerConfig *new_config);

ControllerStepResult controller_step(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *config,
    ControllerOutput *output,
    ControllerDiagnostics *diag);

ControllerStatus controller_commit(
    ControllerContext *ctx);

void controller_abort_pending(
    ControllerContext *ctx);

#endif /* BOARD15_CONTROLLER_ADAPTER_V0_1_H */
