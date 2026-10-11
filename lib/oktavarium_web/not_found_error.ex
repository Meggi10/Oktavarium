defmodule OktavariumWeb.NotFoundError do
  @moduledoc false
  defexception message: "nie znaleziono", plug_status: 404
end
