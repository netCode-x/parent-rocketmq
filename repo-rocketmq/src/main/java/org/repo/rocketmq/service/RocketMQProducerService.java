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

    /** 解析 topic：为空则用默认 */
    private String resolveTopic(String topic) {
        return (topic == null || topic.isEmpty()) ? properties.getTopic() : topic;
    }

    // ---------- 对外统一发送方法 ----------

    public SendResult send(String body) throws Exception {
        return send(null, null, null, body);
    }

    public SendResult send(String topic, String body) throws Exception {
        return send(topic, null, null, body);
    }

    public SendResult send(String topic, String tag, String body) throws Exception {
        return send(topic, tag, null, body);
    }

    /**
     * 统一发送入口：支持 topic、tag、key、body。
     * 由本方法构建 Message，并交给私有 doSend 完成真正的发送与埋点。
     */
    public SendResult send(String topic, String tag, String key, String body) throws Exception {
        String resolvedTopic = resolveTopic(topic);
        Message message = new Message(
                resolvedTopic,
                tag,
                key,
                body.getBytes(StandardCharsets.UTF_8)
        );
        return doSend(message, resolvedTopic, tag);
    }

    // ---------- 内部真正发送 + 埋点 ----------

    /**
     * 统一发送入口：埋点 + 异常兜底 + 日志。
     *
     * @param message 已经构建好的 RocketMQ Message
     * @param topic   实际使用的 topic（用于埋点，避免从 message 取时不一致）
     * @param tag     实际使用的 tag（用于埋点）
     */
    private SendResult doSend(Message message, String topic, String tag) throws Exception {
        int payloadSize = message.getBody() == null ? 0 : message.getBody().length;
        long startNanos = System.nanoTime();

        boolean success = false;
        Throwable error = null;

        try {
            SendResult result = producer.send(message);

            if (result.getSendStatus() == SendStatus.SEND_OK) {
                success = true;
                log.info("消息发送成功, topic={}, tag={}, msgId={}",
                        topic, tag, result.getMsgId());
            } else {
                success = false;
                error = new IllegalStateException("SendStatus: " + result.getSendStatus());
                log.warn("消息发送非 OK, topic={}, tag={}, status={}",
                        topic, tag, result.getSendStatus());
            }
            return result;
        } catch (Exception e) {
            success = false;
            error = e;
            log.error("消息发送异常, topic={}, tag={}", topic, tag, e);
            throw e;
        } finally {
            // 无论成功、失败、异常，都只记录一次，避免重复计数或漏计
            metrics.recordSend(topic, tag, startNanos, payloadSize, success, error);
        }
    }
}