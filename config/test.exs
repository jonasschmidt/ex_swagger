use Mix.Config

config :ex_json_schema,
  :remote_schema_resolver,
  fn "http://swagger.io/v2/schema.json" -> ExSwagger.Schema.Swagger20.schema end
