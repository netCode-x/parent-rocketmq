package org.repo.rocketmq.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
@Schema(description = "发送消息响应体")
public class SendMessageResponse {

    @Schema(description = "是否发送成功", example = "true")
    private boolean success;

    @Schema(description = "消息 ID", example = "7F0000010A0F18B4AAC2...")
    private String msgId;

    @Schema(description = "发送状态", example = "SEND_OK")
    private String sendStatus;

    @Schema(description = "错误信息（失败时）", example = "connect to nameserver failed")
    private String errorMsg;
}