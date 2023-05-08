defmodule OpentelemetryExUnitFormatter do
  @moduledoc """
  #{File.read!("README.md") |> String.split("<!-- MDOC !-->") |> Enum.fetch!(1)}
  """

  use GenServer

  defstruct register_after_suite?: false,
            root_attribute: "code",
            span_name: "ex_unit",
            tracer_provider_config: :none

  @type t() :: %__MODULE__{
          register_after_suite?: boolean(),
          root_attribute: String.t(),
          span_name: :opentelemetry.span_name(),
          tracer_provider_config: map() | :none
        }

  @attr_suite "suite"
  @attr_module "module"
  @attr_test "test"

  @doc false
  @impl GenServer
  def init(opts) do
    config =
      __MODULE__
      |> Application.get_application()
      |> Application.get_all_env()
      |> Enum.into(%{})
      |> then(&Map.merge(struct!(__MODULE__), &1))
      |> Map.put(:seed, opts[:seed])
      |> Map.put(:partition_no, System.get_env("MIX_TEST_PARTITION", ""))

    {tracer_provider_config, config} = Map.pop!(config, :tracer_provider_config)
    do_init(tracer_provider_config, config)
  end

  defp do_init(:none, _config) do
    IO.puts("[#{__MODULE__}] Tracer provider is disabled.")
    {:ok, %{tracer_provider: :none}}
  end

  defp do_init(tracer_provider_config, config) do
    {name, vsn, schema_url} =
      case :opentelemetry.get_application(__MODULE__) do
        {name, vsn, schema_url} ->
          {name, vsn, schema_url}

        _undef ->
          {Application.get_application(__MODULE__), Mix.Project.config()[:version], :undefined}
      end

    case :otel_tracer_provider.get_tracer(__MODULE__, name, vsn, schema_url) do
      {:otel_tracer_noop, []} ->
        {:ok, _pid} = :opentelemetry.start_tracer_provider(__MODULE__, tracer_provider_config)
        tracer = :otel_tracer_provider.get_tracer(__MODULE__, name, vsn, schema_url)
        register_after_suite(config.register_after_suite?, tracer_provider_config)
        config = Map.put(config, :tracer_provider, tracer)
        {:ok, config}

      tracer ->
        config = Map.put(config, :tracer_provider, tracer)
        {:ok, config}
    end
  end

  @doc false
  @impl GenServer
  def handle_cast(_request, %{tracer_provider: :none} = state), do: {:noreply, state}

  @doc false
  @impl GenServer
  def handle_cast({e, _data} = event, state)
      when e in [
             :suite_finished,
             :module_finished,
             :test_finished
           ] do
    event
    |> normalize_event()
    |> emit_span(state)

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_cast(_event, state), do: {:noreply, state}

  defp register_after_suite(true, tracer) do
    {type, name, delay} =
      case tracer do
        %{processors: [{:otel_simple_processor, %{name: name} = config}]} ->
          delay = Map.get(config, :bsp_scheduled_delay_ms, 5000)
          {"simple", name, delay}

        %{processors: [{:otel_batch_processor, %{name: name} = config}]} ->
          delay = Map.get(config, :bsp_scheduled_delay_ms, 5000)
          {"batch", name, delay}

        _ ->
          {nil, nil, nil}
      end

    if !is_nil(type) do
      ExUnit.after_suite(fn _result ->
        IO.puts("Flushing otel #{type} processor [#{name}] with #{delay} msec waiting time...")
        :otel_tracer_provider.force_flush(name)
        Process.sleep(delay)
        IO.puts("Flushing otel processor completed.")
      end)
    end

    :ok
  end

  defp register_after_suite(false, _tracer), do: :ok

  defp normalize_event({:suite_finished, %{run: run, async: async, load: load}}) do
    sync = run - (async || 0)
    total = run + (load || 0)

    %{
      event_type: @attr_suite,
      duration_run: run,
      duration_async: async,
      duration_sync: sync,
      duration_load: load,
      duration: total
    }
  end

  defp normalize_event(
         {:module_finished,
          %ExUnit.TestModule{
            file: file,
            name: name,
            state: state,
            tests: tests
          }}
       ) do
    {state, state_reason} = normalize_state(state)

    %{
      event_type: @attr_module,
      filepath: file,
      module_name: name,
      state: state,
      state_reason: state_reason,
      tests_count: Enum.count(tests),
      duration: Enum.reduce(tests, 0, fn %ExUnit.Test{time: time}, acc -> time + acc end)
    }
  end

  defp normalize_event(
         {:test_finished,
          %ExUnit.Test{
            logs: logs,
            name: name,
            module: module,
            state: state,
            tags: %{async: async, file: file, line: line, test_type: test_type},
            time: time
          }}
       ) do
    {state, state_reason} = normalize_state(state)

    %{
      event_type: @attr_test,
      test_logs: logs,
      test_name: name,
      module_name: module,
      state: state,
      state_reason: state_reason,
      exec_async: async,
      filepath: file,
      lineno: line,
      file_line: "#{file}:#{line}",
      test_type: test_type,
      duration: time
    }
  end

  defp normalize_state(nil), do: {:ok, ""}
  defp normalize_state({state, reason}), do: {state, inspect(reason)}

  defp emit_span(%{duration: duration, event_type: span_type} = attributes, %{
         partition_no: partition_no,
         root_attribute: root_attribute,
         seed: seed,
         span_name: span_name,
         tracer_provider: tracer
       }) do
    status = get_status(attributes)
    status_reason = Map.get(attributes, :state_reason, "")

    attributes = Map.put(attributes, :test_partition_no, partition_no)
    attributes = Map.put(attributes, :test_seed, seed)
    attributes = prefix_root_attribute(attributes, root_attribute)

    start_time =
      :opentelemetry.timestamp() - :erlang.convert_time_unit(duration, :microsecond, :native)

    :otel_tracer.with_span(
      tracer,
      "#{span_name}.#{span_type}",
      %{start_time: start_time},
      fn span_ctx ->
        :otel_span.set_status(span_ctx, status, status_reason)
        :otel_span.set_attributes(span_ctx, attributes)
      end
    )
  end

  defp get_status(attributes) do
    case Map.get(attributes, :state) do
      :ok -> :ok
      :failed -> :error
      _any -> :unset
    end
  end

  defp prefix_root_attribute(attributes, root_attribute) do
    attributes
    |> Enum.map(fn {k, v} -> {:"#{root_attribute}.#{k}", v} end)
    |> Enum.into(%{})
  end
end
