package org.repo.rocketmq.order;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.time.Duration;

@Component
public class RocketMQProducerMetrics {

    private final MeterRegistry meterRegistry;

    // 默认 fallback topic，避免 topic 为空时崩溃
    private static final String DEFAULT_TOPIC = "unknown";

    public RocketMQProducerMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    /**
     * 获取（或创建）某个 topic + status 的 Counter
     * Micrometer 会自动缓存同名同 tag 的 meter，不会重复注册
     */
    private Counter getCounter(String topic, String status) {
        return Counter.builder("rocketmq_send_total")
                .description("Total number of RocketMQ messages sent")
                .tag("topic", safeTopic(topic))
                .tag("status", status)
                .register(meterRegistry);
    }

    /**
     * 获取（或创建）某个 topic + status 的 Timer
     */
    private Timer getTimer(String topic, String status) {
        return Timer.builder("rocketmq_send_duration")
                .description("Time taken to send RocketMQ messages")
                .tag("topic", safeTopic(topic))
                .tag("status", status)
                .publishPercentiles(0.5, 0.95, 0.99)
                .publishPercentileHistogram()
                .minimumExpectedValue(Duration.ofMillis(1))
                .maximumExpectedValue(Duration.ofSeconds(10))
                .register(meterRegistry);
    }

    private String safeTopic(String topic) {
        return (topic == null || topic.isEmpty()) ? DEFAULT_TOPIC : topic;
    }

    /**
     * 开始计时，返回 Sample 用于 stop
     */
    public Timer.Sample startTimer() {
        return Timer.start(meterRegistry);
    }

    public void recordSuccess(String topic, Timer.Sample sample) {
        getCounter(topic, "success").increment();
        sample.stop(getTimer(topic, "success"));
    }

    public void recordFailure(String topic, Timer.Sample sample) {
        getCounter(topic, "failure").increment();
        sample.stop(getTimer(topic, "failure"));
    }
}