defmodule ExSwagger.ValidatorTest do
  use ExUnit.Case, async: true

  import ExSwagger.Validator
  alias ExSwagger.Validator.Request

  @schema "test/fixtures/uber.json" |> File.read! |> Poison.decode!
  @request %Request{path: "/products", method: :get, query_params: %{"latitude" => 11.11, "longitude" => "22.22"}}

  test "wrong path" do
    request = %Request{@request | path: "/foo"}
    assert validate(request, @schema) == {:error, :path_not_found}
  end

  test "wrong method" do
    request = %Request{@request | method: :patch}
    assert validate(request, @schema) == {:error, :method_not_allowed}
  end

  test "missing required parameter" do
    request = %Request{@request | query_params: %{"latitude" => 11.11}}
    assert validate(request, @schema) == {:error, [parameter_missing: "longitude"]}
  end

  test "empty parameter" do
    request = %Request{@request | query_params: %{@request.query_params | "longitude" => ""}}
    assert validate(request, @schema) == {:error, [empty_parameter: "longitude"]}
  end

  test "wrong parameter type" do
    request = %Request{@request | query_params: %{@request.query_params | "latitude" => "foo"}}
    assert validate(request, @schema) == {:error, [invalid_parameter_type: "latitude"]}
  end

  test "valid request" do
    assert validate(@request, @schema) == :ok
  end
end
