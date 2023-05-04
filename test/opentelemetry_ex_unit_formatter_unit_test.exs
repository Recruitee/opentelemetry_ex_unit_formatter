defmodule OpentelemetryExUnitFormatterUnitTest do
  use ExUnit.Case, async: true

  describe "init/1" do
    test "defaults" do
      assert {:ok,
              %{
                partition_no: "",
                register_after_suite?: false,
                root_attribute: "code",
                seed: nil,
                span_name: "ex_unit",
                tracer_provider: _tracer
              }} = OpentelemetryExUnitFormatter.init([])
    end

    test "seed is set" do
      assert {:ok,
              %{
                partition_no: "",
                register_after_suite?: false,
                root_attribute: "code",
                seed: 123_456,
                span_name: "ex_unit",
                tracer_provider: _tracer
              }} = OpentelemetryExUnitFormatter.init(seed: 123_456)
    end
  end

  describe "handle_cast/2" do
    test "tracer_provider is set to :noop" do
      assert {:noreply, %{tracer_provider: :none}} ==
               OpentelemetryExUnitFormatter.handle_cast(:event, %{tracer_provider: :none})
    end
  end
end
