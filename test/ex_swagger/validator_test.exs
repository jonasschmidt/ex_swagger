defmodule ExSwagger.ValidatorTest do
  use ExUnit.Case, async: true

  import ExSwagger.Validator
  alias ExSwagger.Request
  alias ExSwagger.Validator.ParameterError
  alias ExJsonSchema.Validator.Error, as: ValidationError

  @schema %{
    "paths" => %{
      "/item/{scope}/{item_id}" => %{
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
            "type" => "integer"
          }
        ],
        "get" => %{
          "parameters" => [
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
              "type" => "integer"
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
    request = %Request{@request | query_params: %{@request.query_params | "latitude" => "11.11foo"}}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "latitude"]}
  end

  test "optional query parameter with wrong type" do
    request = %Request{@request | query_params: @request.query_params |> Map.put("optional", "123foo")}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "optional"]}
  end

  test "multiple validaton errors" do
    request = %Request{@request |
      path_params: %{"item_id" => "bar"},
      query_params: %{"latitude" => 11.11, "optional" => ""}
    }
    assert validate(request, @schema) == {:error, [
      parameter_missing: "scope",
      empty_parameter: "optional",
      parameter_missing: "longitude",
      invalid_parameter_type: "item_id",
    ]}
  end

  test "valid request with path and query parameters" do
    sanitized_request = %{@request |
      path_params: %{"scope" => "foo", "item_id" => 123},
      query_params: %{"latitude" => 11.11, "longitude" => 22.22}
    }
    assert validate(@request, @schema) === {:ok, sanitized_request}
  end

  test "overriding path-global parameter definition on operation level" do
    schema = %{
      "paths" => %{
        "/item" => %{
          "parameters" => [
            %{
              "name" => "limit",
              "in" => "query",
              "required" => false,
              "type" => "integer"
            }
          ],
          "get" => %{
            "parameters" => [
              %{
                "name" => "limit",
                "in" => "query",
                "required" => true,
                "type" => "string"
              }
            ]
          }
        }
      }
    }
    request = %Request{path: "/item", method: :get, query_params: %{"limit" => "foo"}}
    assert validate(request, schema) == {:ok, request}
  end

  test "schema validation" do
    schema = %{
      "paths" => %{
        "/item" => %{
          "get" => %{
            "parameters" => [
              %{
                "name" => "maximum",
                "in" => "query",
                "type" => "integer",
                "maximum" => 100
              },
              %{
                "name" => "minimum",
                "in" => "path",
                "type" => "integer",
                "minimum" => 10,
                "exclusiveMinimum" => true
              },
              %{
                "name" => "max_length",
                "in" => "query",
                "type" => "string",
                "maxLength" => 3
              },
              %{
                "name" => "min_length",
                "in" => "path",
                "type" => "string",
                "minLength" => 3
              },
              %{
                "name" => "pattern",
                "in" => "query",
                "type" => "string",
                "pattern" => "^\\d+$"
              },
              %{
                "name" => "enum",
                "in" => "path",
                "type" => "string",
                "enum" => ~w(foo bar)
              },
              %{
                "name" => "multiple_of",
                "in" => "query",
                "type" => "integer",
                "multipleOf" => 2
              },
            ]
          }
        }
      }
    }

    request = %Request{
      path: "/item",
      method: :get,
      path_params: %{
        "minimum" => "10",
        "min_length" => "ab",
        "enum" => "baz",
      },
      query_params: %{
        "maximum" => "101",
        "max_length" => "abcd",
        "pattern" => "a1b2c3",
        "multiple_of" => 3,
      },
    }

    assert validate(request, schema) == {:error, [
      %ParameterError{error: %ValidationError.Enum{}, in: :path, parameter: "enum"},
      %ParameterError{error: %ValidationError.MinLength{expected: 3, actual: 2}, in: :path, parameter: "min_length"},
      %ParameterError{error: %ValidationError.Minimum{exclusive?: true, expected: 10}, in: :path, parameter: "minimum"},
      %ParameterError{error: %ValidationError.MaxLength{expected: 3, actual: 4}, in: :query, parameter: "max_length"},
      %ParameterError{error: %ValidationError.Maximum{exclusive?: false, expected: 100}, in: :query, parameter: "maximum"},
      %ParameterError{error: %ValidationError.MultipleOf{expected: 2}, in: :query, parameter: "multiple_of"},
      %ParameterError{error: %ValidationError.Pattern{expected: "^\\d+$"}, in: :query, parameter: "pattern"},
    ]}
  end
end
