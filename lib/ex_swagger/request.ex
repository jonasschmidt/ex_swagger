defmodule ExSwagger.Request do
  defstruct [:path, :method, :header_params, :path_params, :query_params, :body_params]
end
