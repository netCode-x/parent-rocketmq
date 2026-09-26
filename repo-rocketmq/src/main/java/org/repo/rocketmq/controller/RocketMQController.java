package org.repo.rocketmq.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.repo.rocketmq.dto.SendMessageResponse;
import org.repo.rocketmq.service.RocketMQProducerService;
import org.springframework.web.bind.annotation.*;

/**
 * RocketMQ 消息发送接口
 *
 * topic / tag / key 通过 Header 传递，消息体通过 Body 传递。
 */
@Slf4j
@RestController
@RequestMapping("/api/rocketmq")
@RequiredArgsConstructor
@Tag(name = "RocketMQ 消息接口", description = "发送 RocketMQ 消息")
public class RocketMQController {
    private static final Logger logger = LoggerFactory.getLogger(RocketMQController.class);

    /** Header 名称常量，避免拼写错误 */
    private static final String HEADER_TOPIC = "X-RocketMQ-Topic";
    private static final String HEADER_TAG = "X-RocketMQ-Tag";
    private static final String HEADER_KEY = "X-RocketMQ-Key";

    private final RocketMQProducerService producerService;

    @Operation(
            summary = "发送消息",
            description = "topic、tag、key 通过 Header 传递，消息体通过 Body 传递。"
                    + "Header: X-RocketMQ-Topic / X-RocketMQ-Tag / X-RocketMQ-Key，均可选。"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "发送成功",
                    content = @Content(schema = @Schema(implementation = SendMessageResponse.class))),
            @ApiResponse(responseCode = "500", description = "发送失败")
    })
    @PostMapping(value = "/send")
    public SendMessageResponse send(
            @Parameter(description = "主题，不传则使用默认 Topic")
            @RequestHeader(value = HEADER_TOPIC, required = false) String topic,

            @Parameter(description = "标签，可选")
            @RequestHeader(value = HEADER_TAG, required = false) String tag,

            @Parameter(description = "业务键，可选")
            @RequestHeader(value = HEADER_KEY, required = false) String key,

            @Parameter(description = "消息体", required = true)
            @RequestBody String body) {
        try {
            SendResult result = producerService.send(topic, tag, key, body);

            boolean ok = result.getSendStatus() == SendStatus.SEND_OK;
            logger.info("send to msg is: {}, this msg ID : {}",ok,result.getMsgId());

            return SendMessageResponse.builder()
                    .success(ok)
                    .msgId(result.getMsgId())
                    .sendStatus(result.getSendStatus().name())
                    .build();
        } catch (Exception e) {
            log.error("发送消息失败, topic={}, tag={}, key={}, body={}",
                    topic, tag, key, body, e);
            return SendMessageResponse.builder()
                    .success(false)
                    .errorMsg(e.getMessage())
                    .build();
        }
    }
}