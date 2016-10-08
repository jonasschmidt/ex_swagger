defmodule ExSwagger.ValidatorTest do
  use ExUnit.Case, async: true

  import ExSwagger.Validator
  alias ExSwagger.Validator.Request

  @schema %{
    "paths" => %{
      "/item/{scope}/{item_id}" => %{
        "get" => %{
          "parameters" => [
            %{
              "name" => "scope",
              "in" => "path",
              "required" => true,
              "type" => "string"
            },
            %{
              "name" => "item_id",
              "in" => "path",
              "required" => true,
              "type" => "number"
            },
            %{
              "name" => "latitude",
              "in" => "query",
              "required" => true,
              "type" => "number",
              "format" => "double"
            },
            %{
              "name" => "longitude",
              "in" => "query",
              "required" => true,
              "type" => "number",
              "format" => "double"
            },
            %{
              "name" => "optional",
              "in" => "query",
              "required" => false,
              "type" => "number"
            }
          ]
        }
      }
    }
  }

  @request %Request{
    path: "/item/{scope}/{item_id}",
    method: :get,
    path_params: %{
      "scope" => "foo",
      "item_id" => "123"
    },
    query_params: %{
      "latitude" => 11.11,
      "longitude" => "22.22"
    }
  }

  test "wrong path" do
    request = %Request{@request | path: "/foo"}
    assert validate(request, @schema) == {:error, :path_not_found}
  end

  test "wrong method" do
    request = %Request{@request | method: :post}
    assert validate(request, @schema) == {:error, :method_not_allowed}
  end

  test "missing required query parameter" do
    request = %Request{@request | query_params: %{"latitude" => 11.11}}
    assert validate(request, @schema) == {:error, [parameter_missing: "longitude"]}
  end

  test "empty query parameter" do
    request = %Request{@request | query_params: %{@request.query_params | "longitude" => ""}}
    assert validate(request, @schema) == {:error, [empty_parameter: "longitude"]}
  end

  test "wrong query parameter type" do
    request = %Request{@request | query_params: %{@request.query_params | "latitude" => "foo"}}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "latitude"]}
  end

  test "optional query parameter with wrong type" do
    request = %Request{@request | query_params: @request.query_params |> Map.put("optional", "foo")}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "optional"]}
  end

  test "valid request with path and query parameters" do
    assert validate(@request, @schema) == :ok
  end
end
