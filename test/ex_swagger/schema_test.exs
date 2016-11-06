defmodule ExSwagger.SchemaTest do
  use ExUnit.Case, async: true

  @schema %{
    "swagger" => "2.0",
    "info" => %{
        "version" => "0.1",
        "title" => "My awesome API"
    },
    "paths" => %{
      "/items/{item_id}" => %{
        "get" => %{
          "parameters" => [
            %{
              "name" => "item_id",
              "in" => "path",
              "required" => true,
              "type" => "number"
            },
          ]
        }
      }
    }
  }

  test "failing to parse an invalid schema" do
    errors = [
      %ExJsonSchema.Validator.Error{
        error: %ExJsonSchema.Validator.Error.Required{missing: ["responses"]},
        path: "#/paths//items/{item_id}/get"
      }
    ]
    assert ExSwagger.Schema.parse(@schema) == {:error, errors}
  end

  test "parsing a valid schema" do
    responses = %{"200" => %{"description" => "OK"}}
    schema = put_in(@schema, ["paths", "/items/{item_id}", "get", "responses"], responses)
    assert {:ok, _schema} = ExSwagger.Schema.parse(schema)
  end
end
