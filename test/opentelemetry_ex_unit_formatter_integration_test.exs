defmodule OpentelemetryExUnitFormatterIntegrationTest do
  use ExUnit.Case
  require Record

  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  defmacro assert_attributes(attributes, root_attribute, kind) do
    quote do
      attributes = unquote(attributes)
      root_attribute = unquote(root_attribute)
      kind = unquote(kind)

      assert "test" == Map.fetch!(attributes, String.to_atom(root_attribute <> ".event_type"))
      assert false == Map.fetch!(attributes, String.to_atom(root_attribute <> ".exec_async"))

      assert "" == Map.get(attributes, String.to_atom(root_attribute <> ".test_partition_no"))
      assert :test == Map.fetch!(attributes, String.to_atom(root_attribute <> ".test_type"))

      case kind do
        :successful ->
          assert __MODULE__.LocalSuccessfulTest ==
                   Map.fetch!(attributes, String.to_atom(root_attribute <> ".module_name"))

          assert :ok == Map.fetch!(attributes, String.to_atom(root_attribute <> ".state"))
          assert "" == Map.fetch!(attributes, String.to_atom(root_attribute <> ".state_reason"))

          assert :"test successful test" ==
                   Map.fetch!(attributes, String.to_atom(root_attribute <> ".test_name"))

        :failed ->
          assert __MODULE__.LocalFailedTest ==
                   Map.fetch!(attributes, String.to_atom(root_attribute <> ".module_name"))

          assert :failed == Map.fetch!(attributes, String.to_atom(root_attribute <> ".state"))

          assert :"test failed test" ==
                   Map.fetch!(attributes, String.to_atom(root_attribute <> ".test_name"))
      end
    end
  end

  setup do
    :ok = :otel_simple_processor.set_exporter(:test_processor, :otel_exporter_pid, self())
  end

  describe "successful with default settings" do
    test "sends valid opentelemetry span" do
      run_local_tests(:successful)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "ex_unit"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "code", :successful)
    end
  end

  describe "failed with default settings" do
    test "sends valid opentelemetry span" do
      run_local_tests(:failed)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "ex_unit"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "code", :failed)
    end
  end

  describe "successful with custom :root_attribute" do
    setup do
      :ok =
        Application.put_env(
          :opentelemetry_ex_unit_formatter,
          :root_attribute,
          "test_root_attribute"
        )

      :ok =
        on_exit(fn ->
          Application.delete_env(:opentelemetry_ex_unit_formatter, :root_attribute)
        end)
    end

    test "sends valid opentelemetry span" do
      run_local_tests(:successful)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "ex_unit"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "test_root_attribute", :successful)
    end
  end

  describe "failed with custom :root_attribute" do
    setup do
      :ok =
        Application.put_env(
          :opentelemetry_ex_unit_formatter,
          :root_attribute,
          "test_root_attribute"
        )

      :ok =
        on_exit(fn ->
          Application.delete_env(:opentelemetry_ex_unit_formatter, :root_attribute)
        end)
    end

    test "sends valid opentelemetry span" do
      run_local_tests(:failed)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "ex_unit"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "test_root_attribute", :failed)
    end
  end

  describe "successful with custom :span_name" do
    setup do
      :ok = Application.put_env(:opentelemetry_ex_unit_formatter, :span_name, "test_span")

      :ok =
        on_exit(fn ->
          Application.delete_env(:opentelemetry_ex_unit_formatter, :span_name)
        end)
    end

    test "sends valid opentelemetry span" do
      run_local_tests(:successful)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "test_span"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "code", :successful)
    end
  end

  describe "failed with custom :span_name" do
    setup do
      :ok = Application.put_env(:opentelemetry_ex_unit_formatter, :span_name, "test_span")

      :ok =
        on_exit(fn ->
          Application.delete_env(:opentelemetry_ex_unit_formatter, :span_name)
        end)
    end

    test "sends valid opentelemetry span" do
      run_local_tests(:failed)

      assert_receive {:span,
                      span(
                        name: name,
                        attributes: {:attributes, 128, :infinity, 0, attributes}
                      )}

      span_name = "test_span"
      assert name == "#{span_name}.test"
      assert_attributes(attributes, "code", :failed)
    end
  end

  defmodule LocalSuccessfulTest do
    use ExUnit.Case, register: false

    test "successful test" do
      assert true
    end
  end

  defmodule LocalFailedTest do
    use ExUnit.Case, register: false

    test "failed test" do
      assert false
    end
  end

  defp run_local_tests(kind) do
    :otel_tracer_provider.force_flush(:test_processor)
    Process.sleep(5)
    do_flush()
    ExUnit.configure(formatters: [OpentelemetryExUnitFormatter])

    result =
      case kind do
        :successful -> ExUnit.run([__MODULE__.LocalSuccessfulTest])
        :failed -> ExUnit.run([__MODULE__.LocalFailedTest])
      end

    IO.puts("Opentelemetry tests summary: #{inspect(result)}")

    :otel_tracer_provider.force_flush(:test_processor)
    Process.sleep(5)
    ExUnit.configure(formatters: [ExUnit.CLIFormatter])
  end

  defp do_flush() do
    receive do
      _msg ->
        do_flush()
    after
      0 -> :ok
    end
  end
end
