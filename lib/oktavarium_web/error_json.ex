defmodule OktavariumWeb.ErrorJSON do
  @moduledoc false

  def render(template, _assigns) do
    code =
      template
      |> Phoenix.Controller.status_message_from_template()
      |> String.downcase()
      |> String.replace(" ", "_")

    %{error: %{code: code}}
  end
end
