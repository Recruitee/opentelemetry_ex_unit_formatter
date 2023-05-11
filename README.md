# OpentelemetryExUnitFormatter

<!-- MDOC !-->

[![Build](https://img.shields.io/github/actions/workflow/status/Recruitee/opentelemetry_ex_unit_formatter/ci.yml?style=for-the-badge)](https://github.com/Recruitee/opentelemetry_ex_unit_formatter/actions/workflows/ci.yml)
[![Hex Version](https://img.shields.io/hexpm/v/opentelemetry_ex_unit_formatter?style=for-the-badge)](https://hex.pm/packages/opentelemetry_ex_unit_formatter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-informational?style=for-the-badge)](https://hexdocs.pm/opentelemetry_ex_unit_formatter)

Opentelemetry instrumentation for `ExUnit.Formatter`.

Telemetry handler that creates Opentelemetry spans from `ExUnit.Formatter` events.

## Installation

Add `:opentelemetry_ex_unit_formatter` to your application dependencies list:

```elixir
# mix.exs
defp deps do
  [
    {
      :opentelemetry_ex_unit_formatter,
      "~> 0.1.0",
      github: "Recruitee/opentelemetry_ex_unit_formatter", only: :test, runtime: false
    }
  ]
end
```

## Usage

Add `OpentelemetryExUnitFormatter` to the `ExUnit` formatters list:

```elixir
# test/test_helper.exs
ExUnit.configure(formatters: [ExUnit.CLIFormatter, OpentelemetryExUnitFormatter])
ExUnit.start()
```

By default OpentelemetryExUnitFormatter has Opentelemetry tracer set to `:none` and telemetry spans
are not exported.
If you want to export telemetry spans, please add `:opentelemetry_exporter` to your application
dependencies list:

```elixir
# mix.exs
defp deps do
  [
    {
      :opentelemetry_ex_unit_formatter,
      "~> 0.1.0",
      github: "Recruitee/opentelemetry_ex_unit_formatter", only: :test, runtime: false
    },
    {:opentelemetry, "~> 1.2"},
    {:opentelemetry_exporter, "~> 1.4", only: :test, runtime: false}
  ]
end
```

Additionally you need to configure Opentelemetry tracer as described in the
[:tracer_provider_config](#tracer_provider_config) section below.

## Configuration

OpentelemetryExUnitFormatter configuration usually should be provided in the `config/test.exs` file.
Available configuration options are described below.

### `:before_send`

User provided single arity anonymous function executed before starting and sending a new telemetry
span.
Function should accept span attributes map as an argument and should return user modified span
attributes map.

**Default:** `nil`.

Example:

```elixir
# config/test.exs
config :opentelemetry_ex_unit_formatter,
  before_send: &MyApp.Test.Support.OpentelemetryExUnitFormatterHelper.before_send/1,

# test/support/opentelemetry_ex_unit_formatter_helper.ex
defmodule MyApp.Test.Support.OpentelemetryExUnitFormatterHelper do
  @attr_prefix "code.ci"
  @undefined "undefined"

  def before_send(attributes) do
    attributes
    |> Map.put(:"#{@attr_prefix}.ref_name", System.get_env("GITHUB_REF_NAME", @undefined))
    |> Map.put(:"#{@attr_prefix}.repository", System.get_env("GITHUB_REPOSITORY", @undefined))
  end
end
```

### `:register_after_suite?`

Opentelemetry processors might process telemetry spans asynchronously.
After entire testing suite is completed by `ExUnit`, some spans might still be buffered by
Opentelemetry processor and never exported.
If `:register_after_suite?` is set to `true` OpentelemetryExUnitFormatter will register a
callback function using `ExUnit.after_suite/1`. Registered callback function will use configuration
provided with `:tracer_provider_config` key to flush processor using its `:name` and then sleep for
the amount of time provided by `:bsp_scheduled_delay_ms` key (default 5000ms), waiting for a
processor to flush all pending spans.

In many cases built-in `after_suite` callback might not be sufficient or optimal and you should
consider registering your own callback depending on your Opentelemetry processor configuration.

**Default:** `false`.

### `:root_attribute`

Name of the root span attribute. By default it is set to the
[Source Code Attribute](https://opentelemetry.io/docs/reference/specification/trace/semantic_conventions/span-general/#source-code-attributes).

**Default:** `"code"`.

### `:span_name`

Name of the emitted spans (see: `:otel_tracer_default.with_span/5`).

**Default:** `"ex_unit"`.

### `:tracer_provider_config`

To emit telemetry spans OpentelemetryExUnitFormatter will run its own tracer provider, independent
of your application tracer defined in this case for the `:test` environment.

Example tracer provider configuration with `:otel_simple_processor` processor `:ex_unit_processor`
and `:opentelemetry_exporter` exporter:

```elixir
# config/test.exs
config :opentelemetry_ex_unit_formatter,
  tracer_provider_config: %{
    deny_list: [],
    id_generator: :otel_id_generator,
    sampler: {:otel_sampler_always_on, []},
    processors: [
      {
        :otel_simple_processor,
        %{
          bsp_scheduled_delay_ms: 1000,
          exporter: {:opentelemetry_exporter, %{}},
          name: :ex_unit_processor
        }
      }
    ]
  }
```

For large projects you might consider using `:otel_batch_processor`. When using batch processor, be
aware that spans are batched before being processed and it requires special attention as discussed
in the [`:register_after_suite?`](#register_after_suite) section.

For debugging purposes `:opentelemetry_exporter` can be set to `:otel_exporter_stdout`.

**Default:** `:none`.

<!-- MDOC !-->
