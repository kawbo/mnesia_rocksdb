%% -*- mode: erlang; erlang-indent-level: 4; indent-tabs-mode: nil -*-
-module(mnesia_rocksdb_SUITE).

-export([
         all/0
        , groups/0
        , suite/0
        , init_per_suite/1
        , end_per_suite/1
        , init_per_group/2
        , end_per_group/2
        , init_per_testcase/2
        , end_per_testcase/2
                , admin_db_opens_with_default_rocksdb_opts/1
        , direct_access_column_family_table/1
        , column_families_share_one_block_cache/1
]).

-export([ log/2 ]).
-export([ alias_overriding_one_table_option_keeps_the_shared_cache/1
        , alias_indexes_inherit_only_their_tables_bounding_options/1
        , cleared_index_takes_its_tables_current_options/1
        , fifo_check_follows_mrdb_legacy_standalone/1
        , failed_create_leaves_no_instance_directory/1
        , standalone_fifo_table_with_index_opens_and_reopens/1
        , fifo_check_judges_the_options_its_instance_runs_with/1
        , malformed_rocksdb_opts_are_refused_cleanly/1
        , failed_create_keeps_a_path_it_did_not_create/1
        , admin_write_table_property_reaches_the_schema_and_the_table/1
        , admin_write_table_property_does_not_wait_on_its_callers_schema_lock/1
        , fifo_instance_rule_is_judged_where_the_table_lives/1
        , fifo_instance_rule_is_judged_on_every_node_holding_the_table/1
        , holders_are_asked_about_their_instances_at_once/1
        , malformed_options_in_the_schema_reopen_with_defaults/1
        , standalone_table_follows_its_written_properties/1
        , removed_alias_leaves_no_table_refs_behind/1
        , compaction_options_of_an_instance_are_reported_as_unused/1
        , fifo_data_size_cap_counts_as_a_size_cap/1
        , removed_alias_leaves_no_ref_behind/1
        , admin_write_table_property_refuses_tables_outside_its_alias/1
        , column_family_left_by_a_table_of_another_alias_reopens_with_defaults/1
        , alias_db_refuses_to_open_with_a_fifo_table_its_instance_cannot_hold/1
        , fifo_index_rule_refusal_points_to_the_escape_hatch_and_warn_starts_anyway/1
        , alias_indexes_keep_their_tables_options/1
        , alias_retainers_keep_default_options/1
        , alias_table_switched_to_fifo_reopens_with_its_data/1
        , alias_fifo_options_never_reach_the_admin_column_families/1
        , fifo_needs_max_open_files_unlimited_in_its_instance/1
        , fifo_table_with_index_needs_a_ttl_and_no_size_cap/1
        , index_added_later_to_capped_fifo_table_is_refused/1
        , capped_fifo_options_written_later_onto_indexed_table_are_refused/1
        , alias_options_win_also_where_they_are_rewritten/1
        , alias_db_that_cannot_reopen_names_the_cause/1
        , alias_db_refuses_to_open_with_an_indexed_table_breaking_the_fifo_rules/1
        , alias_db_opens_with_alias_rocksdb_opts/1
        , alias_tables_live_in_alias_db/1
        , fifo_options_apply_per_column_family/1
        , alias_tables_reopen_with_their_options/1
        , delete_alias_table/1
        ]).

-export([ encoding_sext_attrs/1
        , encoding_binary_binary/1
        , encoding_defaults/1
        ]).
-export([ mrdb_batch/1
        , mrdb_transactions/1
	, mrdb_abort_reasons/1
        , mrdb_repeated_transactions/1
        , mrdb_abort/1
        , mrdb_two_procs/1
        , mrdb_two_procs_tx_restart/1
        , mrdb_two_procs_tx_inner_restart/1
        , mrdb_two_procs_snap/1
        , mrdb_three_procs/1
        , create_counters/1
        , update_counters/1
        , restart_node/1
        ]).

-include_lib("common_test/include/ct.hrl").

-define(TABS_CREATED, tables_created).

%% A second alias, configured to get a RocksDB instance of its own (see the
%% alias_instances group).
-define(TRAFFIC, rdb_traffic).
-define(SMALL_FIFO, 262144).
-define(LARGE_FIFO, 67108864).
-define(UNLIMITED, 18446744073709551615).
-define(FIFO_ROUNDS, 8).
-define(FIFO_ROUND_SIZE, 100).

suite() ->
    [].

all() ->
    [{group, all_tests}].

groups() ->
    [
      {all_tests, [sequence], [ {group, checks}
                              , {group, mrdb}
                              , {group, counters}
                              , {group, options}
                              , {group, alias_instances}]}
    , {options, [sequence], [ admin_db_opens_with_default_rocksdb_opts
                            , direct_access_column_family_table
                            , column_families_share_one_block_cache ]}
    , {alias_instances, [sequence], [ alias_db_opens_with_alias_rocksdb_opts
                                    , alias_tables_live_in_alias_db
                                    , fifo_options_apply_per_column_family
                                    , restart_node
                                    , alias_db_opens_with_alias_rocksdb_opts
                                    , alias_tables_reopen_with_their_options
                                    , delete_alias_table
                                    , alias_indexes_keep_their_tables_options
                                    , alias_retainers_keep_default_options
                                    , alias_table_switched_to_fifo_reopens_with_its_data
                                    , alias_fifo_options_never_reach_the_admin_column_families
                                    , fifo_needs_max_open_files_unlimited_in_its_instance
                                    , fifo_table_with_index_needs_a_ttl_and_no_size_cap
                                    , index_added_later_to_capped_fifo_table_is_refused
                                    , capped_fifo_options_written_later_onto_indexed_table_are_refused
                                    , alias_options_win_also_where_they_are_rewritten
                                    , alias_overriding_one_table_option_keeps_the_shared_cache
                                    , alias_db_that_cannot_reopen_names_the_cause
                                    , alias_db_refuses_to_open_with_a_fifo_table_its_instance_cannot_hold
                                    , alias_indexes_inherit_only_their_tables_bounding_options
                                    , cleared_index_takes_its_tables_current_options
                                    , fifo_check_follows_mrdb_legacy_standalone
                                    , failed_create_leaves_no_instance_directory
                                    , standalone_fifo_table_with_index_opens_and_reopens
                                    , fifo_check_judges_the_options_its_instance_runs_with
                                    , malformed_rocksdb_opts_are_refused_cleanly
                                    , failed_create_keeps_a_path_it_did_not_create
                                    , admin_write_table_property_reaches_the_schema_and_the_table
                                    , admin_write_table_property_does_not_wait_on_its_callers_schema_lock
                                    , fifo_instance_rule_is_judged_where_the_table_lives
                                    , fifo_instance_rule_is_judged_on_every_node_holding_the_table
                                    , holders_are_asked_about_their_instances_at_once
                                    , malformed_options_in_the_schema_reopen_with_defaults
                                    , standalone_table_follows_its_written_properties
                                    , compaction_options_of_an_instance_are_reported_as_unused
                                    , fifo_data_size_cap_counts_as_a_size_cap
                                    , removed_alias_leaves_no_ref_behind
                                    , admin_write_table_property_refuses_tables_outside_its_alias
                                    , column_family_left_by_a_table_of_another_alias_reopens_with_defaults
                                    , fifo_index_rule_refusal_points_to_the_escape_hatch_and_warn_starts_anyway
                                    , alias_db_refuses_to_open_with_an_indexed_table_breaking_the_fifo_rules
                                    , removed_alias_leaves_no_table_refs_behind ]}
                              %% , error_handling ]}
    , {checks, [sequence], [ encoding_sext_attrs
                           , encoding_binary_binary
                           , encoding_defaults ]}
    , {mrdb, [sequence], [ mrdb_batch
                         , mrdb_transactions
			 , mrdb_abort_reasons
                         , mrdb_repeated_transactions
                         , mrdb_abort
                         , mrdb_two_procs
                         , mrdb_two_procs_tx_restart
                         , mrdb_two_procs_tx_inner_restart
                         , mrdb_two_procs_snap
                         , mrdb_three_procs ]}
    , {counters, [sequence], [ create_counters
                             , update_counters
                             , restart_node
                             , update_counters ]}
    ].


%% error_handling(Config) ->
%%     mnesia_rocksdb_error_handling:run(Config).

init_per_suite(Config) ->
    tr_ct:set_activation_checkpoint(?TABS_CREATED, Config).

end_per_suite(_Config) ->
    ok.

init_per_group(G, Config) when G==mrdb
                             ; G==checks ->
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset),
    Config;

init_per_group(options, Config) ->
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, [{max_open_files, 123}]),
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset),
    Config;
init_per_group(alias_instances, Config) ->
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, [{max_open_files, 123}]),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts,
                             [{?TRAFFIC, [{max_open_files, -1}]}]),
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset),
    {ok, ?TRAFFIC} = mnesia_rocksdb:register(?TRAFFIC),
    Config;
init_per_group(_, Config) ->
    Config.

end_per_group(options, _Config) ->
    ok = application:unset_env(mnesia_rocksdb, default_rocksdb_opts);
end_per_group(alias_instances, _Config) ->
    ok = application:unset_env(mnesia_rocksdb, default_rocksdb_opts),
    ok = application:unset_env(mnesia_rocksdb, alias_rocksdb_opts),
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset);
end_per_group(_, _Config) ->
    ok.

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, _Config) ->
    ok.

encoding_sext_attrs(Config) ->
    tr_ct:with_trace(fun encoding_sext_attrs_/1, Config,
                     tr_patterns(mnesia_rocksdb,
                                 [{mnesia_rocksdb,'_',x}], tr_opts())).

encoding_sext_attrs_(Config) ->
    Created = create_tabs([{t, [{attributes, [k, v]}]}], Config),
    ok = mrdb:insert(t, {t, 1, a}),
    ok = mnesia:dirty_write({t, 2, b}),
    expect_error(fun() -> mrdb:insert(t, {t, a}) end, ?LINE,
                 error, {mrdb_abort, badarg}),
    expect_error(fun() -> mnesia:dirty_write({t, a}) end, ?LINE,
                 exit, '_'),
    delete_tabs(Created),
    ok.

encoding_defaults(Config) ->
    UP = fun(T) -> mnesia:table_info(T, user_properties) end,
    Created = create_tabs([ {a, [ {attributes, [k, v]}
                                , {type, set}]}
                          , {b, [ {attributes, [k, v, w]}
                                , {type, ordered_set}]}
                          , {c, [ {attributes, [k, v]}
                                , {type, bag} ]}], Config),
    [{mrdb_encoding,{term,{value,term}}}]  = UP(a),
    [{mrdb_encoding,{sext,{object,term}}}] = UP(b),
    [{mrdb_encoding,{sext,{value,term}}}]  = UP(c),
    delete_tabs(Created),
    ok.

encoding_binary_binary(Config) ->
    Created = create_tabs([ {a, [ {attributes, [k,v]}
                                  , {user_properties,
                                     [{mrdb_encoding, {raw, raw}}]}]}
                          , {b, [ {attributes, [k, v, w]}
                                , {user_properties,
                                   [{mrdb_encoding, {raw, {object, term}}}]}]}
                          ], Config),
    expect_error(fun() ->
                         create_tab(
                           c, [ {attributes, [k, v, w]}
                              , {user_properties,
                                 [{mrdb_encoding, {raw, {value, raw}}}]}])
                 end, ?LINE, error, '_'),
    delete_tabs(Created),
    ok.

expect_error(F, Line, Type, Expected) ->
    try F() of
        Unexpected -> error({unexpected, Line, Unexpected})
    catch
        Type:Expected ->
            ct:log("Caught expected ~p:~p (Line: ~p)", [Type, Expected, Line]),
            ok;
        Type:Error when Expected == '_' ->
            ct:log("Caught expected ~p:_ (Line:~p): ~p", [Type, Line, Error]),
            ok
    end.

mrdb_batch(Config) ->
    Created = create_tabs([{b, []}], Config),
    D0 = get_dict(),
    mrdb:activity(
      batch, rdb,
      fun() ->
              [mrdb:insert(b, {b, K, K})
               || K <- lists:seq(1, 10)]
      end),
    dictionary_unchanged(D0),
    [[{b,K,K}] = mrdb:read(b, K) || K <- lists:seq(1, 10)],
    expect_error(
      fun() -> mrdb:activity(
                 batch, rdb,
                 fun() ->
                         mrdb:insert(b, {b, 11, 11}),
                         error(willful_abort)
                 end)
      end, ?LINE, error, '_'),
    dictionary_unchanged(D0),
    [] = mrdb:read(b, 11),
    TRef = mrdb:get_ref(b),
    mrdb:activity(
      batch, rdb,
      fun() ->
              mrdb:insert(TRef, {b, 12, 12})
      end),
    dictionary_unchanged(D0),
    [{b, 12, 12}] = mrdb:read(b, 12),
    mrdb:as_batch(b, fun(R) ->
                             mrdb:insert(R, {b, 13, 13})
                     end),
    dictionary_unchanged(D0),
    [{b, 13, 13}] = mrdb:read(b, 13),
    delete_tabs(Created),
    ok.

mrdb_transactions(Config) ->
    tr_ct:with_trace(fun mrdb_transactions_/1, Config,
                     tr_patterns(
                       mnesia_rocksdb_admin,
                       [{mnesia_rocksdb_admin,'_',x}], tr_opts())).

mrdb_transactions_(Config) ->
    Created = create_tabs([{tx, []}], Config),
    mrdb:insert(tx, {tx, a, 1}),
    [_] = mrdb:read(tx, a),
    D0 = get_dict(),
    mrdb:activity(
      tx, rdb,
      fun() ->
              [{tx,a,N}] = mrdb:read(tx, a),
              N1 = N+1,
              ok = mrdb:insert(tx, {tx,a,N1}),
              [{tx,a,N1}] = mrdb:read(tx, a),
              ok
      end),
    dictionary_unchanged(D0),
    [{tx,a,2}] = mrdb:read(tx,a),
    delete_tabs(Created),
    ok.

-dialyzer(no_return).
mrdb_abort_reasons(_Config) ->
    Prev = mnesia_rocksdb_admin:set_and_cache_env(mnesia_compatible_aborts, true),
    X = some_value,
    compare_txs('throw', fun() -> throw(X) end),
    compare_txs('exit' , fun() -> exit(X) end),
    compare_txs('error', fun() -> error(X) end),
    compare_txs('abort', fun() -> mnesia:abort(X) end),
    compare_txs('abort' , fun() -> mrdb:abort(X) end),
    mnesia_rocksdb_admin:set_and_cache_env(mnesia_compatible_aborts, Prev),
    ok.

compare_txs(Type, F) ->
    {caught, exit, {aborted, EMn}} = mnesia_tx(F),
    {caught, exit, {aborted, EMr}} = mrdb_tx(F),
    ct:log("Mnesia = ~p/~p", [Type, EMn]),
    ct:log("Mrdb   = ~p/~p", [Type, EMr]),
    case {Type, EMn, EMr} of
	{error, {some_value, [_|_]}, {some_value, []}} -> ok;
	{throw, {throw, some_value}, {throw, some_value}} -> ok;
	{exit, some_value, some_value} -> ok;
	{abort, some_value, some_value} -> ok
    end.

mnesia_tx(F) ->
    try
	mnesia:activity(transaction, F)
    catch
	C:E ->
	    {caught, C, E}
    end.

mrdb_tx(F) ->
    try
	mrdb:activity(transaction, rdb, F)
    catch
	C:E ->
	    {caught, C, E}
    end.

mrdb_repeated_transactions(Config) ->
    Created = create_tabs([{rtx, []}], Config),
    mrdb:insert(rtx, {rtx, a, 0}),
    [_] = mrdb:read(rtx, a),
    Fun = fun() ->
                  [{rtx, a, N}] = mrdb:read(rtx, a),
                  N1 = N+1,
                  ok = mrdb:insert(rtx, {rtx, a, N1})
          end,
    D0 = get_dict(),
    [ok = mrdb:activity(tx, rdb, Fun) || _ <- lists:seq(1,100)],
    dictionary_unchanged(D0),
    [{rtx,a,100}] = mrdb:read(rtx, a),
    delete_tabs(Created),
    ok.

mrdb_abort(Config) ->
    Created = create_tabs([{tx_abort, []}], Config),
    mrdb:insert(tx_abort, {tx_abort, a, 1}),
    Pre = mrdb:read(tx_abort, a),
    D0 = get_dict(),
    TRes = try mrdb:activity(
                 {tx, #{mnesia_compatible => true}}, rdb,
                 fun() ->
                         [{tx_abort, a, N}] = mrdb:read(tx_abort, a),
                         error(abort_here),
                         ok = mrdb:insert(tx_abort, [{tx_abort, a, N+1}]),
                         noooo
                 end)
           catch
               error:abort_here ->
                   ok
           end,
    dictionary_unchanged(D0),
    ok = TRes,
    Pre = mrdb:read(tx_abort, a),
    delete_tabs(Created),
    ok.

mrdb_two_procs(Config) ->
    tr_ct:with_trace(fun mrdb_two_procs_/1, Config,
                     tr_flags(
                       {self(), [call, sos, p, 'receive']},
                       tr_patterns(
                         mrdb, [ {mrdb, insert, 2, x}
                               , {mrdb, read, 2, x}
                               , {mrdb, retry_activity, 3, x}
                               , {mrdb, try_f, 2, x}
                               , {mrdb, incr_attempt, 2, x}
                               , {mrdb_mutex, do, 2, x}
                               , {mrdb_mutex_serializer, do, 2, x}
                               , {?MODULE, wait_for_other, 2, x}
                               , {?MODULE, go_ahead_other, 1, x}
                               , {mrdb, activity, x}], tr_opts()))).

mrdb_two_procs_(Config) ->
    R = ?FUNCTION_NAME,
    Parent = self(),
    Created = create_tabs([{R, []}], Config),
    mrdb:insert(R, {R, a, 1}),
    Pre = mrdb:read(R, a),
    F0 = fun() ->
                 wait_for_other(Parent, ?LINE),
                 ok = mrdb:insert(R, {R, a, 17}),
                 wait_for_other(Parent, ?LINE)
         end,
    {POther, MRef} = spawn_opt(
                       fun() ->
                               D0 = get_dict(),
                               ok = mrdb:activity(tx, rdb, F0),
                               dictionary_unchanged(D0)
                       end, [monitor]),
    F1 = fun() ->
                 Pre = mrdb:read(R, a),
                 go_ahead_other(POther),
                 await_other_down(POther, MRef, ?LINE),
                 %% The test proc is still inside the transaction, and POther
                 %% has terminated/committed. If we now read 'a', we should see
                 %% the value that POther wrote (no isolation).
                 [{R, a, 17}] = mrdb:read(R, a),
                 ok = mrdb:insert(R, {R, a, 18})
         end,
    go_ahead_other(0, POther),
    Do0 = get_dict(),
    %% Our transaction should fail due to the resource conflict, and because
    %% we're not using retries.
    try mrdb:activity({tx, #{no_snapshot => true,
                             retries => 0}}, rdb, F1) of
        ok -> error(unexpected)
    catch
        error:{error, "Resource busy" ++ _} ->
            ok
    end,
    dictionary_unchanged(Do0),
    [{R, a, 17}] = mrdb:read(R, a),
    delete_tabs(Created),
    ok.

mrdb_two_procs_tx_restart(Config) ->
    tr_ct:with_trace(fun mrdb_two_procs_tx_restart_/1, Config,
                     light_tr_opts()).

mrdb_two_procs_tx_restart_(Config) ->
    R = ?FUNCTION_NAME,
    Parent = self(),
    Created = create_tabs([{R, []}], Config),
    check_stats(rdb),
    mrdb:insert(R, {R, a, 1}),
    Pre = mrdb:read(R, a),
    F0 = fun() ->
                 wait_for_other(Parent, ?LINE),
                 ok = mrdb:insert(R, {R, a, 17}),
                 wait_for_other(Parent, ?LINE)
         end,
    {POther, MRef} = spawn_opt(
                       fun() ->
                               ok = mrdb:activity(tx, rdb, F0)
                       end, [monitor]),
    F1 = fun() ->
                 OtherWrite = [{R, a, 17}],
                 Att = get_attempt(),
                 Expected = case Att of
                                0 -> Pre;
                                _ -> OtherWrite
                            end,
                 Expected = mrdb:read(R, a),
                 go_ahead_other(POther),
                 await_other_down(POther, MRef, ?LINE),
                 OtherWrite = mrdb:read(R, a),
                 ok = mrdb:insert(R, {R, a, 18})
         end,
    go_ahead_other(0, POther),
    Do0 = get_dict(),
    mrdb:activity({tx, #{no_snapshot => true}}, rdb, F1),
    dictionary_unchanged(Do0),
    check_stats(rdb),
    [{R, a, 18}] = mrdb:read(R, a),
    delete_tabs(Created),
    ok.

mrdb_two_procs_tx_inner_restart(Config) ->
    tr_ct:with_trace(fun mrdb_two_procs_tx_inner_restart_/1, Config,
                     dbg_tr_opts()).

mrdb_two_procs_tx_inner_restart_(Config) ->
    R = ?FUNCTION_NAME,
    Parent = self(),
    Created = create_tabs([{R, []}], Config),
    mrdb:insert(R, {R, a, 1}),
    mrdb:insert(R, {R, b, 1}),
    PreA = mrdb:read(R, a),
    PreB = mrdb:read(R, b),
    #{inner_retries := Ri0, outer_retries := Ro0} = check_stats(rdb),
    F0 = fun() ->
                 wait_for_other(Parent, ?LINE),
                 ok = mrdb:insert(R, {R, a, 17}),
                 wait_for_other(Parent, ?LINE)
         end,
    F1 = fun() ->
                 wait_for_other(Parent, ?LINE),
                 ok = mrdb:insert(R, {R, b, 147}),
                 wait_for_other(Parent, ?LINE)
         end,

    Spawn = fun(F) ->
                    Res = spawn_opt(
                            fun() ->
                                    ok = mrdb:activity(tx, rdb, F)
                            end, [monitor]),
                    Res
            end,
    {P1, MRef1} = Spawn(F0),
    {P2, MRef2} = Spawn(F1),
    F2 = fun() ->
                 PostA = [{R, a, 17}],  % once F0 (P1) has committed
                 PostB = [{R, b, 147}], % once F1 (P2) has committed
                 ARes = mrdb:read(R, a),  % We need to read first to establish a pre-image
                 BRes = mrdb:read(R, b),
                 Att = get_attempt(),
                 ct:log("Att = ~p", [Att]),
                 case Att of
                     0 ->                         % This is the first run (no retry yet)
                         ARes = PreA,
                         BRes = PreB,
                         go_ahead_other(0, P1),   % Having our pre-image, now let P1 write
                         go_ahead_other(0, P1),   % Let P1 commit, then await DOWN (normal)
                         await_other_down(P1, MRef1, ?LINE),
                         PostA = mrdb:read(R, a); % now, P1's write should leak through here
                     {0, 1} ->                    % This is the first (outer) retry
                         go_ahead_other(0, P2),   % Let P2 write
                         go_ahead_other(0, P2),   % Let P2 commit, then await DOWN (normal)
                         await_other_down(P2, MRef2, ?LINE),
                         PostA = mrdb:read(R, a), % now we should see writes from both P1
                         %% On OTP 23, the following step might fail due to timing, even
                         %% though the trace output looks as expected. Possibly some quirk
                         %% with leakage propagation time in rocksdb. Let's retry to be sure.
                         ok = try_until(PostB, fun() -> mrdb:read(R, b) end); % ... and P2
                     {1, 1} ->
                         PostA = mrdb:read(R, a),
                         PostB = mrdb:read(R, b),
                         ok
                 end,
                 mrdb:insert(R, {R, a, 18}),
                 mrdb:insert(R, {R, b, 18})
         end,
    Do0 = get_dict(),
    mrdb:activity({tx, #{no_snapshot => true, retries => {1,1}}}, rdb, F2),
    check_stats(rdb),
    dictionary_unchanged(Do0),
    [{R, a, 18}] = mrdb:read(R, a),
    [{R, b, 18}] = mrdb:read(R, b),
    #{inner_retries := Ri1, outer_retries := Ro1} = check_stats(rdb),
    {restarts, {1, 1}} = {restarts, {Ri1 - Ri0, Ro1 - Ro0}},
    delete_tabs(Created),
    ok.

try_until(Result, F) ->
    try_until(Result, F, 10).

try_until(Result, F, N) when N > 0 ->
    case F() of
        Result ->
            ok;
        _ ->
            receive after 100 -> ok end,
            try_until(Result, F, N-1)
    end;
try_until(Result, F, _) ->
    error({badmatch, {Result, F}}).

%
%% For testing purposes, we use side-effects inside the transactions
%% to synchronize the concurrent transactions. If a transaction fails due
%% to "Resource busy", it can re-run, but then mustn't attempt to sync with
%% the other transaction, which is already committed.
%%
%% To achieve this, we rely on the `mrdb:current_context()` function, which gives
%% us information about which is the current attempt; we only sync on the first
%% attempt, and ignore the sync ops on retries.
%%
-define(IF_FIRST(N, Expr),
        if N == 0 ->
                Expr;
           true ->
                ok
        end).

mrdb_two_procs_snap(Config) ->
    %% _snap is now the default tx mode
    R = ?FUNCTION_NAME,
    Parent = self(),
    Created = create_tabs([{R, []}], Config),
    mrdb:insert(R, {R, a, 1}),
    Pre = mrdb:read(R, a),
    mrdb:insert(R, {R, b, 11}),
    PreB = mrdb:read(R, b),
    F0 = fun() ->
                 ok = mrdb:insert(R, {R, a, 17}),
                 wait_for_other(Parent, ?LINE)
         end,
    {POther, MRef} =
        spawn_opt(fun() ->
                          D0 = get_dict(),
                          ok = mrdb:activity(tx, rdb, F0),
                          dictionary_unchanged(D0)
                  end, [monitor]),
    F1 = fun() ->
                 Att = get_attempt(),
                 go_ahead_other(Att, POther),
                 ARes = mrdb:read(R, a),
                 ARes = case Att of
                            0 -> Pre;
                            _ -> [{R, a, 17}]
                        end,
                 await_other_down(POther, MRef, ?LINE),
                 PreB = mrdb:read(R, b),
                 mrdb:insert(R, {R, b, 18}),
                 1477
         end,
    Do0 = get_dict(),
    1477 = mrdb:activity(tx, rdb, F1),
    dictionary_unchanged(Do0),
    [{R, a, 17}] = mrdb:read(R, a),
    [{R, b, 18}] = mrdb:read(R, b),
    delete_tabs(Created),
    ok.

%% We spawn two helper processes, making it 3 transactions, with the one
%% in the parent process. P2 writes to key `a`, which the other two try to read.
%% We make sure that P2 commits before finishing the other two, and P3 and the 
%% main thread sync, so as to maximize the contention for the retry lock.
mrdb_three_procs(Config) ->
    tr_ct:with_trace(fun mrdb_three_procs_/1, Config, dbg_tr_opts()).

mrdb_three_procs_(Config) ->
    R = ?FUNCTION_NAME,
    Parent = self(),
    Created = create_tabs([{R, []}], Config),
    A0 = {R, a, 1},
    A1 = {R, a, 11},
    A2 = {R, a, 12},
    ok = mrdb:insert(R, A0),
    F1 = fun() ->
                 ok = mrdb:insert(R, A1),
                 ok = mrdb:insert(R, {R, p1, 1})
         end,
    {P1, MRef1} =
        spawn_opt(fun() ->
                          D0 = get_dict(),
                          do_when_p_allows(
                            0, Parent, ?LINE,
                            fun() ->
                                    ok = mrdb:activity({tx,#{retries => 0}}, rdb, F1)
                            end),
                          dictionary_unchanged(D0)
                  end, [monitor]),
    F2 = fun() ->
                 [A0] = mrdb:read(R, a),
                 Att = get_attempt(),
                 wait_for_other(Att, Parent, ?LINE),
                 do_when_p_allows(
                   Att, Parent, ?LINE,
                   fun() ->
                           [A1] = mrdb:read(R, a),
                           ok = mrdb:insert(R, A2),
                           ok = mrdb:insert(R, {R, p2, 1})
                   end)
         end,
    {P2, MRef2} =
        spawn_opt(fun() ->
                          D0 = get_dict(),
                          try mrdb:activity(
                                {tx, #{retries => 0,
                                       no_snapshot => true}}, rdb, F2) of
                              ok -> error(unexpected)
                          catch
                              error:{error, "Resource busy" ++ _} ->
                                  ok
                          end,
                          dictionary_unchanged(D0)
                  end, [monitor]),
    Do0 = get_dict(),
    ok = mrdb:activity(tx, rdb,
                       fun() ->
                               Att = get_attempt(),
                               ARes = case Att of
                                          0 -> [A0];
                                          _ -> [A1]
                                      end,
                               %% First, ensure that P2 tx is running
                               go_ahead_other(Att, P2),
                               ARes = mrdb:read(R, a),
                               allow_p(Att, P1, ?LINE),
                               ARes = mrdb:read(R, a),
                               allow_p(Att, P2, ?LINE),
                               ARes = mrdb:read(R, a),
                               await_other_down(P1, MRef1, ?LINE),
                               await_other_down(P2, MRef2, ?LINE),
                               ok = mrdb:insert(R, {R, p0, 1})
                       end),
    dictionary_unchanged(Do0),
    [{R, p1, 1}] = mrdb:read(R, p1),
    [] = mrdb:read(R, p2),
    [A1] = mrdb:read(R, a),
    [{R, p0, 1}] = mrdb:read(R, p0),
    delete_tabs(Created),
    ok.

tr_opts() ->
    #{patterns => [ {mrdb, '_', '_', x}
                  , {mrdb_lib, '_', '_', x}
                  , {tr_ttb, event, 3, []}
                  , {?MODULE, go_ahead_other, 3, x}
                  , {?MODULE, wait_for_other, 3, x}
                  , {?MODULE, await_other_down, 3, x}
                  , {?MODULE, do_when_p_allows, 4, x}
                  , {?MODULE, allow_p, 3, x}
                  , {?MODULE, check_stats, 1, x}
                  ]}.

light_tr_opts() ->
    tr_flags(
      {self(), [call, sos, p]},
      tr_patterns(
        mrdb, [ {mrdb, insert, 2, x}
              , {mrdb, read, 2, x}
              , {mrdb, activity, x} ], tr_opts())).

dbg_tr_opts() ->
    tr_flags(
      {self(), [call, sos, p, 'receive']},
      tr_patterns(
        mrdb, [ {mrdb, insert, 2, x}
              , {mrdb, read, 2, x}
              , {mrdb, retry_activity, 3, x}
              , {mrdb, try_f, 2, x}
              , {mrdb, incr_attempt, 2, x}
              , {mrdb, current_context, 0, x}
              , {mrdb_mutex, do, 2, x}
              , {mrdb_mutex_serializer, do, 2, x}
              , {?MODULE, wait_for_other, 2, x}
              , {?MODULE, go_ahead_other, 1, x}
              , {?MODULE, try_until, 3, x}
              , {mrdb, activity, x} ], tr_opts())).

tr_patterns(Mod, Ps, #{patterns := Pats} = Opts) ->
    Pats1 = [P || P <- Pats, element(1,P) =/= Mod],
    Opts#{patterns => Ps ++ Pats1}.

tr_flags(Flags, Opts) when is_map(Opts) ->
    Opts#{flags => Flags}.

wait_for_other(Parent, L) ->
    wait_for_other(get_attempt(), Parent, 1000, L).

wait_for_other(Att, Parent, L) ->
    wait_for_other(Att, Parent, 1000, L).

wait_for_other(0, Parent, Timeout, L) ->
    MRef = monitor(process, Parent),
    Parent ! {self(), ready},
    receive
        {Parent, cont} ->
            demonitor(MRef),
            Parent ! {self(), cont_ack},
            ok;
        {'DOWN', MRef, _, _, Reason} ->
            ct:log("Parent died, Reason = ~p", [Reason]),
            exit(Reason)
    after Timeout ->
              demonitor(MRef),
              error({inner_timeout, L})
    end;
wait_for_other(_, _, _, _) ->
    ok.

do_when_p_allows(Att, P, Line, F) ->
    wait_for_other(Att, P, Line),
    F(),
    %% Tell P that we're done
    go_ahead_other(Att, P, Line),
    %% Wait for P to acknowlege
    wait_for_other(Att, P, Line).

allow_p(Att, P, Line) ->
    go_ahead_other(Att, P),
    %% This is where P does its thing.
    wait_for_other(Att, P, Line),
    %% Acknowledge
    go_ahead_other(Att, P, Line).

go_ahead_other(POther) ->
    go_ahead_other(get_attempt(), POther).

go_ahead_other(Att, POther) ->
    go_ahead_other(Att, POther, 1000).

go_ahead_other(Att, POther, Timeout) ->
    ?IF_FIRST(Att, go_ahead_other_(POther, Timeout)).

go_ahead_other_(POther, Timeout) ->
    receive
        {POther, ready} ->
            POther ! {self(), cont},
            receive
                {POther, cont_ack} ->
                    ok
            after Timeout ->
                    error(cont_ack_timeout)
            end
    after Timeout ->
            error(go_ahead_timeout)
    end.

%% Due to transaction restarts, we may already have collected
%% a DOWN message. In this case, P will already be dead, and there
%% will not be a 'DOWN' messsage still in the msg queue.
%% This is fine (we assume it is), and we just make sure that the
%% process didn't die abnormally.
await_other_down(P, MRef, Line) ->
    Attempt = get_attempt(),
    ?IF_FIRST(Attempt, await_other_down_(P, MRef, Line)).

await_other_down_(P, MRef, Line) ->
    receive {'DOWN', MRef, _, _, Reason} ->
                case Reason of
                    normal -> ok;
                    _ ->
                        error({abnormal_termination,
                               [ {pid, P}
                               , {mref, MRef}
                               , {line, Line}
                               , {reason, Reason}]})
                end
    after 1000 ->
              error({monitor_timeout, Line})
    end.

get_attempt() ->
    #{activity := #{attempt := Attempt}} = mrdb:current_context(),
    Attempt.

create_counters(_Config) ->
    create_tab(counters, []),
    mrdb:insert(counters, {counters, c0, 1}),
    mrdb:update_counter(counters, c1, 1),
    [{counters, c0, 1}] = mrdb:read(counters, c0),
    [{counters, c1, 1}] = mrdb:read(counters, c1),
    ct:log("Created tab counters, with objs c0 (1) and c1 (1)", []),
    ok.

restart_node(_Config) ->
    mnesia:stop(),
    ok = mnesia:start(),
    ct:log("mnesia restarted", []),
    ok.

update_counters(_Config) ->
    [{counters, c0, C0Prev}] = mrdb:read(counters, c0),
    [{counters, c1, C1Prev}] = mrdb:read(counters, c1),
    ct:log("co: ~p, c1: ~p", [C0Prev, C1Prev]),
    ok = mrdb:update_counter(counters, c0, 1),
    ok = mrdb:update_counter(counters, c1, 1),
    ct:log("Incremented c0 and c1 by 1", []),
    C0 = C0Prev + 1,
    C1 = C1Prev + 1,
    [{counters, c0, C0}] = mrdb:read(counters, c0),
    [{counters, c1, C1}] = mrdb:read(counters, c1),
    ct:log("c0: ~p, c1: ~p", [C0, C1]),
    ok.

create_tabs(Tabs, Config) ->
    Res = lists:map(fun create_tab/1, Tabs),
    tr_ct:trace_checkpoint(?TABS_CREATED, Config),
    Res.

create_tab({T, Opts}) -> create_tab(T, Opts).

create_tab(T, Opts) ->
    {atomic, ok} = mnesia:create_table(T, [{rdb,[node()]} | Opts]),
    T.

delete_tabs(Tabs) ->
    [{atomic,ok} = mnesia:delete_table(T) || T <- Tabs],
    ok.

get_dict() ->
    {dictionary, D} = process_info(self(), dictionary),
    [X || {K,_} = X <- D,
          K =/= log_timestamp].

dictionary_unchanged(Old) ->
    New = get_dict(),
    #{ deleted := []
     , added   := [] } = #{ deleted => Old -- New
                          , added   => New -- Old },
    ok.

check_stats(Alias) ->
    Stats = mrdb_stats:get(Alias),
    ct:log("Stats: ~p", [Stats]),
    Stats.

%% DB-level rocksdb options cannot be carried by a column family table, so the admin db
%% (shared by every column family of the alias) is opened with the configured defaults.
admin_db_opens_with_default_rocksdb_opts(_Config) ->
    {match, _} = re:run(admin_log(rdb), <<"Options.max_open_files: 123">>),
    ok.

%% rocksdb_access_type is a user property like any other; a column family table must
%% honour it the same way a standalone table does.
direct_access_column_family_table(_Config) ->
    T = direct_cf,
    {atomic, ok} = mnesia:create_table(T, [{rdb, [node()]}, {attributes, [k, v]},
                                           {user_properties, [{rocksdb_access_type, direct}]}]),
    #{type := column_family, access_type := direct} = mrdb:get_ref(T),
    ok = mnesia:dirty_write({T, 1, one}),
    ok = mrdb:insert(T, {T, 2, two}),
    [{T, 1, one}] = mnesia:dirty_read(T, 1),
    [{T, 2, two}] = mnesia:dirty_read(T, 2),
    ok.

%% block_cache_size names one cache for the whole node: every column family (and every
%% standalone db) opened with the same size shares it, instead of each allocating its own.
column_families_share_one_block_cache(_Config) ->
    Opts = [{user_properties, [{rocksdb_opts, [{block_based_table_options, [{block_cache_size, 8388608}]}]}]}],
    [{atomic, ok} = mnesia:create_table(T, [{rdb, [node()]}, {attributes, [k, v]} | Opts]) || T <- [cache_a, cache_b, cache_c]],
    [ok = mnesia:dirty_write({cache_a, N, {payload, N, lists:duplicate(50, N)}}) || N <- lists:seq(1, 2000)],
    #{db_ref := Db, cf_handle := CfA} = mrdb:get_ref(cache_a),
    ok = rocksdb:flush(Db, CfA, [{wait, true}]),
    [[_] = mnesia:dirty_read(cache_a, N) || N <- lists:seq(1, 2000)],
    Usage = fun(T) ->
        #{db_ref := D, cf_handle := Cf} = mrdb:get_ref(T),
        {ok, Bytes} = rocksdb:get_property(D, Cf, <<"rocksdb.block-cache-usage">>),
        binary_to_integer(Bytes)
    end,
    Usages = [{T, Usage(T)} || T <- [cache_a, cache_b, cache_c]],
    ct:log("block cache usage seen through each table: ~p", [Usages]),
    true = Usage(cache_a) > 0,
    [_Shared] = lists:usort([U || {_T, U} <- Usages]),
    ok.

%% An alias configured under alias_rocksdb_opts gets a RocksDB instance of its own, opened
%% with its DB-level options on top of default_rocksdb_opts; other aliases keep the defaults.
alias_db_opens_with_alias_rocksdb_opts(_Config) ->
    {match, _} = re:run(admin_log(?TRAFFIC), <<"Options.max_open_files: -1\n">>),
    {match, _} = re:run(admin_log(rdb), <<"Options.max_open_files: 123\n">>),
    #{db_ref := TrafficDb, mountpoint := TrafficMP} = mrdb:get_ref({admin, ?TRAFFIC}),
    #{db_ref := MainDb, mountpoint := MainMP} = mrdb:get_ref({admin, rdb}),
    true = TrafficDb =/= MainDb,
    true = TrafficMP =/= MainMP,
    ok.

%% Tables of the alias are column families of the alias' own instance, each created with
%% its own rocksdb_opts. FIFO compaction is only accepted there, since RocksDB demands
%% max_open_files = -1 of the whole instance.
alias_tables_live_in_alias_db(_Config) ->
    [{atomic, ok} = mnesia:create_table(T, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                             {user_properties, [{rocksdb_opts, fifo_opts(Size)}]}])
     || {T, Size} <- traffic_tabs()],
    {atomic, ok} = mnesia:create_table(plain, [{rdb, [node()]}, {attributes, [k, v]}]),
    #{db_ref := TrafficDb, mountpoint := TrafficMP} = mrdb:get_ref({admin, ?TRAFFIC}),
    #{db_ref := MainDb, mountpoint := MainMP} = mrdb:get_ref({admin, rdb}),
    [#{type := column_family, alias := ?TRAFFIC, db_ref := TrafficDb} = mrdb:get_ref(T)
     || {T, _} <- traffic_tabs()],
    #{type := column_family, alias := rdb, db_ref := MainDb} = mrdb:get_ref(plain),
    {ok, TrafficCFs} = rocksdb:list_column_families(TrafficMP, []),
    {ok, MainCFs} = rocksdb:list_column_families(MainMP, []),
    ct:log("~p column families: ~p~n~p column families: ~p", [?TRAFFIC, TrafficCFs, rdb, MainCFs]),
    [true = lists:member(cf_name(T), TrafficCFs) || {T, _} <- traffic_tabs()],
    [false = lists:member(cf_name(T), MainCFs) || {T, _} <- traffic_tabs()],
    true = lists:member(cf_name(plain), MainCFs),
    false = lists:member(cf_name(plain), TrafficCFs),
    [ok = mnesia:dirty_write({T, hello, T}) || T <- [plain | traffic_names()]],
    [[{T, hello, T}] = mnesia:dirty_read(T, hello) || T <- [plain | traffic_names()]],
    [ok = mnesia:dirty_delete(T, hello) || T <- traffic_names()],
    check_fifo_options(),
    ok.

%% max_table_files_size is a per column family limit: past it, only the table that set the
%% small limit loses its oldest data, its sibling in the same instance keeps everything.
fifo_options_apply_per_column_family(_Config) ->
    fill_traffic_tabs(1, ?FIFO_ROUNDS),
    ok = try_until([], fun() -> mnesia:dirty_read(traffic_wp, {1, 1}) end, 100),
    [_] = mnesia:dirty_read(traffic_wp, {?FIFO_ROUNDS, 1}),
    all_present(traffic_ws, 1, ?FIFO_ROUNDS),
    ok.

%% After a restart the tables are column families of the alias' instance again, reopened
%% with their own rocksdb_opts rather than defaults, and the data written before is there.
alias_tables_reopen_with_their_options(_Config) ->
    ok = mnesia:wait_for_tables([plain | traffic_names()], 10000),
    #{db_ref := TrafficDb} = mrdb:get_ref({admin, ?TRAFFIC}),
    #{db_ref := MainDb} = mrdb:get_ref({admin, rdb}),
    [#{type := column_family, alias := ?TRAFFIC, db_ref := TrafficDb} = mrdb:get_ref(T)
     || T <- traffic_names()],
    #{alias := rdb, db_ref := MainDb} = mrdb:get_ref(plain),
    [{plain, hello, plain}] = mnesia:dirty_read(plain, hello),
    [_] = mnesia:dirty_read(traffic_wp, {?FIFO_ROUNDS, 1}),
    all_present(traffic_ws, 1, ?FIFO_ROUNDS),
    check_fifo_options(),
    %% The FIFO limit is still in force: further writes push out the pre-restart data
    fill_traffic_tabs(?FIFO_ROUNDS + 1, 2 * ?FIFO_ROUNDS),
    ok = try_until([], fun() -> mnesia:dirty_read(traffic_wp, {?FIFO_ROUNDS, 1}) end, 100),
    [_] = mnesia:dirty_read(traffic_wp, {2 * ?FIFO_ROUNDS, 1}),
    all_present(traffic_ws, 1, 2 * ?FIFO_ROUNDS),
    ok.

%% Deleting a table of the alias drops its column family, and only it.
delete_alias_table(_Config) ->
    #{mountpoint := TrafficMP} = mrdb:get_ref({admin, ?TRAFFIC}),
    {atomic, ok} = mnesia:delete_table(traffic_wp),
    {ok, CFs} = rocksdb:list_column_families(TrafficMP, []),
    false = lists:member(cf_name(traffic_wp), CFs),
    true = lists:member(cf_name(traffic_ws), CFs),
    all_present(traffic_ws, 1, 2 * ?FIFO_ROUNDS),
    ok = restart_and_wait([traffic_ws, plain]),
    {aborted, {no_exists, _}} = mnesia:delete_table(traffic_wp),
    all_present(traffic_ws, 1, 2 * ?FIFO_ROUNDS),
    {atomic, ok} = mnesia:delete_table(traffic_ws),
    {atomic, ok} = mnesia:delete_table(plain),
    ok.

%% An index lives and dies with its table's rows, so it gets the table's rocksdb_opts: an
%% index of a FIFO table is FIFO too, when created and again after a restart, and its
%% entries age out with the rows instead of piling up.
alias_indexes_keep_their_tables_options(_Config) ->
    {atomic, ok} = mnesia:create_table(indexed_fifo, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                      {user_properties, [{rocksdb_opts, [{ttl, 3600} | fifo_opts(infinity)]}]}]),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    true = cf_is_fifo(MP, "{i,indexed_fifo,", ?UNLIMITED),
    ok = restart_and_wait([indexed_fifo]),
    true = cf_is_fifo(MP, "{i,indexed_fifo,", ?UNLIMITED),
    {atomic, ok} = mnesia:delete_table(indexed_fifo),
    ok.

%% A checkpoint's retainer must keep every old value for as long as the checkpoint is
%% active, so it does not take its table's FIFO options: it keeps the defaults.
alias_retainers_keep_default_options(_Config) ->
    {atomic, ok} = mnesia:create_table(retained_fifo, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                                       {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    ok = mnesia:dirty_write({retained_fifo, 1, one}),
    {ok, Checkpoint, _Nodes} = mnesia:activate_checkpoint([{max, [retained_fifo]}]),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    Fifo = cf_is_fifo(MP, "{r,retained_fifo,", ?SMALL_FIFO),
    ok = mnesia:deactivate_checkpoint(Checkpoint),
    {atomic, ok} = mnesia:delete_table(retained_fifo),
    false = Fifo,
    ok.

%% A table that ran with level compaction, its data compacted down to the bottom level, can
%% be switched to FIFO through its rocksdb_opts: after a restart RocksDB opens it as FIFO and
%% the data is still there.
alias_table_switched_to_fifo_reopens_with_its_data(_Config) ->
    {atomic, ok} = mnesia:create_table(leveled_then_fifo, [{?TRAFFIC, [node()]}, {attributes, [k, v]}]),
    [ok = mnesia:dirty_write({leveled_then_fifo, N, crypto:strong_rand_bytes(1024)}) || N <- lists:seq(1, 6000)],
    #{db_ref := Db, cf_handle := Cf} = mrdb:get_ref(leveled_then_fifo),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    ok = rocksdb:flush(Db, Cf, [{wait, true}]),
    ok = rocksdb:compact_range(Db, Cf, undefined, undefined, [{bottommost_level_compaction, force}]),
    {ok, Levels} = rocksdb:get_property(Db, Cf, <<"rocksdb.levelstats">>),
    ct:log("levels before the switch:~n~s", [Levels]),
    {atomic, ok} = mnesia:write_table_property(leveled_then_fifo, {rocksdb_opts, fifo_opts(?LARGE_FIFO)}),
    ok = restart_and_wait([leveled_then_fifo]),
    true = cf_is_fifo(MP, "{d,leveled_then_fifo}", ?LARGE_FIFO),
    [{leveled_then_fifo, 1, _}] = mnesia:dirty_read(leveled_then_fifo, 1),
    [{leveled_then_fifo, 6000, _}] = mnesia:dirty_read(leveled_then_fifo, 6000),
    {atomic, ok} = mnesia:delete_table(leveled_then_fifo),
    ok.

%% FIFO compaction options in an alias' config are for its tables: the instance's own column
%% families, which hold the table metadata, never take them, so the metadata cannot age out.
alias_fifo_options_never_reach_the_admin_column_families(_Config) ->
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts,
                             [{rdb_fifo_cfg, [{max_open_files, -1} | fifo_opts(?SMALL_FIFO)] ++ [{ttl, 3600}]} | Aliases]),
    {ok, rdb_fifo_cfg} = mnesia_rocksdb:register(rdb_fifo_cfg),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    #{mountpoint := MP} = mrdb:get_ref({admin, rdb_fifo_cfg}),
    {ok, CFs} = rocksdb:list_column_families(MP, []),
    Sections = [{CF, cf_options_section(latest_options_file(MP), CF)} || CF <- CFs],
    ct:log("admin column families: ~p", [Sections]),
    [] = [CF || {CF, Section} <- Sections, re:run(Section, <<"compaction_style=kCompactionStyleFIFO">>) =/= nomatch],
    ok.

%% RocksDB only opens FIFO column families in an instance with max_open_files = -1. A table
%% that would land in one without it is refused before mnesia commits it: a column family
%% table in an alias opened with another value, a standalone table not asking for it.
fifo_needs_max_open_files_unlimited_in_its_instance(_Config) ->
    {aborted, InMain} = mnesia:create_table(fifo_in_main, [{rdb, [node()]}, {attributes, [k, v]},
                                                         {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    true = refused_for(fifo_requires_max_open_files_unlimited, InMain),
    {aborted, Standalone} = mnesia:create_table(fifo_standalone, [{rdb, [node()]}, {attributes, [k, v]},
                                                                {user_properties, [{rocksdb_standalone, true},
                                                                                   {rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    true = refused_for(fifo_requires_max_open_files_unlimited, Standalone),
    {atomic, ok} = mnesia:create_table(fifo_standalone, [{rdb, [node()]}, {attributes, [k, v]},
                                                       {user_properties, [{rocksdb_standalone, true},
                                                                          {rocksdb_opts, [{max_open_files, -1} | fifo_opts(?SMALL_FIFO)]}]}]),
    ok = mnesia:dirty_write({fifo_standalone, 1, one}),
    {atomic, ok} = mnesia:delete_table(fifo_standalone),
    ok.

%% An index does not expire with its rows under a size cap: its column family is smaller, so
%% the rows go first and the index keeps their entries. A FIFO table with an index must
%% therefore expire by age (ttl) and have its size cap switched off (infinity).
fifo_table_with_index_needs_a_ttl_and_no_size_cap(_Config) ->
    Create = fun(Name, RdbOpts) -> mnesia:create_table(Name, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                              {user_properties, [{rocksdb_opts, RdbOpts}]}]) end,
    {aborted, Capped} = Create(fifo_capped_index, fifo_opts(?SMALL_FIFO)),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, Capped),
    {aborted, TtlAndCap} = Create(fifo_ttl_capped_index, [{ttl, 3600} | fifo_opts(?SMALL_FIFO)]),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, TtlAndCap),
    {aborted, NoTtl} = Create(fifo_uncapped_index, fifo_opts(infinity)),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, NoTtl),
    {atomic, ok} = Create(fifo_aged_index, [{ttl, 3600} | fifo_opts(infinity)]),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    true = cf_is_fifo(MP, "{d,fifo_aged_index}", ?UNLIMITED),
    true = cf_is_fifo(MP, "{i,fifo_aged_index,", ?UNLIMITED),
    ok = mnesia:dirty_write({fifo_aged_index, 1, one}),
    [{fifo_aged_index, 1, one}] = mnesia:dirty_index_read(fifo_aged_index, one, v),
    {atomic, ok} = mnesia:delete_table(fifo_aged_index),
    ok.

%% The same holds for an index added to a FIFO table later.
index_added_later_to_capped_fifo_table_is_refused(_Config) ->
    {atomic, ok} = mnesia:create_table(capped_then_indexed, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                                             {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    {aborted, Reason} = mnesia:add_table_index(capped_then_indexed, v),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, Reason),
    ok = mnesia:dirty_write({capped_then_indexed, 1, one}),
    [{capped_then_indexed, 1, one}] = mnesia:dirty_read(capped_then_indexed, 1),
    {atomic, ok} = mnesia:delete_table(capped_then_indexed),
    ok.

%% And for size-capped FIFO options written later onto a table that has an index.
capped_fifo_options_written_later_onto_indexed_table_are_refused(_Config) ->
    {atomic, ok} = mnesia:create_table(indexed_then_capped, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]}]),
    {aborted, Reason} = mnesia:write_table_property(indexed_then_capped, {rocksdb_opts, fifo_opts(?SMALL_FIFO)}),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, Reason),
    {atomic, ok} = mnesia:delete_table(indexed_then_capped),
    ok.

refused_for(Why, Reason) ->
    ct:log("refused: ~p", [Reason]),
    string:find(lists:flatten(io_lib:format("~p", [Reason])), atom_to_list(Why)) =/= nomatch.

%% An index inherits only its table's bounding options (compaction style, FIFO options, ttl):
%% anything tuned for the table's own keys, here its write buffer, stays the table's.
alias_indexes_inherit_only_their_tables_bounding_options(_Config) ->
    {atomic, ok} = mnesia:create_table(bounded_index, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                       {user_properties, [{rocksdb_opts, [{ttl, 3600}, {write_buffer_size, 3145728} | fifo_opts(infinity)]}]}]),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    true = cf_is_fifo(MP, "{i,bounded_index,", ?UNLIMITED),
    {match, _} = re:run(cf_section(MP, "{d,bounded_index}"), <<"write_buffer_size=3145728">>),
    nomatch = re:run(cf_section(MP, "{i,bounded_index,"), <<"write_buffer_size=3145728">>),
    {atomic, ok} = mnesia:delete_table(bounded_index),
    ok.

%% Clearing a table recreates its index with the table's current options, the same ones a
%% restart would reopen it with, not the ones the index was first created with.
cleared_index_takes_its_tables_current_options(_Config) ->
    {atomic, ok} = mnesia:create_table(cleared_index, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]}]),
    {atomic, ok} = mnesia:write_table_property(cleared_index, {rocksdb_opts, [{ttl, 3600} | fifo_opts(infinity)]}),
    {atomic, ok} = mnesia:clear_table(cleared_index),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    true = cf_is_fifo(MP, "{i,cleared_index,", ?UNLIMITED),
    {atomic, ok} = mnesia:delete_table(cleared_index),
    ok.

%% With MRDB_LEGACY=true every table is standalone, so a FIFO table is judged against its own
%% options, not its alias' instance.
fifo_check_follows_mrdb_legacy_standalone(_Config) ->
    true = os:putenv("MRDB_LEGACY", "true"),
    Result = mnesia:create_table(legacy_fifo, [{rdb, [node()]}, {attributes, [k, v]},
                                              {user_properties, [{rocksdb_opts, [{max_open_files, -1} | fifo_opts(?SMALL_FIFO)]}]}]),
    true = os:unsetenv("MRDB_LEGACY"),
    {atomic, ok} = Result,
    {atomic, ok} = mnesia:delete_table(legacy_fifo),
    ok.

%% An instance that fails to be created leaves no directory behind, so once its config is
%% fixed the next start creates it afresh instead of failing to reopen an empty directory.
failed_create_leaves_no_instance_directory(_Config) ->
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{rdb_bad_wal, [{wal_dir, "/proc/nonexistent/wal"}]} | Aliases]),
    MP = mnesia_rocksdb_lib:data_mountpoint({admin, rdb_bad_wal}),
    {_, Reported} = capture_log(error, "Cannot load admin db for alias rdb_bad_wal", fun() -> catch mnesia_rocksdb:register(rdb_bad_wal) end),
    ok = await_restartable_mnesia(),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    ct:log("reported: ~ts", [Reported]),
    false = filelib:is_dir(MP),
    ok = mnesia:start(),
    {ok, rdb_bad_wal} = mnesia_rocksdb:register(rdb_bad_wal),
    #{db_ref := _} = mrdb:get_ref({admin, rdb_bad_wal}),
    ok.

%% A standalone table's index is an instance of its own: it takes max_open_files from its
%% table along with the FIFO options, as RocksDB opens FIFO only with max_open_files = -1.
standalone_fifo_table_with_index_opens_and_reopens(_Config) ->
    {atomic, ok} = mnesia:create_table(standalone_indexed_fifo,
                                       [{rdb, [node()]}, {attributes, [k, v]}, {index, [v]},
                                        {user_properties, [{rocksdb_standalone, true},
                                                           {rocksdb_opts, [{max_open_files, -1}, {ttl, 3600} | fifo_opts(infinity)]}]}]),
    ok = mnesia:dirty_write({standalone_indexed_fifo, 1, one}),
    [{standalone_indexed_fifo, 1, one}] = mnesia:dirty_index_read(standalone_indexed_fifo, one, v),
    ok = restart_and_wait([standalone_indexed_fifo]),
    [{standalone_indexed_fifo, 1, one}] = mnesia:dirty_index_read(standalone_indexed_fifo, one, v),
    {atomic, ok} = mnesia:delete_table(standalone_indexed_fifo),
    ok.

%% A table is judged against the options its alias' instance runs with: options changed in
%% the env take effect only when the instance is reopened.
fifo_check_judges_the_options_its_instance_runs_with(_Config) ->
    Props = [{type, set}, {attributes, [k, v]}, {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}],
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, [{max_open_files, -1}]),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{?TRAFFIC, [{max_open_files, 123}]}]),
    InMain = mnesia_rocksdb:check_definition(rdb, live_opts, [node()], Props),
    InTraffic = mnesia_rocksdb:check_definition(?TRAFFIC, live_opts, [node()], Props),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, [{max_open_files, 123}]),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    {error, {fifo_requires_max_open_files_unlimited, live_opts}} = InMain,
    {ok, _} = InTraffic,
    ok.

%% Malformed rocksdb_opts abort the schema change with a reason naming them; a bare atom is an
%% option set to true, as in a proplist.
malformed_rocksdb_opts_are_refused_cleanly(_Config) ->
    Create = fun(Name, RdbOpts) -> mnesia:create_table(Name, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                              {user_properties, [{rocksdb_opts, RdbOpts}]}]) end,
    {aborted, NotAList} = Create(opts_not_a_list, not_a_list),
    true = refused_for(invalid_rocksdb_opts, NotAList),
    {aborted, NotAnOption} = Create(opts_not_an_option, [{ttl, 3600, extra}]),
    true = refused_for(invalid_rocksdb_opts, NotAnOption),
    {aborted, FifoNotAList} = Create(fifo_opts_not_a_list, [{ttl, 3600}, {compaction_style, fifo}, {compaction_options_fifo, 1024}]),
    true = refused_for(invalid_rocksdb_opts, FifoNotAList),
    {atomic, ok} = Create(bare_atom_option, [use_bloomfilter, {ttl, 3600} | fifo_opts(infinity)]),
    ok = mnesia:dirty_write({bare_atom_option, 1, one}),
    [{bare_atom_option, 1, one}] = mnesia:dirty_index_read(bare_atom_option, one, v),
    {atomic, ok} = mnesia:delete_table(bare_atom_option),
    yes = mnesia:system_info(is_running),
    ok.

%% A failed create removes only a directory it made itself: a path already there, here a
%% dangling symlink to an unmounted volume, is left alone.
failed_create_keeps_a_path_it_did_not_create(_Config) ->
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{rdb_dangling, [{wal_dir, "/proc/nonexistent/wal"}]} | Aliases]),
    MP = mnesia_rocksdb_lib:data_mountpoint({admin, rdb_dangling}),
    ok = file:make_symlink("/nonexistent/rdb_dangling_volume", MP),
    {_, Reported} = capture_log(error, "Cannot load admin db for alias rdb_dangling", fun() -> catch mnesia_rocksdb:register(rdb_dangling) end),
    ok = await_restartable_mnesia(),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    ct:log("reported: ~ts", [Reported]),
    Kept = file:read_link(MP),
    _ = file:delete(MP),
    ok = mnesia:start(),
    {ok, "/nonexistent/rdb_dangling_volume"} = Kept,
    ok.

%% A property written through the admin lands in mnesia's schema and in the open table's
%% record together; one the schema refuses changes neither.
admin_write_table_property_reaches_the_schema_and_the_table(_Config) ->
    {atomic, ok} = mnesia:create_table(admin_props, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]}]),
    ok = mnesia_rocksdb_admin:write_table_property(?TRAFFIC, admin_props, {owner, maria}),
    true = lists:member({owner, maria}, mnesia:table_info(admin_props, user_properties)),
    ok = try_until({owner, maria}, fun() -> maps:get(owner, admin_user_properties(admin_props), none) end),
    {error, Refused} = mnesia_rocksdb_admin:write_table_property(?TRAFFIC, admin_props, {rocksdb_opts, fifo_opts(?SMALL_FIFO)}),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, Refused),
    false = lists:keymember(rocksdb_opts, 1, mnesia:table_info(admin_props, user_properties)),
    false = maps:is_key(rocksdb_opts, admin_user_properties(admin_props)),
    {atomic, ok} = mnesia:delete_table(admin_props),
    ok.

admin_user_properties(Tab) ->
    #{properties := #{user_properties := UPs}} = mrdb:get_ref(Tab),
    UPs.

%% The admin server serves every alias: a property write must not make it wait on a schema
%% lock, here held by the caller itself, who is waiting on the admin's reply.
admin_write_table_property_does_not_wait_on_its_callers_schema_lock(_Config) ->
    {atomic, ok} = mnesia:create_table(locked_props, [{?TRAFFIC, [node()]}, {attributes, [k, v]}]),
    Self = self(),
    Caller = spawn(fun() ->
                           Res = mnesia_schema:schema_transaction(
                                   fun() ->
                                           mnesia:lock({table, schema}, write),
                                           mnesia_rocksdb_admin:write_table_property(?TRAFFIC, locked_props, {owner, maria})
                                   end),
                           Self ! {written, Res}
                   end),
    Written = receive {written, Res} -> Res after 5000 -> exit(Caller, kill), still_waiting end,
    ct:log("written: ~p", [Written]),
    {atomic, ok} = mnesia:delete_table(locked_props),
    {atomic, {error, _}} = Written,
    ok.

%% max_data_files_size, when set, caps FIFO in place of max_table_files_size: an indexed
%% table needs both off, infinity switching off either.
fifo_data_size_cap_counts_as_a_size_cap(_Config) ->
    Create = fun(Name, Fifo) -> mnesia:create_table(Name, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                           {user_properties, [{rocksdb_opts, [{ttl, 3600}, {compaction_style, fifo},
                                                                                              {compaction_options_fifo, Fifo}]}]}]) end,
    {aborted, DataCapped} = Create(data_capped_index, [{max_table_files_size, infinity}, {max_data_files_size, ?SMALL_FIFO}]),
    true = refused_for(fifo_with_index_requires_ttl_and_no_size_cap, DataCapped),
    {atomic, ok} = Create(data_uncapped_index, [{max_table_files_size, infinity}, {max_data_files_size, infinity}]),
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    {match, _} = re:run(cf_section(MP, "{i,data_uncapped_index,"), ["max_data_files_size=", integer_to_list(?UNLIMITED)]),
    {atomic, ok} = mnesia:delete_table(data_uncapped_index),
    ok.

%% Removing an alias closes and deletes its instance, and its ref goes with it: nothing may
%% go on judging tables against, or reaching, an instance that is gone.
removed_alias_leaves_no_ref_behind(_Config) ->
    {ok, rdb_removed} = mnesia_rocksdb:register(rdb_removed),
    #{db_ref := _} = mrdb:get_ref({admin, rdb_removed}),
    ok = mnesia_rocksdb:remove_aliases([rdb_removed]),
    Left = mnesia_rocksdb_admin:get_ref({admin, rdb_removed}, gone),
    {atomic, ok} = mnesia_schema:delete_backend_type(rdb_removed),
    gone = Left,
    ok.

%% The admin writes properties only of tables this node stores in the given alias.
admin_write_table_property_refuses_tables_outside_its_alias(_Config) ->
    {atomic, ok} = mnesia:create_table(other_alias_props, [{?TRAFFIC, [node()]}, {attributes, [k, v]}]),
    {atomic, ok} = mnesia:create_table(ram_props, [{ram_copies, [node()]}, {attributes, [k, v]}]),
    OtherAlias = mnesia_rocksdb_admin:write_table_property(rdb, other_alias_props, {owner, maria}),
    Ram = mnesia_rocksdb_admin:write_table_property(rdb, ram_props, {owner, maria}),
    Untouched = [lists:keymember(owner, 1, mnesia:table_info(T, user_properties)) || T <- [other_alias_props, ram_props]],
    {atomic, ok} = mnesia:delete_table(other_alias_props),
    {atomic, ok} = mnesia:delete_table(ram_props),
    {error, not_found} = OtherAlias,
    {error, not_found} = Ram,
    [false, false] = Untouched,
    ok.

%% A column family left in one alias' instance by a table now stored in another (an
%% interrupted migration, say) reopens with the defaults: the table's options are its own
%% instance's business, here FIFO, which the main instance could not hold.
column_family_left_by_a_table_of_another_alias_reopens_with_defaults(_Config) ->
    {atomic, ok} = mnesia:create_table(moved_fifo, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                                    {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    #{db_ref := MainDb} = mrdb:get_ref({admin, rdb}),
    {ok, _} = rocksdb:create_column_family(MainDb, cf_name(moved_fifo), []),
    {Restarted, Refused} = capture_log(error, "Cannot load admin db for alias rdb", 0, fun() -> restart_and_wait([moved_fifo]) end),
    ct:log("restarted: ~p, refused: ~ts", [Restarted, Refused]),
    nothing_reported = Refused,
    ok = Restarted,
    ok = mnesia:dirty_write({moved_fifo, 1, one}),
    {atomic, ok} = mnesia:delete_table(moved_fifo),
    ok.

%% Whether a table's instance can hold FIFO is judged on the nodes holding the table, against
%% their own instances: mnesia checks a definition on every node, schema merges included, and
%% a node without a copy must not refuse it over its own options. The index rule depends on
%% the table's options only, so every node applies it.
fifo_instance_rule_is_judged_where_the_table_lives(_Config) ->
    Elsewhere = ['holder@elsewhere'],
    Def = fun(Extra) -> [{type, set}, {attributes, [k, v]}, {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]} | Extra] end,
    {ok, _} = mnesia_rocksdb:check_definition(rdb, held_elsewhere, Elsewhere, Def([])),
    {error, {fifo_requires_max_open_files_unlimited, held_here}} = mnesia_rocksdb:check_definition(rdb, held_here, [node()], Def([])),
    {error, {fifo_with_index_requires_ttl_and_no_size_cap, indexed_elsewhere}} =
        mnesia_rocksdb:check_definition(?TRAFFIC, indexed_elsewhere, Elsewhere, Def([{index, [{3, ordered}]}])),
    ok.

%% mnesia checks a definition on the node running the schema operation only, so that node
%% asks every other node holding the table about its own instance; one it cannot reach
%% judges the table itself when its instance opens.
fifo_instance_rule_is_judged_on_every_node_holding_the_table(_Config) ->
    {ok, Peer, Holder} = peer:start_link(#{name => peer:random_name(fifo_holder), args => ["-pa" | code:get_path()]}),
    SetHolderOpts = fun(MaxOpenFiles) ->
                            ok = rpc:call(Holder, application, set_env,
                                          [mnesia_rocksdb, alias_rocksdb_opts, [{?TRAFFIC, [{max_open_files, MaxOpenFiles}]}]])
                    end,
    Def = [{type, set}, {attributes, [k, v]}, {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}],
    ok = SetHolderOpts(123),
    Both = mnesia_rocksdb:check_definition(?TRAFFIC, held_by_both, [node(), Holder], Def),
    HolderOnly = mnesia_rocksdb:check_definition(?TRAFFIC, held_by_holder, [Holder], Def),
    ok = SetHolderOpts(-1),
    BothUnlimited = mnesia_rocksdb:check_definition(?TRAFFIC, held_by_both, [node(), Holder], Def),
    ok = peer:stop(Peer),
    Unreachable = mnesia_rocksdb:check_definition(?TRAFFIC, held_by_both, [node(), Holder], Def),
    {error, {fifo_requires_max_open_files_unlimited, held_by_both}} = Both,
    {error, {fifo_requires_max_open_files_unlimited, held_by_holder}} = HolderOnly,
    {ok, _} = BothUnlimited,
    {ok, _} = Unreachable,
    ok.

%% mnesia holds schema locks while it checks a definition: holders slow to answer about their
%% instances delay it by one timeout in all, not one per holder.
holders_are_asked_about_their_instances_at_once(_Config) ->
    Slow = [begin
                {ok, Peer, Holder} = peer:start_link(#{name => peer:random_name(slow_holder), args => ["-pa" | code:get_path()]}),
                ok = rpc:call(Holder, meck, new, [mnesia_rocksdb_admin, [passthrough, no_link]]),
                ok = rpc:call(Holder, meck, expect, [mnesia_rocksdb_admin, instance_db_opts,
                                                     fun(_Alias) -> receive after 60000 -> [] end end]),
                {Peer, Holder}
            end || _ <- [1, 2]],
    Def = [{type, set}, {attributes, [k, v]}, {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}],
    {Micros, Checked} = timer:tc(mnesia_rocksdb, check_definition, [?TRAFFIC, held_by_slow, [Holder || {_, Holder} <- Slow], Def]),
    _ = [ok = peer:stop(Peer) || {Peer, _} <- Slow],
    ct:log("checked in ~p ms: ~p", [Micros div 1000, Checked]),
    {ok, _} = Checked,
    true = Micros < 8000000,
    ok.

%% A table whose rocksdb_opts in the schema are malformed (written before they were
%% checked) reopens with the defaults, with a warning, instead of stopping its instance.
malformed_options_in_the_schema_reopen_with_defaults(_Config) ->
    {atomic, ok} = mnesia:create_table(legacy_opts, [{?TRAFFIC, [node()]}, {attributes, [k, v]}]),
    ok = meck:new(mnesia_rocksdb, [passthrough]),
    ok = meck:expect(mnesia_rocksdb, check_definition, fun(_Alias, _Tab, _Nodes, Props) -> {ok, Props} end),
    Written = mnesia:write_table_property(legacy_opts, {rocksdb_opts, [{write_buffer_size, 3145728, extra}]}),
    ok = meck:unload(mnesia_rocksdb),
    {atomic, ok} = Written,
    {Restarted, Warned} = capture_log(warning, "legacy_opts", fun() -> restart_and_wait([legacy_opts]) end),
    ct:log("restarted: ~p, warned: ~ts", [Restarted, Warned]),
    ok = Restarted,
    ok = mnesia:dirty_write({legacy_opts, 1, one}),
    {atomic, ok} = mnesia:delete_table(legacy_opts),
    true = string:find(Warned, "default options") =/= nomatch,
    ok.

%% A property written to a standalone table reaches its ref, as one written to a column
%% family table does.
standalone_table_follows_its_written_properties(_Config) ->
    {atomic, ok} = mnesia:create_table(standalone_props, [{rdb, [node()]}, {attributes, [k, v]},
                                                          {user_properties, [{rocksdb_standalone, true}]}]),
    {atomic, ok} = mnesia:write_table_property(standalone_props, {owner, maria}),
    Followed = try_until({owner, maria}, fun() -> maps:get(owner, admin_user_properties(standalone_props), none) end),
    {atomic, ok} = mnesia:delete_table(standalone_props),
    ok = Followed,
    ok.

%% Removing an alias closes its instance: no ref of its tables may still lead there.
removed_alias_leaves_no_table_refs_behind(_Config) ->
    {ok, rdb_gone} = mnesia_rocksdb:register(rdb_gone),
    {atomic, ok} = mnesia:create_table(gone_tab, [{rdb_gone, [node()]}, {attributes, [k, v]}, {index, [v]}]),
    #{db_ref := _} = mrdb:get_ref(gone_tab),
    ok = mnesia_rocksdb:remove_aliases([rdb_gone]),
    Left = [mnesia_rocksdb_admin:get_ref(Tab, gone) || Tab <- [gone_tab, {gone_tab, index, {3, ordered}}]],
    ct:log("left: ~p", [Left]),
    [gone, gone] = Left,
    ok.

%% Compaction options in default_rocksdb_opts or alias_rocksdb_opts reach no column family:
%% a table's own rocksdb_opts carry them. An instance opened with them says so.
compaction_options_of_an_instance_are_reported_as_unused(_Config) ->
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{rdb_compacting, [{max_open_files, -1}, {ttl, 3600}]} | Aliases]),
    {Registered, Warned} = capture_log(warning, "rdb_compacting", fun() -> mnesia_rocksdb:register(rdb_compacting) end),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    ct:log("warned: ~ts", [Warned]),
    {ok, rdb_compacting} = Registered,
    true = string:find(Warned, "ttl") =/= nomatch,
    ok.

%% The index rule can be relaxed with {fifo_index_rule, warn}: tables breaking it are then
%% accepted with a warning. Back on the default, an instance holding such a table refuses to
%% open and its error names the escape hatch; with warn it opens again, warning about the table.
fifo_index_rule_refusal_points_to_the_escape_hatch_and_warn_starts_anyway(_Config) ->
    ok = application:set_env(mnesia_rocksdb, fifo_index_rule, warn),
    {atomic, ok} = mnesia:create_table(tolerated_index, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                         {user_properties, [{rocksdb_opts, fifo_opts(?LARGE_FIFO)}]}]),
    ok = application:unset_env(mnesia_rocksdb, fifo_index_rule),
    mnesia:stop(),
    {_, Refused} = capture_log(error, "Cannot load admin db for alias rdb_traffic", fun mnesia:start/0),
    ok = await_restartable_mnesia(),
    ok = application:set_env(mnesia_rocksdb, fifo_index_rule, warn),
    {ok, Warned} = capture_log(warning, "tolerated_index", fun() -> ok = mnesia:start(), mnesia:wait_for_tables([tolerated_index], 10000) end),
    ok = mnesia:dirty_write({tolerated_index, 1, one}),
    {atomic, ok} = mnesia:delete_table(tolerated_index),
    ok = application:unset_env(mnesia_rocksdb, fifo_index_rule),
    ct:log("refused: ~ts~nwarned: ~ts", [Refused, Warned]),
    true = string:find(compact(Refused), "{fifo_with_index_requires_ttl_and_no_size_cap,tolerated_index}") =/= nomatch,
    true = string:find(compact(Refused), "{fifo_index_rule,warn}") =/= nomatch,
    true = string:find(Warned, "fifo_with_index_requires_ttl_and_no_size_cap") =/= nomatch,
    ok.

compact(Text) ->
    re:replace(Text, "\\s+", "", [global, {return, list}]).

restart_and_wait(Tabs) ->
    mnesia:stop(),
    ok = mnesia:start(),
    mnesia:wait_for_tables(Tabs, 10000).

%% Restarts mnesia with AliasOpts for the traffic alias, which make its instance refuse to
%% reopen, and returns what is reported; mnesia is then back with the group's alias options.
reopen_refused(AliasOpts) ->
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    mnesia:stop(),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{?TRAFFIC, AliasOpts}]),
    {_, Reported} = capture_log(error, "Cannot load admin db for alias", fun mnesia:start/0),
    ok = await_restartable_mnesia(),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    ok = mnesia:start(),
    ct:log("reported: ~ts", [Reported]),
    Reported.

%% Runs Fun while logs of Level are captured; returns its result and the first log text
%% containing Needle, or nothing_reported after Timeout.
capture_log(Level, Needle, Fun) ->
    capture_log(Level, Needle, 10000, Fun).

capture_log(Level, Needle, Timeout, Fun) ->
    ok = logger:add_handler(captured_log, ?MODULE, #{level => Level, config => #{pid => self()}}),
    Result = Fun(),
    Text = receive_log(fun(T) -> string:find(T, Needle) =/= nomatch end, Timeout),
    ok = logger:remove_handler(captured_log),
    {Result, Text}.

await_restartable_mnesia() ->
    Admin = monitor(process, mnesia_rocksdb_admin),
    receive {'DOWN', Admin, process, _, _} -> ok after 30000 -> error(admin_still_up) end,
    ok = try_until(false, fun() -> lists:keymember(mnesia, 1, application:which_applications()) end, 100),
    mnesia:stop(),
    ok.

cf_section(MP, CfPrefix) ->
    {ok, CFs} = rocksdb:list_column_families(MP, []),
    [Cf] = [CF || CF <- CFs, lists:prefix(CfPrefix, CF)],
    cf_options_section(latest_options_file(MP), Cf).

cf_is_fifo(MP, CfPrefix, Size) ->
    Section = cf_section(MP, CfPrefix),
    ct:log("~s options: ~s", [CfPrefix, Section]),
    re:run(Section, <<"compaction_style=kCompactionStyleFIFO">>) =/= nomatch
        andalso re:run(Section, ["max_table_files_size=", integer_to_list(Size), "[;}]"]) =/= nomatch.

%% Options given both in default_rocksdb_opts and for the alias are the alias' own, also
%% the ones that are rewritten before RocksDB gets them: an alias asking for statistics
%% gets a statistics object, not the raw <<"create">> that RocksDB cannot take.
alias_options_win_also_where_they_are_rewritten(_Config) ->
    {ok, Defaults} = application:get_env(mnesia_rocksdb, default_rocksdb_opts),
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, [{statistics, <<"create">>} | Defaults]),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, [{rdb_stats, [{statistics, <<"create">>}]} | Aliases]),
    {ok, rdb_stats} = mnesia_rocksdb:register(rdb_stats),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, Defaults),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    #{db_ref := _} = mrdb:get_ref({admin, rdb_stats}),
    nomatch = re:run(admin_log(rdb_stats), <<"Options.statistics: \\(nil\\)">>),
    {match, _} = re:run(admin_log(rdb_stats), <<"Options.statistics: 0x">>),
    ok.

%% Nested options merge across the layers: an alias that overrides only block_size of the
%% defaults' block_based_table_options keeps their block_cache_size, so it still gets the
%% node-wide shared cache of that size.
alias_overriding_one_table_option_keeps_the_shared_cache(_Config) ->
    {ok, Defaults} = application:get_env(mnesia_rocksdb, default_rocksdb_opts),
    {ok, Aliases} = application:get_env(mnesia_rocksdb, alias_rocksdb_opts),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts,
                             [{block_based_table_options, [{block_cache_size, 12582912}, {block_size, 4096}]} | Defaults]),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts,
                             [{rdb_bbt, [{block_based_table_options, [{block_size, 16384}]}]} | Aliases]),
    {ok, rdb_bbt} = mnesia_rocksdb:register(rdb_bbt),
    ok = application:set_env(mnesia_rocksdb, default_rocksdb_opts, Defaults),
    ok = application:set_env(mnesia_rocksdb, alias_rocksdb_opts, Aliases),
    #{db_ref := Db, mountpoint := MP} = mrdb:get_ref({admin, rdb_bbt}),
    {ok, Capacity} = rocksdb:get_property(Db, <<"rocksdb.block-cache-capacity">>),
    ct:log("block cache capacity: ~s", [Capacity]),
    <<"12582912">> = Capacity,
    {match, _} = re:run(latest_options_file(MP), <<"block_size=16384">>),
    ok.

%% An instance RocksDB refuses to reopen (here its WAL directory cannot be created) stops,
%% and mnesia says why, naming RocksDB's reason and the tables with options of their own,
%% instead of crashing on an unexpected open result.
alias_db_that_cannot_reopen_names_the_cause(_Config) ->
    {atomic, ok} = mnesia:create_table(own_opts_victim, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                                         {user_properties, [{rocksdb_opts, [{write_buffer_size, 3145728}]}]}]),
    Reported = reopen_refused([{max_open_files, -1}, {wal_dir, "/proc/nonexistent/wal"}]),
    ok = mnesia:wait_for_tables([own_opts_victim], 10000),
    {atomic, ok} = mnesia:delete_table(own_opts_victim),
    true = string:find(Reported, "/proc/nonexistent/wal") =/= nomatch,
    true = string:find(compact(Reported), "tables_with_own_options=>[{own_opts_victim,") =/= nomatch,
    ok.

%% A FIFO table, with indexes or not, makes an instance without max_open_files = -1 refuse to
%% open, naming the rule and the table before RocksDB is asked to open anything.
alias_db_refuses_to_open_with_a_fifo_table_its_instance_cannot_hold(_Config) ->
    {atomic, ok} = mnesia:create_table(fifo_victim, [{?TRAFFIC, [node()]}, {attributes, [k, v]},
                                                     {user_properties, [{rocksdb_opts, fifo_opts(?SMALL_FIFO)}]}]),
    Reported = reopen_refused([]),
    ok = mnesia:wait_for_tables([fifo_victim], 10000),
    {atomic, ok} = mnesia:delete_table(fifo_victim),
    true = string:find(compact(Reported), "{fifo_requires_max_open_files_unlimited,fifo_victim}") =/= nomatch,
    ok.

%% A table with indexes breaking the FIFO rules makes its instance refuse to open, naming the
%% rule and the table: here a FIFO table with an index, once the alias has lost
%% max_open_files = -1. It is caught before RocksDB is asked to open anything.
alias_db_refuses_to_open_with_an_indexed_table_breaking_the_fifo_rules(_Config) ->
    {atomic, ok} = mnesia:create_table(indexed_victim, [{?TRAFFIC, [node()]}, {attributes, [k, v]}, {index, [v]},
                                                        {user_properties, [{rocksdb_opts, [{ttl, 3600} | fifo_opts(infinity)]}]}]),
    Reported = reopen_refused([]),
    ok = mnesia:wait_for_tables([indexed_victim], 10000),
    {atomic, ok} = mnesia:delete_table(indexed_victim),
    true = string:find(compact(Reported), "{fifo_requires_max_open_files_unlimited,indexed_victim}") =/= nomatch,
    ok.

log(#{msg := Msg}, #{config := #{pid := Pid}}) ->
    Pid ! {captured_log, log_text(Msg)},
    ok.

log_text({string, Chars}) -> unicode:characters_to_list(Chars);
log_text({report, #{format := Format, args := Args}}) -> lists:flatten(io_lib:format(Format, Args));
log_text({report, Report}) -> lists:flatten(io_lib:format("~p", [Report]));
log_text({Format, Args}) -> lists:flatten(io_lib:format(Format, Args)).

receive_log(Wanted, Timeout) ->
    receive
        {captured_log, Text} ->
            case Wanted(Text) of
                true -> Text;
                false -> receive_log(Wanted, Timeout)
            end
    after Timeout -> nothing_reported
    end.

traffic_tabs() ->
    [{traffic_wp, ?SMALL_FIFO}, {traffic_ws, ?LARGE_FIFO}].

traffic_names() ->
    [T || {T, _} <- traffic_tabs()].

fifo_opts(Size) ->
    [{compaction_style, fifo}, {compaction_options_fifo, [{max_table_files_size, Size}]}].

cf_name(T) ->
    lists:flatten(io_lib:fwrite("~w", [{d, T}])).

admin_log(Alias) ->
    Log = filename:join(mnesia_rocksdb_lib:data_mountpoint({admin, Alias}), "LOG"),
    {ok, Contents} = file:read_file(Log),
    Contents.

%% Each round is a flushed sst file of roughly 100 KB of incompressible values per table.
fill_traffic_tabs(From, To) ->
    lists:foreach(
      fun(R) ->
              [ok = mnesia:dirty_write({T, {R, N}, crypto:strong_rand_bytes(1024)})
               || T <- traffic_names(), N <- lists:seq(1, ?FIFO_ROUND_SIZE)],
              [flush(T) || T <- traffic_names()]
      end, lists:seq(From, To)).

flush(T) ->
    #{db_ref := Db, cf_handle := Cf} = mrdb:get_ref(T),
    ok = rocksdb:flush(Db, Cf, [{wait, true}]).

all_present(T, From, To) ->
    [[_] = mnesia:dirty_read(T, {R, N}) || R <- lists:seq(From, To),
                                          N <- lists:seq(1, ?FIFO_ROUND_SIZE)],
    ok.

%% RocksDB records the options each column family was last opened with in its newest
%% OPTIONS file.
check_fifo_options() ->
    #{mountpoint := MP} = mrdb:get_ref({admin, ?TRAFFIC}),
    [true = cf_is_fifo(MP, cf_name(T), Size) || {T, Size} <- traffic_tabs()],
    ok.

latest_options_file(MP) ->
    {ok, Files} = file:list_dir(MP),
    Numbered = [{list_to_integer(N), F} || "OPTIONS-" ++ N = F <- Files,
                                           re:run(N, "^[0-9]+$") =/= nomatch],
    {_, Latest} = lists:max(Numbered),
    {ok, Bin} = file:read_file(filename:join(MP, Latest)),
    Bin.

cf_options_section(Options, CfName) ->
    Header = iolist_to_binary(["[CFOptions \"", CfName, "\"]"]),
    [_, Rest] = binary:split(Options, Header),
    hd(binary:split(Rest, <<"\n[CFOptions">>)).
