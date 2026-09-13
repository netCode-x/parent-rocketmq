package org.repo.rocketmq.producer;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.repo.rocketmq.config.RocketMQProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * RocketMQ 生产者配置
 * 从 RocketMQProperties 读取配置，创建并启动 DefaultMQProducer
 */
@Slf4j
@Configuration
@RequiredArgsConstructor
public class ProduceConfig {

    private final RocketMQProperties properties;

    @Bean(destroyMethod = "shutdown")
    public DefaultMQProducer defaultMQProducer() throws Exception {
        DefaultMQProducer producer = new DefaultMQProducer(properties.getTopic());
        producer.setNamesrvAddr(properties.getNameServer());
        producer.setSendMsgTimeout(properties.getSendMessageTimeout());
        producer.setRetryTimesWhenSendAsyncFailed(properties.getRetryTimesWhenSendAsyncFailed());
        producer.setMaxMessageSize(properties.getMaxMessageSize());
        producer.setCompressMsgBodyOverHowmuch(properties.getCompressMsgBodyOverHowmuch());
        producer.setRetryAnotherBrokerWhenNotStoreOK(properties.isRetryAnotherBrokerWhenNotStoreOk());

        producer.start();
        log.info("RocketMQ Producer 启动成功, topic={}, nameServer={}",
                properties.getTopic(), properties.getNameServer());
        return producer;
    }
}
