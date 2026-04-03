output "api_endpoint" {
  description = "Invoke URL of the HTTP API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  description = "Identifier of the HTTP API."
  value       = aws_apigatewayv2_api.http_api.id
}
