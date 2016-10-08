defmodule ExSwagger.Validator do
  defmodule Request do
    defstruct [:path, :method, :query_params]
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
    validate_query_params(request.query_params, operation["parameters"])
  end

  defp validate_query_params(params, parameters) do
    errors = Enum.flat_map parameters, fn parameter_schema ->
      validate_query_param(params[parameter_schema["name"]], parameter_schema)
    end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_query_param(nil, parameter_schema) do
    case parameter_schema["required"] do
      true -> [parameter_missing: parameter_schema["name"]]
      false -> []
    end
  end

  defp validate_query_param("", parameter_schema) do
    [empty_parameter: parameter_schema["name"]]
  end

  defp validate_query_param(value, parameter_schema) do
    case parse_value(value, parameter_schema["type"]) do
      :error -> [invalid_parameter_type: parameter_schema["name"]]
      _ -> []
    end
  end

  defp parse_value(value, "number") when is_float(value), do: value
  defp parse_value(value, "number"), do: Float.parse(value)
end
