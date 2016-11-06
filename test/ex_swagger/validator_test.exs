defmodule ExSwagger.ValidatorTest do
  use ExUnit.Case, async: true

  import ExSwagger.Validator
  alias ExSwagger.Request
  alias ExSwagger.Validator.{ParameterError, BodyError}
  alias ExJsonSchema.Validator.Error, as: ValidationError

  @schema %{
    "swagger" => "2.0",
    "info" => %{
        "version" => "0.1",
        "title" => "My awesome API"
    },
    "paths" => %{
      "/items/{SCOPE}/{item_id}" => %{
        "parameters" => [
          %{
            "name" => "SCOPE",
            "in" => "path",
            "required" => true,
            "type" => "string"
          },
          %{
            "name" => "item_id",
            "in" => "path",
            "required" => true,
            "type" => "integer"
          },
          %{
            "name" => "X-Request-Id",
            "in" => "header",
            "required" => true,
            "type" => "string"
          },
        ],
        "get" => %{
          "parameters" => [
            %{
              "name" => "Latitude",
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
            },
          ],
          "responses" => %{
            "200" => %{
              "description" => "OK"
            }
          }
        }
      }
    }
  }

  @request %Request{
    path: "/items/{SCOPE}/{item_id}",
    method: :get,
    header_params: %{
      "x-request-id" => "xyz"
    },
    path_params: %{
      "SCOPE" => "foo",
      "item_id" => "123"
    },
    query_params: %{
      "Latitude" => 11.11,
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

  test "missing required header parameter" do
    request = %Request{@request | header_params: %{}}
    assert validate(request, @schema) == {:error, [parameter_missing: "x-request-id"]}
  end

  test "missing required query parameter" do
    request = %Request{@request | query_params: %{"Latitude" => 11.11}}
    assert validate(request, @schema) == {:error, [parameter_missing: "longitude"]}
  end

  test "empty query parameter" do
    request = %Request{@request | query_params: %{@request.query_params | "longitude" => ""}}
    assert validate(request, @schema) == {:error, [empty_parameter: "longitude"]}
  end

  test "wrong query parameter type" do
    request = %Request{@request | query_params: %{@request.query_params | "Latitude" => "11.11foo"}}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "Latitude"]}
  end

  test "optional query parameter with wrong type" do
    request = %Request{@request | query_params: @request.query_params |> Map.put("optional", "123foo")}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "optional"]}
  end

  test "path param names are case-sensitive" do
    request = %Request{@request | path_params: %{"scope" => "foo", "item_id" => "123"}}
    assert validate(request, @schema) == {:error, [parameter_missing: "SCOPE"]}
  end

  test "query param names are case-sensitive" do
    request = %Request{@request | query_params: %{"latitude" => 11.11, "longitude" => 22.22}}
    assert validate(request, @schema) == {:error, [parameter_missing: "Latitude"]}
  end

  test "multiple validaton errors" do
    request = %Request{@request |
      path_params: %{"item_id" => "bar"},
      query_params: %{"Latitude" => 11.11, "optional" => ""}
    }
    assert validate(request, @schema) == {:error, [
      empty_parameter: "optional",
      parameter_missing: "longitude",
      invalid_parameter_type: "item_id",
      parameter_missing: "SCOPE",
    ]}
  end

  test "valid request with path and query parameters" do
    sanitized_request = %{@request |
      path_params: %{"SCOPE" => "foo", "item_id" => 123},
      query_params: %{"Latitude" => 11.11, "longitude" => 22.22}
    }
    assert validate(@request, @schema) === {:ok, sanitized_request}
  end

  test "overriding path-global parameter definition on operation level" do
    schema = %{
      "swagger" => "2.0",
      "info" => %{
          "version" => "0.1",
          "title" => "My awesome API"
      },
      "paths" => %{
        "/items" => %{
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
            ],
            "responses" => %{
              "200" => %{
                "description" => "OK"
              }
            }
          }
        }
      }
    }
    request = %Request{path: "/items", method: :get, query_params: %{"limit" => "foo"}}
    assert validate(request, schema) == {:ok, request}
  end

  test "parameter validation" do
    schema = %{
      "swagger" => "2.0",
      "info" => %{
          "version" => "0.1",
          "title" => "My awesome API"
      },
      "paths" => %{
        "/items" => %{
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
                "in" => "header",
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
                "required" => true,
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
                "required" => true,
                "enum" => ~w(foo bar)
              },
              %{
                "name" => "multiple_of",
                "in" => "query",
                "type" => "integer",
                "multipleOf" => 2
              },
            ],
            "responses" => %{
              "200" => %{
                "description" => "OK"
              }
            }
          }
        }
      }
    }

    request = %Request{
      path: "/items",
      method: :get,
      header_params: %{
        "minimum" => "10",
      },
      path_params: %{
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
      %ParameterError{error: %ValidationError.Minimum{exclusive?: true, expected: 10}, in: :header, parameter: "minimum"},
      %ParameterError{error: %ValidationError.Enum{}, in: :path, parameter: "enum"},
      %ParameterError{error: %ValidationError.MinLength{expected: 3, actual: 2}, in: :path, parameter: "min_length"},
      %ParameterError{error: %ValidationError.MaxLength{expected: 3, actual: 4}, in: :query, parameter: "max_length"},
      %ParameterError{error: %ValidationError.Maximum{exclusive?: false, expected: 100}, in: :query, parameter: "maximum"},
      %ParameterError{error: %ValidationError.MultipleOf{expected: 2}, in: :query, parameter: "multiple_of"},
      %ParameterError{error: %ValidationError.Pattern{expected: "^\\d+$"}, in: :query, parameter: "pattern"},
    ]}
  end

  test "parsing array parameters" do
    schema = %{
      "swagger" => "2.0",
      "info" => %{
          "version" => "0.1",
          "title" => "My awesome API"
      },
      "paths" => %{
        "/items" => %{
          "get" => %{
            "parameters" => [
              %{
                "name" => "already_array_ids",
                "in" => "query",
                "type" => "array",
              },
              %{
                "name" => "ids",
                "in" => "query",
                "type" => "array"
              },
              %{
                "name" => "csv_ids",
                "in" => "query",
                "type" => "array",
                "collectionFormat" => "csv"
              },
              %{
                "name" => "ssv_ids",
                "in" => "query",
                "type" => "array",
                "collectionFormat" => "ssv"
              },
              %{
                "name" => "tsv_ids",
                "in" => "query",
                "type" => "array",
                "collectionFormat" => "tsv"
              },
              %{
                "name" => "pipes_ids",
                "in" => "query",
                "type" => "array",
                "collectionFormat" => "pipes"
              },
            ],
            "responses" => %{
              "200" => %{
                "description" => "OK"
              }
            }
          }
        }
      }
    }

    request = %Request{
      path: "/items",
      method: :get,
      query_params: %{
        "already_array_ids" => ~w(foo bar baz),
        "ids" => "foo,bar,baz",
        "csv_ids" => "foo,bar,baz",
        "ssv_ids" => "foo bar baz",
        "tsv_ids" => "foo\tbar\tbaz",
        "pipes_ids" => "foo|bar|baz",
      },
    }

    assert validate(request, schema) == {:ok, %{request | query_params: %{
      "ids" => ~w(foo bar baz),
      "csv_ids" => ~w(foo bar baz),
      "ssv_ids" => ~w(foo bar baz),
      "tsv_ids" => ~w(foo bar baz),
      "pipes_ids" => ~w(foo bar baz),
      "already_array_ids" => ~w(foo bar baz),
    }}}
  end

  test "body validation" do
    schema = %{
      "swagger" => "2.0",
      "info" => %{
          "version" => "0.1",
          "title" => "My awesome API"
      },
      "paths" => %{
        "/items" => %{
          "post" => %{
            "parameters" => [
              %{
                "name" => "body",
                "in" => "body",
                "required" => true,
                "schema" => %{
                  "$ref" => "#/definitions/Item"
                }
              }
            ],
            "responses" => %{
              "200" => %{
                "description" => "OK"
              }
            }
          }
        }
      },
      "definitions" => %{
        "Item" => %{
          "type" => "object",
          "required" => ["foo", "bar"],
          "properties" => %{
            "foo" => %{
              "type" => "string"
            }
          }
        }
      }
    }

    request = %Request{
      path: "/items",
      method: :post,
      body: %{
        "foo" => 123
      },
    }

    assert validate(request, schema) == {:error, [
      %BodyError{error: %ValidationError.Type{actual: "Integer", expected: ["String"]}, path: "#/foo"},
      %BodyError{error: %ValidationError.Required{missing: ["bar"]}, path: "#"}
    ]}
  end
end
