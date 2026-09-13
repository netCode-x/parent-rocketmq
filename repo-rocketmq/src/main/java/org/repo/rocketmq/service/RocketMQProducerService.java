package org.repo.rocketmq.service;

import io.micrometer.core.instrument.Timer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.Message;
import org.repo.rocketmq.config.RocketMQProperties;
import org.repo.rocketmq.order.RocketMQProducerMetrics;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;

@Slf4j
@Service
public class RocketMQProducerService {

    private final RocketMQProducerMetrics metrics;
    private final DefaultMQProducer producer;
    private final RocketMQProperties properties;

    public RocketMQProducerService (RocketMQProducerMetrics metrics,
                                    DefaultMQProducer producer,
                                    RocketMQProperties properties){
        this.metrics=metrics;
        this.producer=producer;
        this.properties=properties;
    }

    /** 解析 topic：为空则用默认 */
    private String resolveTopic(String topic) {
        return (topic == null || topic.isEmpty()) ? properties.getTopic() : topic;
    }

    public SendResult send(String body) throws Exception {
        return send(resolveTopic(null), body, null);
    }

    public SendResult send(String topic, String body) throws Exception {
        return send(resolveTopic(topic), body, null);
    }

    public SendResult send(String topic, String body, String tag) throws Exception {
        Message message = new Message(resolveTopic(topic), tag, body.getBytes(StandardCharsets.UTF_8));
        return doSend(message);
    }

    public SendResult sendWithKey(String topic, String tag, String key, String body) throws Exception {
        Message message = new Message(resolveTopic(topic), tag, key, body.getBytes(StandardCharsets.UTF_8));
        return doSend(message);
    }

    private SendResult doSend(Message message) throws Exception {

        Timer.Sample sample = metrics.startTimer();

        SendResult result = producer.send(message);
        if (result.getSendStatus() == SendStatus.SEND_OK) {
            metrics.recordSuccess(sample);
            log.info("消息发送成功, topic={}, tag={}, msgId={}",
                    message.getTopic(), message.getTags(), result.getMsgId());
        } else {
            metrics.recordFailure(sample);
            log.warn("消息发送非 OK, topic={}, status={}",
                    message.getTopic(), result.getSendStatus());
        }
        metrics.stopTimer(sample);
        return result;
    }
}
