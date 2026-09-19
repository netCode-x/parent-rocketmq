package org.repo.rocketmq.order;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

/**
 * RocketMQ Producer 指标埋点组件（按 topic 维度）
 */
@Component
public class MetricsRocketMQTemplate {

    private static final String SEND_TIMER = "rocketmq.producer.send.cost";
    private static final String SEND_COUNTER = "rocketmq.producer.send.messages";
    private static final String SEND_BYTES = "rocketmq.producer.send.bytes";
    private static final String SEND_ERRORS = "rocketmq.producer.send.errors";

    private final MeterRegistry registry;

    public MetricsRocketMQTemplate(MeterRegistry registry) {
        this.registry = registry;
    }

    /**
     * 记录一次发送（同步/异步都适用）
     *
     * @param topic     消息主题（核心标签）
     * @param tag       消息 tag，可为 null 或空
     * @param startNanos 发送开始时间（System.nanoTime()）
     * @param payloadSize 消息体字节数，未知可传 0
     * @param success   是否成功
     * @param error     失败时的异常，成功传 null
     */
    public void recordSend(String topic, String tag, long startNanos,
                           int payloadSize, boolean success, Throwable error) {
        String resultTag = success ? "success" : "failure";
        String safeTag = (tag == null || tag.isEmpty()) ? "none" : tag;

        // 1. 耗时（Timer 自动统计 count / sum / max / percentile）
        Timer.builder(SEND_TIMER)
                .description("RocketMQ 消息发送耗时")
                .tag("topic", topic)
                .tag("tag", safeTag)
                .tag("result", resultTag)
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(registry)
                .record(System.nanoTime() - startNanos, TimeUnit.NANOSECONDS);

        // 2. 消息条数
        Counter.builder(SEND_COUNTER)
                .description("RocketMQ 消息发送条数")
                .tag("topic", topic)
                .tag("tag", safeTag)
                .tag("result", resultTag)
                .register(registry)
                .increment();

        // 3. 字节数（成功才统计业务体量，可按需调整）
        if (success && payloadSize > 0) {
            Counter.builder(SEND_BYTES)
                    .description("RocketMQ 消息发送字节数")
                    .tag("topic", topic)
                    .tag("tag", safeTag)
                    .register(registry)
                    .increment(payloadSize);
        }

        // 4. 异常细分
        if (!success && error != null) {
            Counter.builder(SEND_ERRORS)
                    .description("RocketMQ 消息发送异常次数")
                    .tag("topic", topic)
                    .tag("tag", safeTag)
                    .tag("exception", error.getClass().getSimpleName())
                    .register(registry)
                    .increment();
        }
    }

    /** 便捷方法：不关心 tag 和字节数时使用 */
    public void recordSend(String topic, long startNanos, boolean success, Throwable error) {
        recordSend(topic, null, startNanos, 0, success, error);
    }
}