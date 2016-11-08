ExUnit.start()

defmodule TestHelper do
  def fixture(name) do
    "test/fixtures/#{name}.json" |> File.read! |> Poison.decode!
  end
end
