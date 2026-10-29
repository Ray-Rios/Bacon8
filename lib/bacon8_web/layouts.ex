defmodule Bacon8Web.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered around other layouts.
  """
  use Bacon8Web, :html
  # Navigation import removed - not used

  embed_templates "layouts/*"

  @doc "The background kinds drawn as a cosmos (the rest, gradient and solid, are flat colours)."
  def cosmos_backgrounds, do: Bacon8Web.Components.Cosmos.kinds()
end