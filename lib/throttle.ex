defmodule Throttle do
  @moduledoc """
  Throttle function calls

  A Throttle process allows you to limit how many times a function may be
  called in a given interval. This is especially useful when building API
  clients for rate-limited services.
  """

  use GenServer

  def start_link(interval, n \\ 1) do
    GenServer.start_link(__MODULE__, {:ready, interval, n})
  end

  @doc """
  Call `fun/0` as soon as possible
  """
  def call(pid, fun, timeout \\ 5_000) do
    GenServer.call(pid, {:call, fun}, timeout)
  end

  defp async_apply({pid, fun}) do
    GenServer.reply(pid, fun.())
  end

  @doc false
  def init(state) do
    {:ok, state}
  end

  @doc false
  def handle_call({:call, fun}, from, {:ready, interval, n}) do
    async_apply({from, fun})
    Process.send_after(self(), :resume, interval)
    {:noreply, {:triggered, {interval, 1, n}, :queue.new()}}
  end

  @doc false
  def handle_call({:call, fun}, from, {:triggered, {interval, n, max}, queue}) when n < max do
    {{:value, first}, remaining} = {from, fun} |> :queue.in(queue) |> :queue.out()
    async_apply(first)
    {:noreply, {:triggered, {interval, n + 1, max}, remaining}}
  end

  @doc false
  def handle_call({:call, fun}, from, {:triggered, {interval, n, max}, queue}) do
    {:noreply, {:triggered, {interval, n, max}, :queue.in({from, fun}, queue)}}
  end

  @doc false
  def handle_info(:resume, {:triggered, {interval, _n, max}, queue}) do
    case :queue.is_empty(queue) do
      true ->
        {:noreply, {:ready, interval, max}}
      false ->
        n = min(:queue.len(queue), max)
        {funs, remaining} = :queue.split(n, queue)
        Enum.each(:queue.to_list(funs), &async_apply/1)
        Process.send_after(self(), :resume, interval)
        {:noreply, {:triggered, {interval, n, max}, remaining}}
    end
  end
end
