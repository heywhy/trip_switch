# TripSwitch

A circuit breaker implementation for Elixir, with ability to self-heal if needed.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `trip_switch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trip_switch, "~> 0.1.3"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/trip_switch>.

## Release

An alias/command is included to make a new release of the package.

```bash
# include --initial for first release and without for subsequent releases
mix ops.release
```
