package org.repo.rocketmq.config;

import lombok.Data;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;


/**
 * RocketMQ 配置属性
 * 对应 application.yml 中 spring.rocketmq.* 的配置
 */
//@ConfigurationProperties(prefix = "spring.rocketmq")
@Data
@Component
public class RocketMQProperties {

    @Value("${spring.rocketmq.topic:T_yangkaihu_test}")
    private String topic;

    @Value("${spring.rocketmq.nameserver:}")
    private String nameServer;

    /**
     * 发送超时，毫秒
     */
    @Value("${spring.rocketmq.sendMessageTimeout:3000}")
    private int sendMessageTimeout;
    /**
     * 异步发送失败重试次数
     */
    @Value("${spring.rocketmq.retryTimesWhenSendAsyncFailed:3}")
    private int retryTimesWhenSendAsyncFailed;

    /**
     * 单条消息最大字节数，默认 4MB
     */
    @Value("${spring.rocketmq.maxMessageSize:4194304}")
    private int maxMessageSize;
    /**
     * 消息体超过该值自动压缩，默认 4KB
     */
    @Value("${spring.rocketmq.compressMsgBodyOverHowmuch:4096}")
    private int compressMsgBodyOverHowmuch;
    /**
     * 发送失败是否尝试其他 Broker
     */
    @Value("${spring.rocketmq.retryAnotherBrokerWhenNotStoreOk:true}")
    private boolean retryAnotherBrokerWhenNotStoreOk;

}
