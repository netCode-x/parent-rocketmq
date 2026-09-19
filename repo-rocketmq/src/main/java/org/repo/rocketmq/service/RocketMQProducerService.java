package org.repo.rocketmq.service;

import lombok.extern.slf4j.Slf4j;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.Message;
import org.repo.rocketmq.config.RocketMQProperties;
import org.repo.rocketmq.order.MetricsRocketMQTemplate;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;

@Slf4j
@Service
public class RocketMQProducerService {

    private final MetricsRocketMQTemplate metrics;
    private final DefaultMQProducer producer;
    private final RocketMQProperties properties;

    public RocketMQProducerService(MetricsRocketMQTemplate metrics,
                                   DefaultMQProducer producer,
                                   RocketMQProperties properties) {
        this.metrics = metrics;
        this.producer = producer;
        this.properties = properties;
    }

    /**
     * 统一发送入口：埋点 + 异常兜底 + 日志。
     * topic 直接从 message 取，避免调用方传错 / 传 null。
     */
    private SendResult doend(Message message,String topic,String tags) throws Exception {

        int payloadSize = message.getBody() == null ? 0 : message.getBody().length;
        long startNanos = System.nanoTime();
        boolean success = false;
        Throwable error = null;

        try {
            SendResult result = producer.send(message);

            if (result.getSendStatus() == SendStatus.SEND_OK) {
                success = true;
                log.info("消息发送成功, topic={}, tag={}, msgId={}",
                        topic, tags, result.getMsgId());
            } else {
                success = false;
                error = new IllegalStateException("SendStatus: " + result.getSendStatus());
                log.warn("消息发送非 OK, topic={}, tag={}, status={}",
                        topic, tags, result.getSendStatus());
            }
            return result;
        } catch (Exception e) {
            // 异常路径同样埋点，否则失败率统计会严重偏低
            metrics.recordSend(topic, tags, startNanos, payloadSize, success, error);
            log.error("消息发送异常, topic={}, tag={}", topic, message.getTags(), e);
            throw e;
        }
    }
}