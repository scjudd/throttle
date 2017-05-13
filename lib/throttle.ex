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

  defp reverse_pop(stack) do
    [first | remaining] = Enum.reverse(stack)
    {first, Enum.reverse(remaining)}
  end

  defp reverse_split(stack, n) do
    {first_n, remaining} = stack |> Enum.reverse() |> Enum.split(n)
    {first_n, Enum.reverse(remaining)}
  end

  @doc false
  def init(state) do
    {:ok, state}
  end

  @doc false
  def handle_call({:call, fun}, from, {:ready, interval, n}) do
    async_apply({from, fun})
    Process.send_after(self(), :resume, interval)
    {:noreply, {:triggered, {interval, 1, n}, []}}
  end

  @doc false
  def handle_call({:call, fun}, from, {:triggered, {interval, n, max}, stack}) when n < max do
    {first, remaining} = reverse_pop([{from, fun} | stack])
    async_apply(first)
    {:noreply, {:triggered, {interval, n + 1, max}, remaining}}
  end

  @doc false
  def handle_call({:call, fun}, from, {:triggered, {interval, n, max}, stack}) do
    {:noreply, {:triggered, {interval, n, max}, [{from, fun} | stack]}}
  end

  @doc false
  def handle_info(:resume, {:triggered, {interval, _n, max}, []}) do
    {:noreply, {:ready, interval, max}}
  end

  @doc false
  def handle_info(:resume, {:triggered, {interval, _n, max}, stack}) do
    {funs, remaining} = reverse_split(stack, max)
    Enum.each(funs, &async_apply/1)
    Process.send_after(self(), :resume, interval)
    {:noreply, {:triggered, {interval, length(funs), max}, remaining}}
  end
end
