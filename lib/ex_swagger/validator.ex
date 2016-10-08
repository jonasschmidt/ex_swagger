defmodule ExSwagger.Validator do
  defmodule Request do
    defstruct [:path, :method, :path_params, :query_params]
  end

  def validate(%Request{} = request, schema) do
    validate_path(request, schema["paths"][request.path])
  end

  defp validate_path(_request, nil) do
    {:error, :path_not_found}
  end

  defp validate_path(request, path_item) do
    validate_method(request, path_item[to_string(request.method)])
  end

  defp validate_method(_request, nil) do
    {:error, :method_not_allowed}
  end

  defp validate_method(request, operation) do
    validate_params(request, operation["parameters"])
  end

  defp validate_params(request, parameters) do
    errors = Enum.flat_map parameters, &(validate_param(request, &1))
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_param(%Request{path_params: path_params}, %{"in" => "path"} = parameter) do
    do_validate_param(path_params[parameter["name"]], parameter)
  end

  defp validate_param(%Request{query_params: query_params}, %{"in" => "query"} = parameter) do
    do_validate_param(query_params[parameter["name"]], parameter)
  end

  defp do_validate_param(nil, parameter) do
    case parameter["required"] do
      true -> [parameter_missing: parameter["name"]]
      false -> []
    end
  end

  defp do_validate_param("", parameter) do
    [empty_parameter: parameter["name"]]
  end

  defp do_validate_param(value, parameter) do
    case parse_value(value, parameter["type"]) do
      :error -> [invalid_parameter_type: parameter["name"]]
      _ -> []
    end
  end

  defp parse_value(value, "string") when is_binary(value), do: value
  defp parse_value(value, "number") when is_float(value), do: value
  defp parse_value(value, "number"), do: Float.parse(value)
end
