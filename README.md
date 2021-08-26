# ExRaft

![Build Status](https://github.com/bajankristof/ex_raft/actions/workflows/main.yml/badge.svg?branch=main)

An Elixir implementation of the raft consensus protocol.

This library takes an in-memory approach for storing log entries
and the state machine state, therefore it is not really suitable
for storing large amounts of data. Since it's in-memory only though,
it's supposed to be fast.

To get started, check out the
[`ExRaft.StateMachine` documentation](https://hexdocs.pm/ex_raft/ExRaft.StateMachine.html).

To understand the internals of the project, check out the
[main `ExRaft` module documentation](https://hexdocs.pm/ex_raft/ExRaft.html).

For a full overview of the project, check out the full
[online documentation](https://hexdocs.pm/ex_raft).

## Installation

The package can be installed by adding `ex_raft` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_raft, "~> 0.2.0"}
  ]
end
```


## Example

```elixir
init_arg = [very_cool: true]
initial_config = [raft1: node(), raft2: node()]

# after starting these servers, they will time out and eventually elect a leader
# amongst themselves
{:ok, _} = ExRaft.start_server(YourStateMachine, init_arg, name: :raft1, initial_config: initial_config)
{:ok, _} = ExRaft.start_server(YourStateMachine, init_arg, name: :raft2, initial_config: initial_config)

# this server can never become leader unless its added to an existing cluster
# since it doesn't know of any other server but is required to achieve
# a minimum majority of 2 in elections and log replication
{:ok, _} = ExRaft.start_server(YourStateMachine, init_arg, name: :raft3, min_majority: 2)

# we could pick any server to await the leader
leader = ExRaft.await_leader(:raft1)
:ok = ExRaft.add_server(leader, :raft3)

# the success result of write/3 depends on the state machine
:ok = ExRaft.write(leader, :hello)

# making a write/3 call to a follower results in an error
follower = List.delete(initial_config, leader) |> List.first()
{:error, {:redirect, ^leader}} = ExRaft.write(follower, :hello)

# if we stop the active leader (or it crashes)
# the rest of the cluster will be able to recover
:ok = ExRaft.stop_server(leader)
:ok = ExRaft.trigger_election(:raft3)
new_leader = ExRaft.await_leader(:raft3)
true = Enum.member?([raft2: node(), raft3: node()], new_leader)
```

## Contributing

All contributions must adhere to the guidelines below:

  * https://github.com/christopheradams/elixir_style_guide
  * https://github.com/christopheradams/elixir_style_guide#modules
  * https://hexdocs.pm/elixir/master/library-guidelines.html
  * https://hexdocs.pm/elixir/master/writing-documentation.html

## License

`ExRaft` source code is released under Apache License 2.0.
Check LICENSE file for more information.
