defmodule ExSwagger.Validator do
  defmodule Request do
    defstruct [:path, :method, :path_params, :query_params]
  end

  defmodule Result do
    defstruct request: nil, errors: []
  end

  def validate(%Request{} = request, schema) do
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
    validate_params(request, operation["parameters"])
  end

  defp validate_params(request, parameters) do
    result = Enum.reduce(parameters, %Result{request: request}, &(validate_param(&2, &1)))
    case result do
      %{errors: [], request: request} -> {:ok, request}
      %{errors: errors} -> {:error, errors}
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
