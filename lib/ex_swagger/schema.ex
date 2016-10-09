defmodule ExSwagger.Schema do
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
      Map.put(operations, path, %{operation |
        "parameters" => merge_parameters(path_global_parameters, operation["parameters"])
      })
    end
  end

  defp merge_parameters(global_parameters, parameters) do
    Enum.reduce global_parameters ++ parameters, %{}, fn parameter, acc ->
      Map.put(acc, {parameter["name"], parameter["in"]}, parameter)
    end
  end
end
