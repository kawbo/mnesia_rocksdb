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

-export([
          no_prefix_fwd_rdb_fold/1
        , prefixed_fwd_rdb_fold/1
        , no_prefix_rev_rdb_fold/1
        , prefixed_rev_rdb_fold/1
        , prefixed_rev_rdb_fold_max/1
        , fwd_fold/1
        , filtered_fwd_fold/1
        , rev_fold/1
        , filtered_rev_fold/1
        , fwd_select/1
        , rev_select/1
        , select_cont/1
        , rev_select_cont/1
        ]).

-include_lib("common_test/include/ct.hrl").

-record(r, {k, v}).

suite() ->
    [].

all() ->
    [{group, all_tests}].

groups() ->
    [
      {all_tests, [sequence], [ {group, rdb_fold}
                              , {group, fold}
                              , {group, select} ]}
    , {rdb_fold, [sequence], [ no_prefix_fwd_rdb_fold
                             , prefixed_fwd_rdb_fold
                             , no_prefix_rev_rdb_fold
                             , prefixed_rev_rdb_fold
                             , prefixed_rev_rdb_fold_max ]}
    , {fold, [sequence], [ fwd_fold
                         , filtered_fwd_fold
                         , rev_fold
                         , filtered_rev_fold ]}
    , {select, [sequence], [ fwd_select
                           , rev_select
                           , select_cont
                           , rev_select_cont ]}
    ].

init_per_suite(Config) ->
    mnesia:stop(),
    ok = mnesia_rocksdb_tlib:start_mnesia(reset),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

init_per_group(G, Config) when G==rdb_fold; G==fold ->
    mk_tab(G),
    Config;
init_per_group(_, Config) ->
    Config.

end_per_group(_, _Config) ->
    ok.

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, _Config) ->
    ok.

mk_tab(G) ->
    T = tab_name(G),
    case create_tab(T) of
        {atomic, ok} -> fill_tab(T);
        {aborted,{already_exists,T}} -> ok
    end.

tab_name(fold    ) -> r;
tab_name(select  ) -> r;
tab_name(rdb_fold) -> t.

create_tab(T) ->
    Opts = tab_opts(T),
    mnesia:create_table(T, [{rdb, [node()]} | Opts]).

tab_opts(r) ->
    [{attributes, [k, v]}, {type, ordered_set}];
tab_opts(t) ->
    [{attributes, [k, v]}, {user_properties, [{mrdb_encoding, {raw, raw}}]}].

no_prefix_fwd_rdb_fold(_Config) ->
    Res = mrdb:rdb_fold(t, fun simple_rdb_acc/3, [], <<>>, infinity),
    Expected = lists:reverse(raw_objs()),
    {Res, Res} = {Res, Expected}.

fwd_fold(_Config) ->
    Res = mrdb:fold(r, fun simple_acc/2, []),
    Expected = lists:reverse(objs()),
    {Res, Res} = {Res, Expected}.

prefixed_fwd_rdb_fold(_Config) ->
    Pfx = <<"aa">>,
    Res = mrdb:rdb_fold(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = lists:reverse(prefixed_raw_objs(Pfx)),
    {Res, Res} = {Res, Expected}.

filtered_fwd_fold(_Config) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Res = mrdb:fold(r, fun simple_acc/2, [], MS, infinity),
    Expected = lists:reverse(filtered_objs(MS)),
    {Res, Res} = {Res, Expected}.

no_prefix_rev_rdb_fold(_Config) ->
    Res = mrdb:rdb_fold_reverse(t, fun simple_rdb_acc/3, [], <<>>, infinity),
    Expected = raw_objs(),
    {Res, Res} = {Res, Expected}.

rev_fold(_Config) ->
    Res = mrdb:fold_reverse(r, fun simple_acc/2, []),
    Expected = objs(),
    {Res, Res} = {Res, Expected}.

prefixed_rev_rdb_fold(_Config) ->
    Pfx = <<"aa">>,
    Res = mrdb:rdb_fold_reverse(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = prefixed_raw_objs(Pfx),
    {Res, Res} = {Res, Expected}.

filtered_rev_fold(_Config) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Res = mrdb:fold_reverse(r, fun simple_acc/2, [], MS, infinity),
    Expected = filtered_objs(MS),
    {Res, Res} = {Res, Expected}.

prefixed_rev_rdb_fold_max(_Config) ->
    Pfx = <<255,255>>,
    Res = mrdb:rdb_fold_reverse(t, fun simple_rdb_acc/3, [], Pfx, infinity),
    Expected = prefixed_raw_objs(Pfx),
    {Res, Res} = {Res, Expected}.

fwd_select(_Config) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Res = mrdb:select(r, MS),
    Expected = filtered_objs(MS),
    {Res, Res} = {Res, Expected}.

rev_select(_Config) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Res = mrdb:select_reverse(r, MS),
    Expected = lists:reverse(filtered_objs(MS)),
    {Res, Res} = {Res, Expected}.

select_cont(_Cont) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Expected = filtered_objs(MS),
    select_cont_loop(mrdb:select(r, MS, 1), Expected).

rev_select_cont(_Cont) ->
    MS = [{#r{k = {a,b,'_'}, v = '_'}, [], ['$_']}],
    Expected = lists:reverse(filtered_objs(MS)),
    select_cont_loop(mrdb:select_reverse(r, MS, 1), Expected).

select_cont_loop({[Obj], Cont}, [Obj|Rest]) ->    
    select_cont_loop(mrdb:select(Cont), Rest);
select_cont_loop({[], '$end_of_table'}, []) ->
    ok.

simple_acc(#r{} = Obj, Acc) ->
    [Obj | Acc].

simple_rdb_acc(K, V, Acc) ->
    [{K,V} | Acc].

fill_tab(t = Tab) ->
    [mrdb:insert(Tab, {Tab, K, V}) || {K,V} <- raw_objs()],
    ok;
fill_tab(r = Tab) ->
    [mrdb:insert(Tab, Obj) || Obj <- objs()],
    ok.

prefixed_raw_objs(Pfx) ->
    [Obj || {K,_} = Obj <- raw_objs(),
            is_prefix(Pfx, K)].

raw_objs() ->
    [ {<<"aa">> , <<"1">>}
    , {<<"aa1">>, <<"2">>}
    , {<<"ab">> , <<"3">>}
    , {<<"ab1">>, <<"4">>}
    , {<<255,255>>, <<"5">>} ].

filtered_objs(MS) ->
    MSC = ets:match_spec_compile(MS),
    ets:match_spec_run(objs(), MSC).

objs() ->
    [ #r{k = {a,a,1}, v = 1}
    , #r{k = {a,b,2}, v = 2}
    , #r{k = {a,b,3}, v = 3}
    , #r{k = {a,c,4}, v = 4}
    , #r{k = {b,b,5}, v = 5}
    ].

%% copied from mrdb_select.erl
is_prefix(A, B) when is_binary(A), is_binary(B) ->
    Sa = byte_size(A),
    case B of
        <<A:Sa/binary, _/binary>> ->
            true;
        _ ->
            false
    end.    
