package org.repo.rocketmq.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

@Data
@Schema(description = "发送消息请求体")
public class SendMessageRequest {

    @Schema(description = "目标 Topic，不传则用配置里的默认 Topic", example = "T_yangkaihu_test")
    private String topic;

    @Schema(description = "消息 Tag，可空", example = "CREATE")
    private String tag;

    @Schema(description = "消息 Key，可空，用于去重/查询", example = "order_1001")
    private String key;

    @Schema(description = "消息内容，必填", example = "Hello RocketMQ", requiredMode = Schema.RequiredMode.REQUIRED)
    private String body;
}