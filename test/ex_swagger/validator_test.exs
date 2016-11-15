defmodule ExSwagger.ValidatorTest do
  use ExUnit.Case, async: true

  import TestHelper
  import ExSwagger.Validator

  alias ExSwagger.Request
  alias ExSwagger.Validator.{ParameterError, BodyError, EmptyParameter, MissingParameter, InvalidDiscriminator}
  alias ExJsonSchema.Validator.Error, as: ValidationError

  @request %Request{
    path: "/items/{SCOPE}/{item_id}",
    method: :post,
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
    },
    body: %{
      "foo" => %{
        "bar" => 666
      }
    }
  }

  @sanitized_request %{@request |
    path_params: %{"SCOPE" => "foo", "item_id" => 123},
    query_params: %{"Latitude" => 11.11, "longitude" => 22.22}
  }

  test "invalid path" do
    request = %Request{@request | path: "/foo"}
    assert validate(request, fixture("parameters")) == {:error, :path_not_found}
  end

  test "invalid method" do
    request = %Request{@request | method: :get}
    assert validate(request, fixture("parameters")) == {:error, :method_not_allowed}
  end

  test "missing required header parameter" do
    request = %Request{@request | header_params: %{}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %MissingParameter{}, in: :header, parameter: "x-request-id"}
    ]}
  end

  test "missing required query parameter" do
    request = %Request{@request | query_params: %{"Latitude" => 11.11}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %MissingParameter{}, in: :query, parameter: "longitude"}
    ]}
  end

  test "missing required body parameter" do
    request = %Request{@request | body: nil}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %MissingParameter{}, in: :body, parameter: "body"}
    ]}
  end

  test "empty query parameters" do
    request = %Request{@request | query_params: %{@request.query_params | "Latitude" => "", "longitude" => nil}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %EmptyParameter{}, in: :query, parameter: "longitude"},
      %ParameterError{error: %EmptyParameter{}, in: :query, parameter: "Latitude"},
    ]}
  end

  test "allowed empty query parameter with nil value" do
    request = %Request{@request | query_params: Map.put(@request.query_params, "empty", nil)}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %ValidationError.Type{actual: "Null", expected: ["String"]}, in: :query, parameter: "empty"}
    ]}
  end

  test "allowed empty query parameter with empty string value" do
    request = %Request{@request | query_params: Map.put(@request.query_params, "empty", "")}
    sanitized_request = %Request{@sanitized_request | query_params: Map.put(@sanitized_request.query_params, "empty", "")}
    assert validate(request, fixture("parameters")) == {:ok, sanitized_request}
  end

  test "invalid query parameter type" do
    request = %Request{@request | query_params: %{@request.query_params | "Latitude" => "11.11foo"}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Number"]}, in: :query, parameter: "Latitude"}
    ]}
  end

  test "optional query parameter with invalid type" do
    request = %Request{@request | query_params: @request.query_params |> Map.put("optional", "123foo")}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, in: :query, parameter: "optional"}
    ]}
  end

  test "path param names are case-sensitive" do
    request = %Request{@request | path_params: %{"scope" => "foo", "item_id" => "123"}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %MissingParameter{}, in: :path, parameter: "SCOPE"}
    ]}
  end

  test "query param names are case-sensitive" do
    request = %Request{@request | query_params: %{"latitude" => 11.11, "longitude" => 22.22}}
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %MissingParameter{}, in: :query, parameter: "Latitude"}
    ]}
  end

  test "multiple validaton errors" do
    request = %Request{@request |
      path_params: %{"item_id" => "bar"},
      query_params: %{"Latitude" => 11.11, "optional" => ""},
      body: %{"foo" => %{"bar" => "baz"}}
    }
    assert validate(request, fixture("parameters")) == {:error, [
      %ParameterError{error: %EmptyParameter{}, in: :query, parameter: "optional"},
      %ParameterError{error: %MissingParameter{}, in: :query, parameter: "longitude"},
      %ParameterError{error: %MissingParameter{}, in: :path, parameter: "SCOPE"},
      %BodyError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, path: "#/foo/bar"},
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, in: :path, parameter: "item_id"},
    ]}
  end

  test "valid request with path and query parameters" do
    assert validate(@request, fixture("parameters")) === {:ok, @sanitized_request}
  end

  test "passing through parameters that are already sanitized/typecast" do
    request = %{@request | path_params: %{"SCOPE" => "foo", "item_id" => 123}}
    assert validate(request, fixture("parameters")) === {:ok, @sanitized_request}
  end

  test "overriding path-global parameter definition on operation level" do
    request = %Request{path: "/items", method: :get, query_params: %{"limit" => "foo"}}
    assert validate(request, fixture("parameter_override")) == {:ok, request}
  end

  test "validating parameters against their schema properties" do
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

    assert validate(request, fixture("parameter_validation")) == {:error, [
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

    assert validate(request, fixture("array_parameter_parsing")) == {:ok, %{request | query_params: %{
      "ids" => ~w(foo bar baz),
      "csv_ids" => ~w(foo bar baz),
      "ssv_ids" => ~w(foo bar baz),
      "tsv_ids" => ~w(foo bar baz),
      "pipes_ids" => ~w(foo bar baz),
      "already_array_ids" => ~w(foo bar baz),
    }}}
  end

  test "validating array parameter items against their schema" do
    request = %Request{
      path: "/items",
      method: :get,
      query_params: %{
        "ids" => "12.3,24foo,100",
      },
    }

    assert validate(request, fixture("array_parameter_validation")) == {:error, [
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, in: :query, parameter: "ids/0"},
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, in: :query, parameter: "ids/1"},
      %ParameterError{error: %ValidationError.Maximum{exclusive?: true, expected: 100}, in: :query, parameter: "ids/2"}
    ]}
  end

  test "returning sanitized array parameter items" do
    request = %Request{
      path: "/items",
      method: :get,
      query_params: %{
        "ids" => "12,24,36",
      },
    }

    assert validate(request, fixture("array_parameter_validation")) == {:ok, %{request | query_params: %{
      "ids" => [12, 24, 36],
    }}}
  end

  test "validating the body against its schema" do
    request = %Request{
      path: "/items",
      method: :post,
      body: %{
        "foo" => 123
      },
    }

    assert validate(request, fixture("body_validation")) == {:error, [
      %BodyError{error: %ValidationError.Type{actual: "Integer", expected: ["String"]}, path: "#/foo"},
      %BodyError{error: %ValidationError.Required{missing: ["bar"]}, path: "#"}
    ]}
  end

  test "validating body schema with discriminator" do
    request = %Request{
      path: "/items",
      method: :post,
      body: %{
        "item_id" => 123,
        "type" => "Foo",
        "foo" => 456
      },
    }

    assert validate(%{request | body: %{request.body | "type" => "Bar"}}, fixture("discriminator")) == {:error, [
      # %BodyError{error: %ValidationError.Required{missing: ["bar"]}, path: "#"}
      %BodyError{error: %ValidationError.AllOf{invalid_indices: [1]}, path: "#"}
    ]}

    assert validate(%{request | body: %{request.body | "type" => "Baz"}}, fixture("discriminator")) == {:error, [
      %BodyError{error: %InvalidDiscriminator{allowed: MapSet.new(~w(Item Foo Bar))}, path: "#/type"}
    ]}

    assert validate(request, fixture("discriminator")) == {:ok, request}
  end

  test "validating with a path item reference" do
    request = %Request{
      path: "/item/{item_id}",
      method: :get,
      path_params: %{
        "item_id" => "foo",
      },
    }

    assert validate(request, fixture("path_item_ref")) == {:error, [
      %ParameterError{error: %ValidationError.Type{actual: "String", expected: ["Integer"]}, in: :path, parameter: "item_id"}
    ]}
  end
end
