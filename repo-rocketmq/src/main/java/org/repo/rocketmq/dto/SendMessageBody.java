package org.repo.rocketmq.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

/**
 * 仅承载消息体，topic / tag / key 走 Header。
 */
@Data
@Schema(description = "发送消息请求体")
public class SendMessageBody {

    @Schema(description = "消息体内容", required = true)
    private String body;
}