defmodule Bacon8Web.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  use Gettext, backend: Bacon8Web.Gettext

  @doc """
  Renders a modal.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <div
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <%= render_slot(@inner_block) %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.
  Updated: 2025-09-21 05:21 - Fixed delay option issue
  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :id_suffix, :any, default: nil, doc: "suffix to make flash IDs unique"
  attr :stack_index, :integer, default: 0, doc: "index in the flash stack for positioning"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  
  slot :inner_block

  def flash(assigns) do
    flash_id = if assigns.id_suffix do
      "flash-#{assigns.kind}-#{assigns.id_suffix}"
    else
      "flash-#{assigns.kind}"
    end
    
    assigns = assign(assigns, :flash_id, flash_id)
    
    # Calculate top position based on stack index (33px base + 110px per additional flash for spacing)
    # Stack index 0 = newest (top), higher index = older (pushed down)
    base_top = 33
    spacing = 110
    top_position = base_top + (assigns.stack_index * spacing)
    
    assigns = assign(assigns, :top_position, top_position)
    
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@flash_id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "##{@flash_id}", transition: {"transition-all duration-300", "opacity-100 translate-x-0", "opacity-0 translate-x-full"})}
      phx-mounted={JS.show(to: "##{@flash_id}", transition: {"transition-all duration-300", "opacity-0 translate-x-full", "opacity-100 translate-x-0"})}
      phx-remove={JS.hide(to: "##{@flash_id}", transition: {"transition-all duration-300", "opacity-100 translate-x-0", "opacity-0 translate-x-full"})}
      phx-hook="AutoDismissFlash"
      data-auto-dismiss="3000"
      data-key={@kind}
      role="alert"
      style={"position: fixed; top: #{@top_position}px; right: 8px; z-index: 99999;"}
      class={[
        "flash-notice w-80 sm:w-96 rounded-lg p-3 ring-1 cursor-pointer shadow-2xl backdrop-blur-sm",
        "hidden transition-all duration-300 ease-out pointer-events-auto",
        @kind == :info && "bg-emerald-100 text-emerald-900 ring-emerald-600 fill-cyan-900 border-2 border-emerald-500",
        @kind == :error && "bg-rose-100 text-rose-950 ring-rose-600 fill-rose-900 border-2 border-rose-500"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        <%= @title %>
      </p>
      <p class="mt-2 text-sm leading-5"><%= msg %></p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: nil, doc: "the optional id of flash container"

  def flash_group(assigns) do
    assigns = assign(assigns, :flash_id, assigns.id || "flash-group")

    # Collect all active flash messages with their types and stable IDs
    # We include a hash of the message in the ID to force re-mounting when the message changes
    # even if the kind is the same. This ensures the animation plays again.
    active_flashes = [
      {:info, Phoenix.Flash.get(assigns.flash, :info), :info},
      {:error, Phoenix.Flash.get(assigns.flash, :error), :error}
    ] 
    |> Enum.filter(fn {_, msg, _} -> msg end)
    |> Enum.map(fn {kind, msg, _} -> 
      {kind, msg, "#{kind}-#{:erlang.phash2(msg)}"}
    end)

    assigns = assign(assigns, :active_flashes, active_flashes)

    ~H"""
    <div id={@flash_id}>
      <%= for {{kind, _message, stable_id}, index} <- Enum.with_index(@active_flashes) do %>
        <.flash kind={kind} title={if(kind == :info, do: "Success!", else: "Error!")} flash={@flash} id_suffix={stable_id} stack_index={index} />
      <% end %>
    </div>
    """
  end

  @doc """
  A small pagination component that renders page links and prev/next buttons.

  Usage:
    <.pagination current_page={@current_page} total_pages={@total_pages} on_page_change="change_page" />
  """
  attr :current_page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :on_page_change, :string, required: true
  attr :page_size, :integer, default: nil
  attr :rest, :global, include: ~w(id class)

  def pagination(assigns) do
    assigns = assign_new(assigns, :current_page, fn -> 1 end)
    assigns = assign_new(assigns, :total_pages, fn -> 1 end)
    assigns = assign_new(assigns, :on_page_change, fn -> "change_page" end)

    # compute a small window of pages around the current page
    pages =
      if assigns.total_pages <= 7 do
        Enum.to_list(1..assigns.total_pages)
      else
        start_page = max(1, assigns.current_page - 2)
        end_page = min(assigns.total_pages, assigns.current_page + 2)
        pages = Enum.to_list(start_page..end_page)

        # ensure we include first/last when necessary
        pages =
          pages
          |> maybe_prepend(1)
          |> maybe_append(assigns.total_pages)

        pages
      end

    assigns = assign(assigns, :pages, pages)

    ~H"""
    <nav aria-label="Pagination" {@rest} class={"flex items-center gap-2"}>
      <button
        :if={@current_page > 1}
        phx-click={@on_page_change}
        phx-value-page={@current_page - 1}
        class="px-3 py-1 bg-zinc-800 text-white rounded"
      >
        ‹ Prev
      </button>

      <%= for page <- @pages do %>
        <button
          phx-click={@on_page_change}
          phx-value-page={page}
          class={"px-3 py-1 rounded " <> if(page == @current_page, do: "bg-blue-600 text-white", else: "bg-zinc-800 text-gray-200")}
        >
          <%= page %>
        </button>
      <% end %>

      <button
        :if={@current_page < @total_pages}
        phx-click={@on_page_change}
        phx-value-page={@current_page + 1}
        class="px-3 py-1 bg-zinc-800 text-white rounded"
      >
        Next ›
      </button>
    </nav>
    """
  end

  defp maybe_prepend(pages, 1) do
    if List.first(pages) == 1, do: pages, else: [1 | pages]
  end

  defp maybe_append(pages, last) do
    if List.last(pages) == last, do: pages, else: pages ++ [last]
  end

  @doc """
  Renders a simple form.
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :label_class, :string, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class={["flex items-center gap-4 text-sm leading-6", @label_class || "text-zinc-600"]}>
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id} class={@label_class}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id} class={@label_class}><%= @label %></.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id} class={@label_class}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class={["block text-sm font-semibold leading-6", @class || "text-zinc-800"]}>
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal"><%= col[:label] %></th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only"><%= gettext("Actions") %></span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a list of items.
  """
  attr :id, :string, required: true
  attr :items, :list, required: true
  attr :item_id, :any, default: nil, doc: "the function for generating the item id"
  attr :item_click, :any, default: nil, doc: "the function for handling phx-click on each item"

  slot :item, required: true do
    attr :title, :string
    attr :subtitle, :string
  end

  slot :action, doc: "the slot for showing user actions in the last item column"

  def list(assigns) do
    assigns =
      with %{items: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, item_id: assigns.item_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="mt-11">
      <div
        id={@id}
        phx-update={match?(%Phoenix.LiveView.LiveStream{}, @items) && "stream"}
        class="divide-y divide-zinc-100 border-t border-zinc-200"
      >
        <div
          :for={item <- @items}
          id={@item_id && @item_id.(item)}
          class="group hover:bg-zinc-50"
        >
          <div class="flex items-center justify-between gap-6 py-4">
            <div class="flex gap-4">
              <div class="flex-auto">
                <p class="text-sm font-semibold leading-6 text-zinc-900">
                  <%= render_slot(@item, item) %>
                </p>
                <p class="mt-1 text-xs leading-5 text-zinc-500">
                  <%= render_slot(@item, item) %>
                </p>
              </div>
            </div>
            <div class="flex flex-none items-center gap-x-4">
              <div
                :for={action <- @action}
                class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
              >
                <%= render_slot(action, item) %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  @doc """
  Renders an icon.
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def hide_flash(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-in duration-300",
         "transform translate-x-0 opacity-100",
         "transform translate-x-full opacity-0"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(Bacon8Web.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Bacon8Web.Gettext, "errors", msg, opts)
    end
  end

  def translate_error(msg), do: msg
end