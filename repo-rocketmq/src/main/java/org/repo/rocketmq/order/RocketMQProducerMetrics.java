package org.repo.rocketmq.order;


import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
public class RocketMQProducerMetrics {


    private final MeterRegistry meterRegistry;

    private Counter sendSuccessCounter;
    private Counter sendFailureCounter;
    private Timer sendTimer;

    private RocketMQProducerMetrics(MeterRegistry meterRegistry){
        this.meterRegistry=meterRegistry;
    }
    @PostConstruct
    public void init(){
        sendSuccessCounter = Counter.builder("rocketmq_send_total")
                .description("Total number of RocketMQ messages sent successfully")
                .tag("status","success")
                .register(meterRegistry);

        sendFailureCounter = Counter.builder("rocketmq_send_total")
                .description("Total number of RocketMQ messages sent failure")
                .tag("status","failure")
                .register(meterRegistry);

        sendTimer = Timer.builder("rocketmq_send_duration")
                .description("Time taken to send RocketMQ mesages")
                .publishPercentiles(0.5,0.95,0.99)
                .register(meterRegistry);

    }

    /**
     *  开始计时，返回sample 用于stop
     * @return
     */
    public Timer.Sample startTimer(){
        return Timer.start(meterRegistry);
    }

    public void  recordSuccess(){
        sendSuccessCounter.increment();
    }
    public void recordFailure(){
        sendFailureCounter.increment();
    }


    /**
     * 停止计时
     * @param sample
     */
    public void  stopTimer (Timer.Sample sample){
        sample.stop(sendTimer);
    }
}
