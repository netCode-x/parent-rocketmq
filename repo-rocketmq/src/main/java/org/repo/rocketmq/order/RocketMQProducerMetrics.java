package org.repo.rocketmq.order;


import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.annotation.PostConstruct;
import org.springframework.stereotype.Component;

import java.time.Duration;

@Component
public class RocketMQProducerMetrics {


    private final MeterRegistry meterRegistry;

    private Counter sendSuccessCounter;
    private Counter sendFailureCounter;
    private Timer sendTimer;

    private Timer sendSuccessTimer;
    private Timer sendFailureTimer;

    private RocketMQProducerMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    @PostConstruct
    public void init() {
        sendSuccessCounter = Counter.builder("rocketmq_send_total")
                .description("Total number of RocketMQ messages sent successfully")
                .tag("status", "success")
                .tag("topic","topic")
                .register(meterRegistry);

        sendFailureCounter = Counter.builder("rocketmq_send_total")
                .description("Total number of RocketMQ messages sent failure")
                .tag("status", "failure")
                .register(meterRegistry);

        sendTimer = Timer.builder("rocketmq_send_duration")
                .description("Time taken to send RocketMQ mesages")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(meterRegistry);
        // 成功/失败各一个 Timer，提前创建并复用
        sendSuccessTimer = buildTimer("success");

        sendFailureTimer = buildTimer("failure");
    }

    private Timer buildTimer(String status) {
        return Timer.builder("rocketmq_send_duration")
                .description("Time taken to send RocketMQ messages")
                .tag("status", status)
                .publishPercentiles(0.5, 0.95, 0.99)     // 客户端算分位数
                .publishPercentileHistogram()             // 生成 bucket，便于 Prometheus 聚合
                .minimumExpectedValue(Duration.ofMillis(1))
                .maximumExpectedValue(Duration.ofSeconds(10))
                .register(meterRegistry);
    }

    /**
     * 开始计时，返回sample 用于stop
     *
     * @return
     */
    public Timer.Sample startTimer() {
        return Timer.start(meterRegistry);
    }

    public void recordSuccess(Timer.Sample sample) {
        sendSuccessCounter.increment();
        sample.stop(sendSuccessTimer);
    }

    public void recordFailure(Timer.Sample sample) {
        sendFailureCounter.increment();
        sample.stop(sendFailureTimer);
    }


    /**
     * 停止计时
     *
     * @param sample
     */
    public void stopTimer(Timer.Sample sample) {
        sample.stop(sendTimer);
    }
}
