/* PWM 型声纳距离采集（DYP A02 系列，PWM 输出型）
 * 协议（examples/pwm/pwm.ino 考证）：
 *   触发：传感器 RX 100µs 低脉冲；输出：TX 高电平脉宽 T，距离 S = T/57.5 cm；
 *   无目标：约 35ms 固定脉宽；触发周期须 >70ms（本程序 500ms）。
 *
 * 用法：./pwm_capture [采样数]   （默认 8 次）
 * 引脚：gpiochip4 line1 = 触发输出（原 UART7_TX，13 脚）
 *       gpiochip4 line0 = PWM 输入（原 UART7_RX，11 脚）
 * 编译：gcc -O2 -o pwm_capture pwm_capture.c -lgpiod
 */
#include <gpiod.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TRIGGER_LOW_US 100000LL  /* 100µs，用 ns 表示 */

static void nsleep(long ns)
{
    struct timespec ts = { ns / 1000000000L, ns % 1000000000L };
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv)
{
    int samples = argc > 1 ? atoi(argv[1]) : 8;
    struct gpiod_chip *chip = gpiod_chip_open_by_name("gpiochip4");
    if (!chip) { perror("gpiod_chip_open"); return 1; }

    struct gpiod_line *tx = gpiod_chip_get_line(chip, 1);
    struct gpiod_line *rx = gpiod_chip_get_line(chip, 0);
    if (!tx || !rx) { perror("get_line"); return 1; }

    if (gpiod_line_request_output(tx, "sonar-trigger", 1)) {
        perror("request tx"); return 1;
    }
    if (gpiod_line_request_both_edges_events(rx, "sonar-pwm")) {
        perror("request rx"); return 1;
    }

    int valid = 0;
    for (int n = 0; n < samples; n++) {
        /* 清残留事件 */
        struct timespec z = { 0, 0 };
        while (gpiod_line_event_wait(rx, &z) == 1) {
            struct gpiod_line_event ev;
            gpiod_line_event_read(rx, &ev);
        }

        /* 触发：拉低 100µs 后拉高，高电平时刻为脉宽起点 */
        gpiod_line_set_value(tx, 0);
        nsleep(100000);
        gpiod_line_set_value(tx, 1);

        struct timespec t_high;
        clock_gettime(CLOCK_REALTIME, &t_high);

        /* 等下降沿（脉宽结束），上限 60ms（35ms 无目标 + 余量） */
        struct timespec wait = { 0, 60000000L };
        int rc = gpiod_line_event_wait(rx, &wait);
        if (rc != 1) {
            printf("[%d/%d] 未捕获下降沿\n", n + 1, samples);
            continue;
        }
        struct gpiod_line_event ev;
        if (gpiod_line_event_read(rx, &ev) < 0) {
            printf("[%d/%d] event read 失败\n", n + 1, samples);
            continue;
        }
        long long width_ns = (long long)(ev.ts.tv_sec - t_high.tv_sec) * 1000000000LL
                             + (ev.ts.tv_nsec - t_high.tv_nsec);
        if (width_ns <= 0) {
            printf("[%d/%d] 异常脉宽 %lld ns\n", n + 1, samples, width_ns);
            continue;
        }
        double width_us = width_ns / 1000.0;
        if (width_us > 50000) {
            printf("[%d/%d] 脉宽 %.0f µs —— 无目标（35ms 固定脉宽）\n",
                   n + 1, samples, width_us);
            continue;
        }
        double dist_cm = width_us / 57.5;
        printf("[%d/%d] 脉宽 %.0f µs —— 距离 ≈ %.1f cm\n",
               n + 1, samples, width_us, dist_cm);
        valid++;
        nsleep(400000000L); /* 500ms 周期（扣除等待） */
    }

    printf("VERDICT: %s —— 有效读数 %d/%d\n",
           valid ? "PWM_OK" : "PWM_SILENT", valid, samples);
    gpiod_line_release(rx);
    gpiod_line_release(tx);
    gpiod_chip_close(chip);
    return 0;
}
