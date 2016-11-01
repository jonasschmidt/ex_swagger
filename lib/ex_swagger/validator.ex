defmodule ExSwagger.Validator do
  alias ExSwagger.{Request, Schema}
  alias ExJsonSchema.Validator.Error, as: ValidationError

  defmodule Result do
    defstruct request: nil, errors: []
  end

  defmodule ParameterError do
    defstruct [:error, :parameter, :in]
  end

  def validate(%Request{} = request, schema) do
    do_validate(request, Schema.parse(schema))
  end

  defp do_validate(request, schema) do
    validate_path(request, schema["paths"][request.path])
  end

  defp validate_path(_request, nil) do
    {:error, :path_not_found}
  end

  defp validate_path(request, path_item) do
    validate_operation(request, path_item[to_string(request.method)])
  end

  defp validate_operation(_request, nil) do
    {:error, :method_not_allowed}
  end

  defp validate_operation(request, operation) do
    validate_params(request, operation)
  end

  defp validate_params(request, operation) do
    parameters = Map.values(operation.parameters)
    result = Enum.reduce(parameters, %Result{request: request}, &(validate_param(&2, &1)))
    case result do
      %{errors: [], request: request} ->
        case validate_request_against_schemata(request, operation.schemata) do
          [] -> {:ok, request}
          errors -> {:error, errors}
        end
      %{errors: errors, request: request} ->
        {:error, errors}
    end
  end

  defp validate_request_against_schemata(request, schemata) do
    Enum.flat_map(schemata, &validate_request_against_schema(request, &1))
  end

  defp validate_request_against_schema(request, {:path_params, schema}) do
    validate_params_against_schema(request.path_params, schema) |> map_errors(:path)
  end

  defp validate_request_against_schema(request, {:query_params, schema}) do
    validate_params_against_schema(request.query_params, schema) |> map_errors(:query)
  end

  defp validate_params_against_schema(params, schema) do
    case ExJsonSchema.Validator.validate(schema, params) do
      :ok -> []
      {:error, errors} -> errors
    end
  end

  defp map_errors(errors, in_) do
    Enum.map errors, fn %ValidationError{error: error, path: "#/" <> path} ->
      %ParameterError{error: error, parameter: path, in: in_}
    end
  end

  defp validate_param(%Result{request: %Request{path_params: path_params}} = result, %{"in" => "path"} = parameter) do
    do_validate_param(result, parameter, path_params[parameter["name"]])
  end

  defp validate_param(%Result{request: %Request{query_params: query_params}} = result, %{"in" => "query"} = parameter) do
    do_validate_param(result, parameter, query_params[parameter["name"]])
  end

  defp do_validate_param(result, parameter, nil) do
    case parameter["required"] do
      true -> result_with_error(result, :parameter_missing, parameter["name"])
      false -> result
    end
  end

  defp do_validate_param(result, parameter, "") do
    result_with_error(result, :empty_parameter, parameter["name"])
  end

  defp do_validate_param(result, parameter, value) do
    case parse_value(value, parameter["type"]) do
      :error -> result_with_error(result, :invalid_parameter_type, parameter["name"])
      value -> overwrite_param(result, parameter, value)
    end
  end

  defp parse_value(value, "string") when is_binary(value), do: value
  defp parse_value(value, "number") when is_float(value), do: value
  defp parse_value(value, "number") when is_binary(value), do: handle_numeric_parse_result(Float.parse(value))
  defp parse_value(value, "integer") when is_integer(value), do: value
  defp parse_value(value, "integer") when is_binary(value), do: handle_numeric_parse_result(Integer.parse(value))

  defp handle_numeric_parse_result(:error), do: :error
  defp handle_numeric_parse_result({value, ""}), do: value
  defp handle_numeric_parse_result({_value, _remainder}), do: :error

  defp result_with_error(result, error, parameter_name) do
    %{result | errors: [{error, parameter_name} | result.errors]}
  end

  defp overwrite_param(result, parameter, value) do
    params_key = String.to_atom("#{parameter["in"]}_params")
    old_params = Map.get(result.request, params_key)
    params = Map.put(old_params, parameter["name"], value)
    %{result | request: Map.put(result.request, params_key, params)}
  end
end
