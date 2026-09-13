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
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.repo.rocketmq.dto.SendMessageRequest;
import org.repo.rocketmq.dto.SendMessageResponse;
import org.repo.rocketmq.service.RocketMQProducerService;
import org.springframework.web.bind.annotation.*;

/**
 * RocketMQ 消息发送接口
 */
@Slf4j
@RestController
@RequestMapping("/api/rocketmq")
@RequiredArgsConstructor
@Tag(name = "RocketMQ 消息接口", description = "发送 RocketMQ 消息")
public class RocketMQController {

    private final RocketMQProducerService producerService;

    @Operation(
            summary = "发送消息",
            description = "支持发送到默认 Topic 或指定 Topic，可选 Tag、Key"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "发送成功",
                    content = @Content(schema = @Schema(implementation = SendMessageResponse.class))),
            @ApiResponse(responseCode = "500", description = "发送失败")
    })
    @PostMapping("/send")
    public SendMessageResponse send(
            @Parameter(description = "发送消息请求体", required = true)
            @RequestBody SendMessageRequest request) {
        try {
            SendResult result;
            if (request.getKey() != null && !request.getKey().isEmpty()) {
                result = producerService.sendWithKey(
                        request.getTopic(), request.getTag(), request.getKey(), request.getBody());
            } else if (request.getTag() != null && !request.getTag().isEmpty()) {
                result = producerService.send(request.getTopic(), request.getBody(), request.getTag());
            } else {
                result = producerService.send(request.getTopic(), request.getBody());
            }

            boolean ok = result.getSendStatus() == SendStatus.SEND_OK;
            return SendMessageResponse.builder()
                    .success(ok)
                    .msgId(result.getMsgId())
                    .sendStatus(result.getSendStatus().name())
                    .build();
        } catch (Exception e) {
            log.error("发送消息失败, request={}", request, e);
            return SendMessageResponse.builder()
                    .success(false)
                    .errorMsg(e.getMessage())
                    .build();
        }
    }
}