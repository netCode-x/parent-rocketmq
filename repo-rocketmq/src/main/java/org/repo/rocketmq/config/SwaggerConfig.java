package org.repo.rocketmq.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Swagger / OpenAPI 配置
 */
@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI rocketMQOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("RocketMQ 消息服务 API")
                        .description("RocketMQ 生产者消息发送接口文档")
                        .version("v1.0.0")
                        .contact(new Contact()
                                .name("yangkaihu")
                                .email("yangkaihu@example.com"))
                        .license(new License()
                                .name("Apache 2.0")
                                .url("https://www.apache.org/licenses/LICENSE-2.0")));
    }
}