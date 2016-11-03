defmodule ExSwagger.Schema do
  @parameter_schema_properties ~w(
    maximum
    exclusiveMaximum
    minimum
    exclusiveMinimum
    maxLength
    minLength
    pattern
    maxItems
    minItems
    uniqueItems
    enum
    multipleOf
  )
  @empty_parameter_schemata %{
    header_params: %{"properties" => %{}},
    path_params: %{"properties" => %{}},
    query_params: %{"properties" => %{}}
  }

  def parse(%{} = schema) do
    %{schema | "paths" => parse_paths(schema["paths"])}
  end

  defp parse_paths(paths) do
    Enum.reduce paths, %{}, fn ({path, operations}, paths) ->
      Map.put(paths, path, operations_with_path_global_parameters(operations))
    end
  end

  defp operations_with_path_global_parameters(operations) do
    path_global_parameters = operations["parameters"] || []
    Enum.reduce Map.drop(operations, ["parameters"]), %{}, fn ({path, operation}, operations) ->
      parameters = path_global_parameters |> merge_parameters(operation["parameters"]) |> downcase_header_parameter_names
      Map.put(operations, path, Map.merge(operation, %{
        parameters: parameters,
        schemata: parameters_to_schema(parameters)
      }))
    end
  end

  defp merge_parameters(global_parameters, parameters) do
    Enum.reduce(global_parameters ++ parameters, %{}, fn parameter, acc ->
      Map.put(acc, {parameter["name"], parameter["in"]}, parameter)
    end) |> Map.values
  end

  defp downcase_header_parameter_names(parameters) do
    parameters |> Enum.map(&downcase_header_parameter_name/1)
  end

  defp downcase_header_parameter_name(%{"in" => "header"} = parameter), do: %{parameter | "name" => String.downcase(parameter["name"])}
  defp downcase_header_parameter_name(parameter), do: parameter

  defp parameters_to_schema(parameters) do
    Enum.reduce parameters, @empty_parameter_schemata, fn %{"name" => name, "in" => in_} = parameter, acc ->
      put_in(acc, [:"#{in_}_params", "properties", name], Map.take(parameter, @parameter_schema_properties))
    end
  end
end
