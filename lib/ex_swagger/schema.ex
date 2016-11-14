defmodule ExSwagger.Schema do
  @swagger_schema ExSwagger.Schema.Swagger20.schema |> ExJsonSchema.Schema.resolve
  @parameter_schema_properties ~w(
    type
    items
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
    header_params: %{schema: %{"properties" => %{}}},
    path_params: %{schema: %{"properties" => %{}}},
    query_params: %{schema: %{"properties" => %{}}},
    body: %{schema: %{}}
  }

  def parse(%{} = schema) do
    case validate(schema) do
      :ok ->
        {:ok, parse_schema(ExJsonSchema.Schema.resolve(schema))}
      {:error, errors} ->
        {:error, errors}
    end
  end

  defp validate(schema) do
    ExJsonSchema.Validator.validate(@swagger_schema, schema)
  end

  defp parse_schema(root_schema) do
    root_schema
    |> resolve_discriminators
    |> resolve_paths
  end

  defp resolve_discriminators(root_schema) do
    definitions = root_schema.schema["definitions"] || %{}

    definitions = definitions
    |> Enum.filter(fn {_name, definition} -> Map.has_key?(definition, "discriminator") end)
    |> Keyword.keys
    |> Enum.reduce(definitions, &definitions_with_allowed_discriminator_schemata/2)

    %{root_schema | schema: Map.put(root_schema.schema, "definitions", definitions)}
  end

  defp definitions_with_allowed_discriminator_schemata(name, definitions) do
    allowed = definitions
    |> Enum.filter(fn {_name, definition} ->
      Enum.any?(definition["allOf"] || [], &(List.last(&1["$ref"] || []) == name))
    end)
    |> Keyword.keys
    |> MapSet.new
    |> MapSet.put(name)

    put_in(definitions, [name, :allowed_schemata], allowed)
  end

  defp resolve_paths(%ExJsonSchema.Schema.Root{schema: %{"paths" => paths}} = root_schema) do
    paths = Enum.reduce paths, %{}, fn ({path, operations}, paths) ->
      Map.put(paths, path, operations_with_path_global_parameters(operations, root_schema))
    end
    %{root_schema.schema | "paths" => paths}
  end

  defp operations_with_path_global_parameters(operations, root_schema) do
    path_global_parameters = operations["parameters"] || []
    Enum.reduce Map.drop(operations, ["parameters"]), %{}, fn ({path, operation}, operations) ->
      parameters = sanitize_parameters(path_global_parameters, operation["parameters"], root_schema)
      Map.put(operations, path, Map.merge(operation, %{
        parameters: parameters,
        schemata: parameters_to_schema(parameters, root_schema)
      }))
    end
  end

  defp sanitize_parameters(path_global_parameters, operation_parameters, root_schema) do
    path_global_parameters ++ operation_parameters
    |> resolve_parameter_refs(root_schema)
    |> merge_parameters
    |> downcase_header_parameter_names
  end

  defp resolve_parameter_refs(parameters, root_schema) do
    Enum.map parameters, fn
      %{"$ref" => ref} -> ExJsonSchema.Schema.get_ref_schema(root_schema, ref)
      parameter -> parameter
    end
  end

  defp merge_parameters(parameters) do
    Enum.reduce(parameters, %{}, fn %{"name" => name, "in" => in_} = parameter, acc ->
      Map.put(acc, {name, in_}, %{parameter | "in" => String.to_atom(in_)})
    end) |> Map.values
  end

  defp downcase_header_parameter_names(parameters) do
    parameters |> Enum.map(fn
      %{"in" => :header} = parameter -> %{parameter | "name" => String.downcase(parameter["name"])}
      parameter -> parameter
    end)
  end

  defp parameters_to_schema(parameters, root_schema) do
    schemata = @empty_parameter_schemata
    |> Enum.map(fn {key, val} -> {key, Map.put(val, :root_schema, root_schema)} end)
    |> Enum.into(%{})
    Enum.reduce parameters, schemata, &parameter_to_schema/2
  end

  defp parameter_to_schema(%{"in" => :body, "schema" => schema}, acc), do: put_in(acc, [:body, :schema], schema)
  defp parameter_to_schema(%{"name" => name, "in" => in_} = parameter, acc) do
    put_in(acc, [:"#{in_}_params", :schema, "properties", name], Map.take(parameter, @parameter_schema_properties))
  end
end
