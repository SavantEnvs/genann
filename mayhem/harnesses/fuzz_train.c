/*
 * fuzz_train — libFuzzer harness for genann training with every public activation.
 *
 * genann_read always leaves the default (cached sigmoid) activations, so this target
 * lets the input choose them, as a library user does by assigning the public
 * ann->activation_hidden / ann->activation_output fields (genann.h):
 *   byte 0      hidden-layer activation   (index into the public genann_act_* table)
 *   byte 1      output-layer activation   (genann_act_linear selects genann_train's
 *                                          separate linear-output branch)
 *   byte 2      number of training rounds (1..8)
 *   byte 3      learning rate             (0 .. ~2)
 *   bytes 4..   a genann network file, parsed by genann_read (header -> genann_init)
 * Training inputs/targets are derived from the input bytes.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "genann.h"

static const genann_actfun acts[] = {
    genann_act_sigmoid, genann_act_sigmoid_cached, genann_act_threshold,
    genann_act_linear,  genann_act_tanh,           genann_act_relu,
};
#define NACTS (sizeof(acts) / sizeof(acts[0]))

static void fill(double *v, int count, const uint8_t *data, size_t size, size_t salt) {
    for (int i = 0; i < count; ++i)
        v[i] = ((int)data[(i + salt) % size] - 128) / 32.0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 5) return -1;
    const genann_actfun hidden_act = acts[data[0] % NACTS];
    const genann_actfun output_act = acts[data[1] % NACTS];
    const int rounds = 1 + data[2] % 8;
    const double rate = data[3] / 128.0;

    FILE *f = fmemopen((void *)(data + 4), size - 4, "r");
    if (!f) return 0;
    genann *ann = genann_read(f);
    fclose(f);
    if (!ann) return 0;

    ann->activation_hidden = hidden_act;
    ann->activation_output = output_act;

    double *in = calloc((size_t)ann->inputs, sizeof(double));
    double *want = calloc((size_t)ann->outputs, sizeof(double));
    if (in && want) {
        for (int r = 0; r < rounds; ++r) {
            fill(in, ann->inputs, data, size, (size_t)r * 3);
            fill(want, ann->outputs, data, size, (size_t)r * 3 + 1);
            genann_train(ann, in, want, rate);
        }
        genann *copy = genann_copy(ann);
        if (copy) {
            genann_run(copy, in);
            genann_free(copy);
        }
        genann_run(ann, in);
    }
    free(in);
    free(want);
    genann_free(ann);
    return 0;
}
