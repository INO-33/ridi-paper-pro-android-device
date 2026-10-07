#!/usr/bin/env python3
"""Exercise the driver's actual PM queue functions with host-side kernel stubs.

This checks list lifetime and deferred dispatch, not hardware or lock timing.
Pass --before to prove that the saved pre-fix source crashes in the same cases.
"""
import argparse
import pathlib
import re
import resource
import subprocess
import tempfile


FUNCTIONS = (
    "pxpdma_first_queued", "pxpdma_dequeue", "pxp_issue_pending",
    "pxp_init_channel", "pxp_dma_init", "pxp_pm_begin_access",
    "pxp_pm_end_access",
)


def extract(source, name):
    match = re.search(r"(?m)^static [^\n]*\b" + name +
                      r"\([^;{}]*\)\s*\n\{", source)
    if not match:
        raise ValueError("Missing driver function: " + name)
    opening = match.end() - 1
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#define NR_PXP_VIRT_CHANNEL 16
#define PXP_CHANNEL_FREE 0
#define PXP_CHANNEL_READY 1
#define DMA_SLAVE 0
#define DMA_PRIVATE 1
#define container_of(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
struct list_head { struct list_head *next, *prev; };
#define INIT_LIST_HEAD(h) ((h)->next=(h), (h)->prev=(h))
#define list_entry(p,t,m) container_of(p,t,m)
static bool list_empty(struct list_head *h) { return h->next == h; }
static void list_add_tail(struct list_head *n, struct list_head *h) {
    n->prev=h->prev; n->next=h; h->prev->next=n; h->prev=n;
}
static void list_move_tail(struct list_head *n, struct list_head *h) {
    n->prev->next=n->next; n->next->prev=n->prev; list_add_tail(n,h);
}
struct dma_device;
struct dma_chan {
    struct dma_device *device; int cookie, chan_id; struct list_head device_node;
};
struct dma_device {
    void *dev; unsigned cap_mask; struct list_head channels;
    void *device_alloc_chan_resources, *device_free_chan_resources;
    void *device_tx_status, *device_issue_pending, *device_prep_slave_sg;
    void *device_terminate_all;
};
struct pxp_dma { struct dma_device dma; };
struct pxp_channel {
    struct dma_chan dma_chan; int lock, status, completed, eof_irq;
    char eof_name[16]; struct list_head queue;
};
struct pxp_tx_desc { struct list_head list; };
struct pxps {
    void *dev; struct pxp_dma pxp_dma; struct pxp_channel channel[16];
    int lock, irq, clk_timer, thread_waitq, pxp_ongoing; bool manual_recovering;
};
static struct list_head head = { &head, &head };
static unsigned long jiffies;
static int timeout_in_ms = 600, enable_count, wake_count;
#define to_pxp_dma(d) container_of(d,struct pxp_dma,dma)
#define to_pxp(p) container_of(p,struct pxps,pxp_dma)
#define to_pxp_channel(c) container_of(c,struct pxp_channel,dma_chan)
#define spin_lock_init(l) (*(l)=0)
#define spin_lock(l) ((void)(l))
#define spin_unlock(l) ((void)(l))
#define spin_lock_irqsave(l,f) ((void)(l), (f)=0)
#define spin_unlock_irqrestore(l,f) ((void)(l), (void)(f))
#define dma_cap_set(c,m) ((void)(c), (void)(m))
#define msecs_to_jiffies(ms) (ms)
#define mod_timer(t,e) ((void)(t), (void)(e))
static void pxp_clk_enable(struct pxps *p) { (void)p; enable_count++; }
static void wake_up_interruptible(int *w) { (void)w; wake_count++; }
static int dma_async_device_register(struct dma_device *d) { (void)d; return 0; }
static void pxp_alloc_chan_resources(void) {}
static void pxp_free_chan_resources(void) {}
static void pxp_tx_status(void) {}
static void pxp_prep_slave_sg(void) {}
static void pxp_device_terminate_all(void) {}
static void pxp_issue_pending(struct dma_chan *chan);
'''


CASES = r'''
int main(int argc, char **argv) {
    struct pxps pxp = {0};
    struct pxp_tx_desc desc = {0};
    int ret;
    assert(argc == 2);
    assert(pxp_dma_init(&pxp) == 0);
    /* EPDC normally allocates one channel; the other fifteen remain unused. */
    if (strcmp(argv[1], "unallocated") != 0)
        assert(pxp_init_channel(&pxp.pxp_dma, &pxp.channel[0]) == 0);
    if (strcmp(argv[1], "active") == 0) {
        pxp.pxp_ongoing = 1;
        assert(pxp_pm_begin_access(&pxp) == -EBUSY);
        assert(pxp.pxp_ongoing == 1 && !pxp.manual_recovering);
    } else if (strcmp(argv[1], "queued") == 0) {
        INIT_LIST_HEAD(&desc.list);
        list_add_tail(&desc.list, &pxp.channel[0].queue);
        assert(pxp_pm_begin_access(&pxp) == -EBUSY);
        assert(list_empty(&pxp.channel[0].queue));
        assert(head.next == &desc.list && wake_count == 1);
        assert(!pxp.manual_recovering && pxp.pxp_ongoing == 0);
    } else {
        ret = pxp_pm_begin_access(&pxp);
        assert(ret == 0 && pxp.manual_recovering && pxp.pxp_ongoing == 1);
        if (strcmp(argv[1], "deferred") == 0) {
            INIT_LIST_HEAD(&desc.list);
            list_add_tail(&desc.list, &pxp.channel[0].queue);
            pxp_issue_pending(&pxp.channel[0].dma_chan);
            assert(!list_empty(&pxp.channel[0].queue) && list_empty(&head));
        }
        pxp_pm_end_access(&pxp);
        assert(!pxp.manual_recovering && pxp.pxp_ongoing == 0);
        if (strcmp(argv[1], "deferred") == 0) {
            assert(head.next == &desc.list && wake_count == 1);
        } else {
            assert(list_empty(&head) && enable_count == 0 && wake_count == 0);
        }
    }
    printf("PASS %s\n", argv[1]);
    return 0;
}
'''


def disable_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(source_path, work, label, regression=False):
    source = source_path.read_text()
    program = work / (label + ".c")
    program.write_text(STUBS + "\n" + "\n\n".join(
        extract(source, name) for name in FUNCTIONS) + CASES)
    binary = work / label
    subprocess.run(["cc", "-std=gnu99", "-O0", "-g", str(program),
                    "-o", str(binary)], check=True)
    for case in ("unallocated", "idle", "queued", "deferred", "active"):
        result = subprocess.run([str(binary), case], capture_output=True,
                                text=True, preexec_fn=disable_core)
        print(label, case, "exit=" + str(result.returncode),
              result.stdout.strip(), result.stderr.strip())
        if regression and case != "active":
            assert result.returncode == -11, "Expected old NULL-list SIGSEGV"
        else:
            assert result.returncode == 0, "Driver queue regression: " + case


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", type=pathlib.Path)
    args = parser.parse_args()
    kernel = pathlib.Path(__file__).resolve().parents[4] / "vendor/nxp-opensource/kernel_imx"
    source = kernel / "drivers/dma/pxp/pxp_dma_v2.c"
    with tempfile.TemporaryDirectory(prefix="ridi-pxp-idle-test-") as temp:
        work = pathlib.Path(temp)
        if args.before:
            run(args.before, work, "before", regression=True)
        run(source, work, "fixed")


if __name__ == "__main__":
    main()
