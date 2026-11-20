/*
 * fuzz_read — libFuzzer harness for genann's only parser, genann_read(FILE*).
 *
 * The input is a genann network file ("inputs hidden_layers hidden outputs" then
 * total_weights doubles). The header goes straight to genann_init (dimension and
 * size-overflow checks), so every header the parser accepts is fuzzed unrestricted.
 * A network that loads is then run, trained, copied and written back out, so the
 * fuzzed weights reach genann_run / genann_train / genann_copy / genann_write.
 *
 * genann_read only returns a network once every weight was read from the input, so
 * the work after loading is bounded by the input length; no size cap is needed.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "genann.h"

/* Network inputs / training targets are derived from the input bytes so the
 * result depends only on this input. */
static void fill(double *v, int count, const uint8_t *data, size_t size, size_t salt) {
    for (int i = 0; i < count; ++i)
        v[i] = ((int)data[(i + salt) % size] - 128) / 32.0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;

    FILE *f = fmemopen((void *)data, size, "r");
    if (!f) return 0;
    genann *ann = genann_read(f);
    fclose(f);
    if (!ann) return 0;

    double *in = calloc((size_t)ann->inputs, sizeof(double));
    double *want = calloc((size_t)ann->outputs, sizeof(double));
    if (in && want) {
        fill(in, ann->inputs, data, size, 0);
        fill(want, ann->outputs, data, size, 7);
        genann_run(ann, in);
        genann_train(ann, in, want, 0.5);

        genann *copy = genann_copy(ann);
        if (copy) {
            genann_run(copy, in);
            FILE *out = fopen("/dev/null", "w");
            if (out) {
                genann_write(copy, out);
                fclose(out);
            }
            genann_free(copy);
        }
    }
    free(in);
    free(want);
    genann_free(ann);
    return 0;
}
