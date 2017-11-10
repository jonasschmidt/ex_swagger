defmodule ExSwagger.Validator do
  alias ExSwagger.{Request, Response, Schema}
  alias ExJsonSchema.Validator.Error, as: ValidationError

  defmodule Result, do: defstruct request: nil, errors: []
  defmodule ParameterError, do: defstruct [:error, :parameter, :in]
  defmodule BodyError, do: defstruct [:error, :path]
  defmodule HeaderError, do: defstruct [:error, :header]
  defmodule EmptyParameter, do: defstruct []
  defmodule MissingParameter, do: defstruct []
  defmodule InvalidDiscriminator, do: defstruct allowed: []

  def validate(%Request{} = request, %{} = schema) do
    {:ok, root_schema} = Schema.parse(schema)
    validate_path(request, root_schema.schema["paths"][request.path])
  end

  def validate(%Response{} = response, %{} = schema) do
    {:ok, root_schema} = Schema.parse(schema)
    operation = get_in(root_schema.schema, ["paths", response.request.path, to_string(response.request.method)])
    validate_response_with_operation(response, operation, root_schema)
  end

  defp validate_response_with_operation(response, operation, root_schema) do
    response_item = operation.responses[to_string(response.status)]
    errors = validate_response_headers(response, response_item, root_schema) ++
      validate_response_body(response, response_item, root_schema)
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_response_headers(response, %{"headers" => header_objects}, root_schema) do
    headers = sanitize_response_headers(response.headers, header_objects)
    errors = ExJsonSchema.Validator.validation_errors(root_schema, %{"properties" => header_objects}, headers)
    Enum.map errors, fn %ValidationError{error: error, path: "#/" <> header} ->
      %HeaderError{error: error, header: header}
    end
  end
  defp validate_response_headers(_response, _response_item, _root_schema), do: []

  defp sanitize_response_headers(headers, header_objects) do
    Enum.reduce headers, %{}, fn {k, v}, acc ->
      case header_objects[k] do
        nil -> acc
        header_object -> Map.put(acc, k, sanitize_value(v, header_object))
      end
    end
  end

  defp validate_response_body(response, response_item, root_schema) do
    errors = do_validate_response_body(response, response_item, root_schema)
    Enum.map errors, fn %ValidationError{error: error, path: path} ->
      %BodyError{error: error, path: path}
    end
  end

  defp do_validate_response_body(_response, nil, _root_schema), do: :error
  defp do_validate_response_body(response, %{"schema" => schema}, root_schema), do:
    ExJsonSchema.Validator.validation_errors(root_schema, schema, response.body)

  defp validate_path(_request, nil), do: {:error, :path_not_found}
  defp validate_path(request, path_item), do: validate_operation(request, path_item[to_string(request.method)])

  defp validate_operation(_request, nil), do: {:error, :method_not_allowed}
  defp validate_operation(request, operation), do: validate_params(request, operation)

  defp validate_params(request, %{parameters: parameters, schemata: schemata}) do
    %{errors: errors, request: request} = Enum.reduce(parameters, %Result{request: request}, &(validate_param(&2, &1)))
    case validate_request_against_schemata(request, schemata, errors) do
      [] -> {:ok, request}
      errors -> {:error, errors}
    end
  end

  defp validate_request_against_schemata(request, schemata, errors) do
    schemata = schemata |> schemata_without_invalid_parameters(errors)
    errors ++ validate_request_against_schemata(request, schemata)
  end

  defp validate_request_against_schemata(request, schemata) do
    Enum.flat_map(schemata, &validate_request_against_schema(request, &1))
  end

  defp schemata_without_invalid_parameters(schemata, errors) do
    Enum.reduce errors, schemata, fn
      %{in: :body}, schemata ->
        schemata |> Map.drop([:body_params])
      %{parameter: p, in: in_}, schemata ->
        schemata |> put_in([:"#{in_}_params", :schema, "properties", p], %{})
    end
  end

  defp validate_request_against_schema(request, {:header_params, schema}), do:
    validate_params_against_schema(request.header_params, schema) |> map_parameter_errors(:header)
  defp validate_request_against_schema(request, {:path_params, schema}), do:
    validate_params_against_schema(request.path_params, schema) |> map_parameter_errors(:path)
  defp validate_request_against_schema(request, {:query_params, schema}), do:
    validate_params_against_schema(request.query_params, schema) |> map_parameter_errors(:query)
  defp validate_request_against_schema(request, {:body_params, schema}), do:
    validate_params_against_schema(request.body_params, schema) |> map_body_errors

  defp validate_params_against_schema(params, %{schema: %{"discriminator" => discriminator, allowed_schemata: allowed}} = schema) do
    case allowed[params[discriminator]] do
      nil ->
        [%ValidationError{error: %InvalidDiscriminator{allowed: Map.keys(allowed)}, path: "#/#{discriminator}"}]
      fragment ->
        ExJsonSchema.Validator.validation_errors(schema.root_schema, fragment, params)
    end
  end
  defp validate_params_against_schema(params, schema) do
    ExJsonSchema.Validator.validation_errors(schema.root_schema, schema.schema, params)
  end

  defp map_parameter_errors(errors, in_) do
    Enum.map errors, fn %ValidationError{error: error, path: "#/" <> path} ->
      %ParameterError{error: error, parameter: path, in: in_}
    end
  end

  defp map_body_errors(errors) do
    Enum.map errors, fn %ValidationError{error: error, path: path} -> %BodyError{error: error, path: path} end
  end

  defp validate_param(%Result{request: %Request{header_params: params}} = result, %{"in" => :header} = parameter), do:
    do_validate_param(result, parameter, params[parameter["name"]], params)
  defp validate_param(%Result{request: %Request{path_params: params}} = result, %{"in" => :path} = parameter), do:
    do_validate_param(result, parameter, params[parameter["name"]], params)
  defp validate_param(%Result{request: %Request{query_params: params}} = result, %{"in" => :query} = parameter), do:
    do_validate_param(result, parameter, params[parameter["name"]], params)
  defp validate_param(%Result{request: %Request{body_params: params}} = result, %{"in" => :body} = parameter), do:
    do_validate_param(result, parameter, params)

  defp do_validate_param(result, parameter, value, params \\ %{})

  defp do_validate_param(result, %{"name" => name, "in" => in_} = parameter, value, params) when value in [nil, ""] do
    required = parameter["required"]

    case Map.has_key?(params, name) do
      true ->
        case parameter["allowEmptyValue"] do
          true -> result
          _ -> result_with_error(result, %ParameterError{error: %EmptyParameter{}, parameter: name, in: in_})
        end
      false when required == true ->
        result_with_error(result, %ParameterError{error: %MissingParameter{}, parameter: name, in: in_})
      _ -> result
    end
  end

  defp do_validate_param(result, %{"in" => :body}, _value, _params), do: result

  defp do_validate_param(result, parameter, value, _params) do
    overwrite_param(result, parameter, sanitize_value(value, parameter))
  end

  defp sanitize_value(value, %{"type" => "string"}) when is_binary(value), do: value
  defp sanitize_value(value, %{"type" => "number"}) when is_float(value), do: value
  defp sanitize_value(value, %{"type" => "number"}) when is_binary(value), do: numeric_parse_result(Float.parse(value), value)
  defp sanitize_value(value, %{"type" => "integer"}) when is_integer(value), do: value
  defp sanitize_value(value, %{"type" => "integer"}) when is_binary(value), do: numeric_parse_result(Integer.parse(value), value)
  defp sanitize_value(value, %{"type" => "array"}) when is_list(value), do: value
  defp sanitize_value(value, %{"type" => "array"} = parameter) when is_binary(value), do: sanitize_array(value, parameter)

  defp numeric_parse_result(:error, original_value), do: original_value
  defp numeric_parse_result({value, ""}, _original_value), do: value
  defp numeric_parse_result({_value, _remainder}, original_value), do: original_value

  defp sanitize_array(value, %{"collectionFormat" => "csv"} = parameter), do: value |> split_and_sanitize(",", parameter)
  defp sanitize_array(value, %{"collectionFormat" => "ssv"} = parameter), do: value |> split_and_sanitize(" ", parameter)
  defp sanitize_array(value, %{"collectionFormat" => "tsv"} = parameter), do: value |> split_and_sanitize("\t", parameter)
  defp sanitize_array(value, %{"collectionFormat" => "pipes"} = parameter), do: value |> split_and_sanitize("|", parameter)
  defp sanitize_array(value, parameter), do: value |> split_and_sanitize(",", parameter)

  defp split_and_sanitize(value, delimiter, parameter) do
    items_schema = parameter["items"] || %{"type" => "string"}
    value |> String.split(delimiter) |> Enum.map(&(sanitize_value(&1, items_schema)))
  end

  defp result_with_error(result, error) do
    %{result | errors: [error | result.errors]}
  end

  defp overwrite_param(result, parameter, value) do
    params_key = String.to_atom("#{parameter["in"]}_params")
    old_params = Map.get(result.request, params_key)
    params = Map.put(old_params, parameter["name"], value)
    %{result | request: Map.put(result.request, params_key, params)}
  end
end
