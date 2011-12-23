-module(genetic).
-author("Mateusz Lenik").
-import(lists, [keysort/2, split/2, map/2, reverse/1, sublist/3, sublist/2, foldl/3]).
-export([main/1, main/0, debug/4, read_best/1, read_instances/1]).

-define(INSTANCE_COUNT, 125).
-define(VARIABLE_COUNT, 3).

main() ->
  io:put_chars("Args: FILE BEST_FILE [BASE_SIZE [TIME_LEFT [MUTABILITY]]]\n"),
  erlang:halt(0).
main([File, BestFile]) -> main([File, BestFile, 50]);
main([File, BestFile, Base]) -> main([File, BestFile, Base, 1000]);
main([File, BestFile, Base, Time]) -> main([File, BestFile, Base, Time, 5]);
main([File, BestFile, BaseS, TimeS, MutabilityS]) ->
  random:seed(now()),
  Instances = lists:zip(read_best(BestFile), read_instances(File)),
  Base = parse_number(BaseS),
  Time = parse_number(TimeS),
  Mutability = parse_number(MutabilityS),
  lists:foreach(fun({Best,I}) -> new_world(I, Base, Time, Mutability, Best) end, Instances),
  erlang:halt(0).

% Function for performance testing
debug(FileName, Base, Time, Mutability) ->
  Instances = read_instances(FileName),
  new_world(hd(Instances), Base, Time, Mutability, 0).

% Creates new world and starts genetic algorithm
new_world(Instance, Base, Time, Mutability, Best) ->
  Population = spawn_population(Instance, Base),
  {BestSolution, TimeLeft} = evolve(Population, Time, Mutability, Best),
  io:format("Found result is ~p, optimal is ~p, ~p generations left.~n",
    [inverse_fitness(BestSolution), Best, TimeLeft]),
  Best.

% Function reading input files
read_instances(FileName) ->
  {ok, Bin} = file:read_file(FileName),
  parse_instances(Bin).

read_best(FileName) ->
  {ok, Bin} = file:read_file(FileName),
  parse_string(Bin).

% Function parses input data
parse_instances(Bin) ->
  Data = parse_string(Bin),
  InstanceSize = length(Data) div (?INSTANCE_COUNT * ?VARIABLE_COUNT),
  parse_instances(InstanceSize, Data, ?INSTANCE_COUNT, []).

parse_instances(_, _, 0, Acc) -> reverse(Acc);
parse_instances(InstanceSize, Data, N, Acc) ->
  {Instance, Rest} = split(?VARIABLE_COUNT*InstanceSize, Data),
  {Pj, Other} = split(InstanceSize, Instance),
  {Wj, Dj} = split(InstanceSize, Other),
  parse_instances(InstanceSize, Rest, N - 1, [lists:zip3(Pj,Wj,Dj)|Acc]).

% Parses binary string to list of integers
parse_string(Bin) when is_binary(Bin) -> parse_string(binary_to_list(Bin));
parse_string(Str) when is_list(Str) ->
  [list_to_integer(X) || X <- string:tokens(Str, "\r\n\t ")].

% Argument parsing function
parse_number(Int) when is_integer(Int) -> Int;
parse_number(Str) when is_list(Str) -> parse_number(list_to_integer(Str));
parse_number(Bin) when is_binary(Bin) -> parse_number(binary_to_list(Bin)).

% Computes the value of target function
% {TaskLen, TaskWeight, TaskDueDate}
inverse_fitness(Permutation) ->
  inverse_fitness(Permutation, 0, 0).
inverse_fitness([], _, Acc) -> Acc;
inverse_fitness([{Pj, Wj, Dj}|Rest], Time, Acc) ->
  inverse_fitness(Rest, Time + Pj, Wj*max(0, Time + Pj - Dj) + Acc).

% Sorts the list by inverse_fitness
sort_by_fitness(Population) ->
  Sorted = keysort(2, [{X, inverse_fitness(X)} || X <- Population]),
  [X || {X,_} <- Sorted].

% Mutation procedure
% Implemented using sequence swap
mutate(Permutation, P) ->
  case probability(P) of
    true  -> mutate(Permutation);
    false -> Permutation
  end.

mutate(Permutation) ->
  S1 = random:uniform(length(Permutation)),
  S2 = random:uniform(length(Permutation)),
  case S1 > S2 of
    true  -> mutate(Permutation, S2, S1);
    false -> mutate(Permutation, S1, S2)
  end.

mutate(Permutation, S1, S2) ->
  {Head, Tail} = split(S1, Permutation),
  {Middle, End} = split(S2 - S1, Tail),
  Head ++ reverse(Middle) ++ End.

% Breeding algorithm
% Implemented using PMX crossover
breed(Parents = {P1, P2}, ProbabilityOfMutation) ->
  S1 = random:uniform(length(P1)),
  S2 = random:uniform(length(P2)),
  case S1 > S2 of
    true  -> breed(Parents, S2, S1, ProbabilityOfMutation);
    false -> breed(Parents, S1, S2, ProbabilityOfMutation)
  end.

breed(Parents = {P1, P2}, S1, S2, P) ->
  V = breed_vector(Parents, S1, S2),
  C1 = map(fun(X) -> foldl(fun breed_swap/2, X, V) end, P1),
  C2 = map(fun(X) -> foldl(fun breed_swap/2, X, V) end, P2),
  {mutate(C1, P), mutate(C2, P)}.

% Gene swapping function used in PMX crossover
breed_swap({Gene, NewGene}, Gene) -> NewGene;
breed_swap({Gene, NewGene}, NewGene) -> Gene;
breed_swap({_, _}, Gene) -> Gene.

% Computes swapping vector for breeding
breed_vector({Parent1, Parent2}, S1, S2) ->
  L1 = sublist(Parent1, S1, S2 - S1),
  L2 = sublist(Parent2, S1, S2 - S1),
  lists:zip(L1, L2).

% Function returning true with probability of 1/2^N
probability(0) -> true;
probability(N) when N >= 1 ->
  R1 = random:uniform(),
  R2 = random:uniform(),
  case R1 =< R2 of
    true  -> probability(N - 1);
    false -> false
  end.

% Function generating base population
spawn_population(Tasks, N) -> spawn_population(Tasks, N, []).
spawn_population(_, 0, Acc) -> Acc;
spawn_population(Tasks, N, Acc) ->
  Permutation = keysort(2, [{X, random:uniform()} || X <- Tasks]),
  New = [X || {X,_} <- Permutation],
  spawn_population(Tasks, N - 1, [New|Acc]).

% Genetic algorithm itself
evolve(Population, TimeLeft, Pmutation, Best) ->
  Sorted = sort_by_fitness(Population),
  evolve(Sorted, TimeLeft, Pmutation, hd(Sorted), Best).

evolve(_, 0, _, BestSolution, _) -> {BestSolution, 0};
evolve(Population, TimeLeft, Pmutation, _, Best) ->
  Length = length(Population) div 3,
  {Good, Bad} = split(Length, Population),
  NewGood = reproduce(Good, Pmutation),
  Sorted = sort_by_fitness(NewGood ++ Good ++ sublist(Bad, Length)),
  BestSolution = hd(Sorted),
  case inverse_fitness(BestSolution) =< Best of
    false -> evolve(Sorted, TimeLeft - 1, Pmutation, BestSolution, Best);
    true  -> {BestSolution, TimeLeft}
  end.


% Function defining reproduction cycle
reproduce(Generation, P) -> reproduce(Generation, [], P).
reproduce([], NewGeneration, _) -> NewGeneration;
reproduce([P1, P2|Rest], NewGeneration, P) ->
  {C1, C2} = breed({P1, P2}, P),
  reproduce(Rest, [C1, C2|NewGeneration], P);
reproduce([Last], NewGeneration, P) ->
  reproduce([], [Last|NewGeneration], P).

