defmodule Circuit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @otp_app :circuit

  @impl true
  def start(_type, _args) do
    Confex.resolve_env!(@otp_app)

    children = [
      # Starts a worker by calling: Circuit.Worker.start_link(arg)
      # {Circuit.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Circuit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
