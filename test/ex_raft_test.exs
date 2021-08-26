defmodule ExRaftTest do
  use ExUnit.Case, async: true
  doctest ExRaft

  @rtmo 100
  @wtmo 1_000
  @ltmo 16
  @etmo 10_000

  defmacrop setup_mocks(state_machine) do
    quote bind_quoted: [state_machine: state_machine] do
      :meck.new(state_machine, [:non_strict])

      :meck.expect(state_machine, :init, fn _ ->
        Process.flag(:trap_exit, true)
        {:ok, %{}}
      end)

      :meck.expect(state_machine, :transition, fn _, _ -> :ok end)
      :meck.expect(state_machine, :command?, fn command, _ -> match?({:put, _, _}, command) end)

      :meck.expect(state_machine, :handle_read, fn key, state -> {:reply, Map.get(state, key)} end)

      :meck.expect(state_machine, :handle_system_write, fn _, _, state -> {:ok, state} end)

      :meck.expect(state_machine, :handle_write, fn {:put, key, value}, state ->
        {:ok, Map.put(state, key, value), [{:mfa, {state_machine, :handle_side_effect, []}}]}
      end)

      :meck.expect(state_machine, :handle_side_effect, fn -> :ok end)
      :meck.expect(state_machine, :terminate, fn _, _ -> :ok end)
    end
  end

  test "single server" do
    {state_machine, _} = __ENV__.function
    setup_mocks(state_machine)

    {:ok, _} = start_server(state_machine, name: state_machine)
    assert :meck.num_calls(state_machine, :init, :_) === 1
    assert ExRaft.await_leader(state_machine, @etmo) === {state_machine, node()}
    assert ExRaft.trigger_election(state_machine, @wtmo) === :ok
    assert ExRaft.await_leader(state_machine, @etmo) === {state_machine, node()}
    assert :meck.num_calls(state_machine, :transition, :_) === 3

    assert ExRaft.read(state_machine, :foo, @rtmo) === nil
    assert ExRaft.read_dirty(state_machine, :foo, @rtmo) === nil
    assert :meck.num_calls(state_machine, :handle_read, :_) === 2

    exit_reason = catch_exit(ExRaft.write(state_machine, :foo, @wtmo))
    assert match?({:timeout, {:gen_statem, :call, _}}, exit_reason)
    assert :meck.num_calls(state_machine, :command?, :_) === 1

    assert ExRaft.write(state_machine, {:put, :foo, :bar}, @wtmo) === :ok
    assert :meck.num_calls(state_machine, :command?, :_) === 2
    assert :meck.num_calls(state_machine, :handle_write, :_) === 1
    assert :meck.num_calls(state_machine, :handle_side_effect, :_) === 1

    assert ExRaft.read(state_machine, :foo, @rtmo) === :bar
    assert :meck.num_calls(state_machine, :handle_read, :_) === 3

    assert ExRaft.stop_server(state_machine) === :ok
    assert :meck.num_calls(state_machine, :terminate, :_) === 1

    :meck.unload(state_machine)
  end

  test "static config" do
    {state_machine, _} = __ENV__.function
    setup_mocks(state_machine)

    config = Enum.map(1..3, &{:"#{state_machine}#{&1}", node()})
    [init_leader | init_followers] = config
    [rand_init_follower | _] = init_followers

    Enum.with_index(config)
    |> Enum.each(fn {{name, _}, index} ->
      {:ok, _} =
        if index === 0,
          do: start_server(state_machine, name: name, initial_config: config),
          else: start_server(state_machine, name: name, min_majority: 2)
    end)

    assert ExRaft.trigger_election(init_leader, @wtmo) === :ok
    assert ExRaft.await_leader(rand_init_follower, @etmo) === init_leader
    assert ExRaft.read(rand_init_follower, :foo, @ltmo) === {:error, {:redirect, init_leader}}
    assert ExRaft.write(rand_init_follower, :foo, @ltmo) === {:error, {:redirect, init_leader}}

    exit_reason = catch_exit(ExRaft.write(init_leader, :foo, @wtmo))
    assert match?({:timeout, {:gen_statem, :call, _}}, exit_reason)
    assert ExRaft.write(init_leader, {:put, :foo, :bar}, @wtmo) === :ok
    assert ExRaft.read(init_leader, :foo, @rtmo) === :bar

    # sleep for a sec to catch up followers
    Process.sleep(1_000)
    assert ExRaft.read_dirty(rand_init_follower, :foo, @rtmo) === :bar

    ExRaft.stop_server(init_leader)
    Process.sleep(@etmo)
    new_leader = ExRaft.await_leader(rand_init_follower, @etmo)
    assert Enum.member?(init_followers, new_leader)
    [follower] = List.delete(init_followers, new_leader)

    assert ExRaft.read(new_leader, :foo, @rtmo) === :bar
    assert ExRaft.write(new_leader, {:put, :foo, :baz}, @wtmo) === :ok

    # sleep for a sec to catch up followers
    Process.sleep(1_000)
    assert ExRaft.read_dirty(follower, :foo, @rtmo) === :baz

    Enum.each(init_followers, &ExRaft.stop_server/1)

    :meck.unload(state_machine)
  end

  test "dynamic config" do
    {state_machine, _} = __ENV__.function
    setup_mocks(state_machine)

    config =
      [:init_leader, :init_follower_one, :init_follower_two]
      |> Enum.map(&{:"#{&1}.#{state_machine}", node()})

    [init_leader | init_followers] = config
    [init_follower_one, init_follower_two] = init_followers

    Enum.with_index(config)
    |> Enum.each(fn {{name, _}, index} ->
      {:ok, _} =
        if index === 0,
          do: start_server(state_machine, name: name),
          else: start_server(state_machine, name: name, min_majority: 2)
    end)

    # unchanged config should return quickly
    assert ExRaft.add_server(init_leader, init_leader, @ltmo) === :ok
    assert ExRaft.remove_server(init_leader, {Enum, :member?}, @ltmo) === :ok
    assert ExRaft.remove_server(init_leader, init_leader, @ltmo) === {:error, :last_server}

    assert ExRaft.add_server(init_leader, init_follower_one, @wtmo) === :ok
    assert ExRaft.add_server(init_leader, init_follower_two, @wtmo) === :ok

    # unchanged config should return quickly
    assert ExRaft.add_server(init_leader, init_leader, @ltmo) === :ok
    assert ExRaft.remove_server(init_leader, {Enum, :member?}, @ltmo) === :ok

    assert ExRaft.remove_server(init_leader, init_leader, @wtmo) === :ok
    # sleep for a sec to wait for election
    Process.sleep(1_000)
    new_leader = ExRaft.await_leader(init_follower_one, @etmo)
    assert new_leader === init_follower_one
    Enum.each(config, &ExRaft.stop_server/1)

    :meck.unload(state_machine)
  end

  defp start_server(state_machine, options),
    do: ExRaft.start_server(state_machine, [{:debug, true} | options])
end
