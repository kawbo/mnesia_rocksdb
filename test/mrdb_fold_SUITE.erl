-module(mrdb_fold_SUITE).

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
        ]).

-export([ no_prefix_fwd_rdb_fold/1
        , prefixed_fwd_rdb_fold/1
        , no_prefix_rev_rdb_fold/1
        , prefixed_rev_rdb_fold/1
        , prefixed_rev_rdb_fold_max/1
        ]).

-include_lib("common_test/include/ct.hrl").

suite() ->
    [].

all() ->
    [{group, all_tests}].

groups() ->
    [
      {all_tests, [sequence], [ {group, rdb_fwd_fold}
                              , {group, rdb_rev_fold} ]}
    , {rdb_fwd_fold, [sequence], [ no_prefix_fwd_rdb_fold
                                 , prefixed_fwd_rdb_fold ]}
    , {rdb_rev_fold, [sequence], [ no_prefix_rev_rdb_fold
                                 , prefixed_rev_rdb_fold
                                 , prefixed_rev_rdb_fold_max ]}
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(G, Config) ->
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset),
    create_tab(t, G, [{type, ordered_set}]),
    fill_tab(t),
    Config.

end_per_group(_, _Config) ->
    ok.

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, _Config) ->
    ok.

create_tab(Tab, Grp, Opts) ->
    GOpts = case Grp of
                _ when Grp==rdb_fwd_fold; Grp==rdb_rev_fold ->
                    [{user_properties,
                      [{mrdb_encoding, {raw, raw}}]}];
                _ -> []
            end,
    {atomic, ok} = mnesia:create_table(Tab, [{rdb, [node()]} | GOpts ++ Opts]),
    ok.

no_prefix_fwd_rdb_fold(_Config) ->
    Res = mrdb:rdb_fold(t, fun simple_rdb_acc/3, [], <<>>, infinity),
    Expected = lists:reverse(objs()),
    {Res, Res} = {Res, Expected}.

prefixed_fwd_rdb_fold(_Config) ->
    Pfx = <<"aa">>,
    Res = mrdb:rdb_fold(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = lists:reverse(prefixed_objs(Pfx)),
    {Res, Res} = {Res, Expected}.

no_prefix_rev_rdb_fold(_Config) ->
    Res = mrdb:rdb_rev_fold(t, fun simple_rdb_acc/3, [], <<>>, infinity),
    Expected = objs(),
    {Res, Res} = {Res, Expected}.

prefixed_rev_rdb_fold(_Config) ->
    Pfx = <<"aa">>,
    Res = mrdb:rdb_rev_fold(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = prefixed_objs(Pfx),
    {Res, Res} = {Res, Expected}.

prefixed_rev_rdb_fold_max(_Config) ->
    Pfx = <<255,255>>,
    Res = mrdb:rdb_rev_fold(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = prefixed_objs(Pfx),
    {Res, Res} = {Res, Expected}.

simple_rdb_acc(K, V, Acc) ->
    [{K,V} | Acc].

fill_tab(Tab) ->
    [mrdb:insert(Tab, {Tab, K, V}) || {K,V} <- objs()],
    ok.

prefixed_objs(Pfx) ->
    [Obj || {K,_} = Obj <- objs(),
            is_prefix(Pfx, K)].

objs() ->
    [ {<<"aa">> , <<"1">>}
    , {<<"aa1">>, <<"2">>}
    , {<<"ab">> , <<"3">>}
    , {<<"ab1">>, <<"4">>}
    , {<<255,255>>, <<"5">>} ].

%% copied from mrdb_select.erl
is_prefix(A, B) when is_binary(A), is_binary(B) ->
    Sa = byte_size(A),
    case B of
        <<A:Sa/binary, _/binary>> ->
            true;
        _ ->
            false
    end.    
