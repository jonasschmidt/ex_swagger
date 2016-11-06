defmodule ExSwagger.Validator do
  alias ExSwagger.{Request, Schema}
  alias ExJsonSchema.Validator.Error, as: ValidationError

  defmodule Result, do: defstruct request: nil, errors: []
  defmodule ParameterError, do: defstruct [:error, :parameter, :in]
  defmodule BodyError, do: defstruct [:error, :path]
  defmodule EmptyParameter, do: defstruct []
  defmodule MissingParameter, do: defstruct []

  def validate(%Request{} = request, %{} = schema) do
    {:ok, schema} = Schema.parse(schema)
    validate_path(request, schema["paths"][request.path])
  end

  defp validate_path(_request, nil), do: {:error, :path_not_found}
  defp validate_path(request, path_item), do: validate_operation(request, path_item[to_string(request.method)])

  defp validate_operation(_request, nil), do: {:error, :method_not_allowed}
  defp validate_operation(request, operation), do: validate_params(request, operation)

  defp validate_params(request, %{parameters: parameters, schemata: schemata}) do
    result = Enum.reduce(parameters, %Result{request: request}, &(validate_param(&2, &1)))
    case result do
      %{errors: [], request: request} ->
        case validate_request_against_schemata(request, schemata) do
          [] -> {:ok, request}
          errors -> {:error, errors}
        end
      %{errors: errors, request: request} ->
        {:error, validate_request_against_schemata(request, schemata, errors)}
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
        schemata |> Map.drop([:body])
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
  defp validate_request_against_schema(request, {:body, schema}), do:
    validate_params_against_schema(request.body, schema) |> map_body_errors

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
    do_validate_param(result, parameter, params[parameter["name"]])
  defp validate_param(%Result{request: %Request{path_params: params}} = result, %{"in" => :path} = parameter), do:
    do_validate_param(result, parameter, params[parameter["name"]])
  defp validate_param(%Result{request: %Request{query_params: params}} = result, %{"in" => :query} = parameter), do:
    do_validate_param(result, parameter, params[parameter["name"]])
  defp validate_param(%Result{request: %Request{body: params}} = result, %{"in" => :body} = parameter), do:
    do_validate_param(result, parameter, params)

  defp do_validate_param(result, %{"name" => name, "in" => in_} = parameter, nil) do
    case parameter["required"] do
      true -> result_with_error(result, %ParameterError{error: %MissingParameter{}, parameter: name, in: in_})
      _ -> result
    end
  end

  defp do_validate_param(result, %{"name" => name, "in" => in_}, "") do
    result_with_error(result, %ParameterError{error: %EmptyParameter{}, parameter: name, in: in_})
  end

  defp do_validate_param(result, %{"in" => :body}, _value), do: result

  defp do_validate_param(result, parameter, value) do
    value = parse_value(value, parameter)
    overwrite_param(result, parameter, value)
  end

  defp parse_value(value, %{"type" => "string"}) when is_binary(value), do: value
  defp parse_value(value, %{"type" => "number"}) when is_float(value), do: value
  defp parse_value(value, %{"type" => "number"}) when is_binary(value), do: numeric_parse_result(Float.parse(value), value)
  defp parse_value(value, %{"type" => "integer"}) when is_integer(value), do: value
  defp parse_value(value, %{"type" => "integer"}) when is_binary(value), do: numeric_parse_result(Integer.parse(value), value)
  defp parse_value(value, %{"type" => "array"}) when is_list(value), do: value
  defp parse_value(value, %{"type" => "array"} = parameter) when is_binary(value), do: parse_array(value, parameter["collectionFormat"])

  defp parse_array(value, collection_format) when collection_format in [nil, "csv"], do: String.split(value, ",")
  defp parse_array(value, "ssv"), do: String.split(value, " ")
  defp parse_array(value, "tsv"), do: String.split(value, "\t")
  defp parse_array(value, "pipes"), do: String.split(value, "|")

  defp numeric_parse_result(:error, original_value), do: original_value
  defp numeric_parse_result({value, ""}, _original_value), do: value
  defp numeric_parse_result({_value, _remainder}, original_value), do: original_value

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
