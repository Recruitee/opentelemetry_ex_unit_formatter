import Config

config :opentelemetry_ex_unit_formatter,
  tracer_provider_config: %{
    deny_list: [],
    id_generator: :otel_id_generator,
    sampler: {:otel_sampler_always_on, []},
    processors: [
      {
        :otel_simple_processor,
        %{
          bsp_scheduled_delay_ms: 1,
          exporter: :none,
          name: :test_processor
        }
      }
    ]
  }
