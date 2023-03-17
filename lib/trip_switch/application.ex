defmodule TripSwitch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @otp_app :circuit

  @impl true
  def start(_type, _args) do
    Confex.resolve_env!(@otp_app)

    children = [
      {Registry, keys: :unique, name: TripSwitch.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: TripSwitch.DynamicSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TripSwitch.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
