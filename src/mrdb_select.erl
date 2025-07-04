%% -*- mode: erlang; erlang-indent-level: 4; indent-tabs-mode: nil -*-
-module(mrdb_select).

-export([ select/3       %% (Ref, MatchSpec, Limit)
        , select/4       %% (Ref, MatchSpec, AccKeys, Limit)
        , select_reverse/3
        , select_reverse/4
        , select/1       %% (Cont)
        , fold/5         %% (Ref, Fun, Acc, MatchSpec, Limit)
        , fold_reverse/5
        , rdb_fold/5     %% (Ref, Fun, Acc, Prefix, Limit)
        , rdb_fold_reverse/5 %% (Ref, Fun, Acc, Prefix, Limit)
        ]).

-export([continuation_info/2]).

-import(mnesia_rocksdb_lib, [ keypos/1
                            , decode_key/2
                            , decode_val/3
                            ]).

-include("mnesia_rocksdb.hrl").

-record(sel, { alias                            % TODO: not used
             , tab
             , ref
             , keypat
             , ms                               % TODO: not used
             , compiled_ms
             , limit
             , key_only = false                 % TODO: not used
             , direction = forward
             , pre_ms
             , derive_obj_f = fun unit_l/1
             }).

select(Ref, MS, Limit) when is_map(Ref), is_list(MS) ->
    select(Ref, MS, false, forward, Limit).

select(Ref, MS, AccKeys, Limit) ->
    select(Ref, MS, AccKeys, forward, Limit).

select_reverse(Ref, MS, Limit) ->
    select(Ref, MS, false, reverse, Limit).

select_reverse(Ref, MS, AccKeys, Limit) ->
    select(Ref, MS, AccKeys, reverse, Limit).

select(Ref, MS, AccKeys, Dir, Limit)
  when is_map(Ref), is_list(MS), is_boolean(AccKeys) ->
    Sel = mk_sel(Ref, MS, Dir, Limit),
    mrdb:with_rdb_iterator(Ref, fun(I) -> i_select(I, Sel, AccKeys, []) end).

mk_sel(#{name := Tab} = Ref, MS, Dir, Limit) ->
    MSpre = maps:get(pre_ms, Ref, MS),
    Keypat = keypat(MSpre, keypos(Tab), Ref),
    #sel{tab = Tab,
         ref = Ref,
         keypat = Keypat,
         ms = MSpre,
         pre_ms = MSpre,
         compiled_ms = ms_compile(MS),
         key_only = needs_key_only(MS),
         direction = Dir,
         limit = Limit,
         derive_obj_f = derive_f(Ref)}.

select(Cont) ->
    case Cont of
        '$end_of_table' -> '$end_of_table';
        _ when is_function(Cont, 1) ->
            Cont(cont)
    end.

continuation_info(Item, C) when is_atom(Item), is_function(C, 1) ->
    continuation_info_(Item, C(sel));
continuation_info(_, _) -> undefined.

continuation_info_(ref,       #sel{ref       = Ref}) -> Ref;
continuation_info_(ms,        #sel{ms        = MS }) -> MS;
continuation_info_(pre_ms,    #sel{pre_ms    = MSp}) -> MSp;
continuation_info_(limit,     #sel{limit     = L  }) -> L;
continuation_info_(direction, #sel{direction = Dir}) -> Dir;
continuation_info_(_, _) -> undefined.

fold(Ref, Fun, Acc, MS, Limit) ->
    do_fold(Ref, Fun, Acc, MS, forward, Limit).

fold_reverse(Ref, Fun, Acc, MS, Limit) ->
    do_fold(Ref, Fun, Acc, MS, reverse, Limit).

do_fold(Ref, Fun, Acc, MS, Dir, Limit) ->
   {AccKeys, F} =
        if is_function(Fun, 3) ->
                {true, fun({K, Obj}, Acc1) ->
                               Fun(Obj, K, Acc1)
                       end};
           is_function(Fun, 2) ->
                {false, Fun};
           true ->
                mrdb:abort(invalid_fold_fun)
        end,
    fold_(select(Ref, MS, AccKeys, Dir, Limit), F, Acc).

fold_('$end_of_table', _, Acc) ->
    Acc;
fold_(L, Fun, Acc) when is_list(L) ->
    lists:foldl(Fun, Acc, L);
fold_({L, Cont}, Fun, Acc) ->
    fold_(select(Cont), Fun, lists:foldl(Fun, Acc, L)).

rdb_fold(Ref, Fun, Acc, Prefix, Limit) ->
    mrdb:with_rdb_iterator(
      Ref, fun(I) ->
                   MovRes = fwd_init_seek(I, Prefix),
                   i_rdb_fold(MovRes, I, Prefix, Fun, Acc, Limit)
           end).

rdb_fold_reverse(Ref, Fun, Acc, Prefix, Limit) ->
    mrdb:with_rdb_iterator(
      Ref, fun(I) ->
                   MovRes = rev_init_seek(I, Prefix),
                   i_rdb_fold_reverse(MovRes, I, Prefix, Fun, Acc, Limit)
           end).

fwd_init_seek(I, Pfx) ->
    rocksdb:iterator_move(I, fwd_init_seek_tgt(Pfx)).

fwd_init_seek_tgt(<<>>  ) -> first;
fwd_init_seek_tgt(Prefix) -> {seek, Prefix}.

rev_init_seek(I, Pfx) ->
    case rev_init_seek_tgt(Pfx) of
        last ->
            i_move(I, last);
        {seek, Bin} ->
            %% An 'incremented' prefix.
            %% This will fail if we seek past the end of the table.
            %% Then, try to seek_for_prev instead (fails if table empty).
            %% This because rocksdb lacks a "seek backward to last matching prefix".
            case i_move(I, {seek, Bin}) of
                {error, invalid_iterator} ->
                    i_move(I, {seek_for_prev, Bin});
                {ok, _, _} = Ok ->
                    Ok
            end
    end.

rev_init_seek_tgt(<<>>) -> last;
rev_init_seek_tgt(Prefix) ->
    case incr_prefix(Prefix) of
        last -> last;
        Pfx1 when is_binary(Pfx1) ->
            {seek, Pfx1}
    end.

incr_prefix(<<>>) -> last;
incr_prefix(Pfx) when is_binary(Pfx) ->
    PfxI = binary:decode_unsigned(Pfx),
    MaxI = (1 bsl (byte_size(Pfx) * 8)) - 1,
    case PfxI + 1 of
        I1 when I1 >= MaxI -> last;
        I1 ->
            binary:encode_unsigned(I1)
    end.

i_rdb_fold({ok, K, V}, I, Pfx, Fun, Acc, Limit) when Limit > 0 ->
    case is_prefix(Pfx, K) of
        true ->
            i_rdb_fold(rocksdb:iterator_move(I, next), I, Pfx, Fun,
                       Fun(K, V, Acc), decr(Limit));
        false ->
            Acc
    end;
i_rdb_fold(_, _, _, _, Acc, _) ->
    Acc.

i_rdb_fold_reverse({ok, K, V}, I, Pfx, Fun, Acc, Limit) when Limit > 0 ->
    case is_prefix(Pfx, K) of
        true ->
            i_rdb_fold_reverse(rocksdb:iterator_move(I, prev), I, Pfx, Fun,
                           Fun(K, V, Acc), decr(Limit));
        false when K > Pfx ->
            i_rdb_fold_reverse(rocksdb:iterator_move(I, prev), I, Pfx, Fun, Acc, Limit);
        false ->
            Acc
    end;
i_rdb_fold_reverse(_, _, _, _, Acc, _) ->
    Acc.

i_select(I, #sel{ keypat = Pfx
                , compiled_ms = MS
                , limit = Limit
                , direction = Dir
                , ref = #{encoding := Enc} } = Sel0, AccKeys, Acc) ->
    {MoveRes, Sel} = case Enc of
                         {term, _} ->
                              %% No defined ordering - do forward select
                             {i_move(I, first), Sel0#sel{direction = forward}};
                         _ ->
                             case Dir of
                                 forward ->
                                     {fwd_init_seek(I, Pfx), Sel0};
                                 reverse ->
                                     {rev_init_seek(I, Pfx), Sel0}
                             end
                     end,
    select_traverse(MoveRes, Limit, Pfx, MS, I, Sel, AccKeys, Acc).

needs_key_only([Pat]) ->
    needs_key_only_(Pat);
needs_key_only([_|_] = Pats) ->
    lists:all(fun needs_key_only_/1, Pats).

needs_key_only_({HP, _, Body}) ->
    BodyVars = lists:flatmap(fun extract_vars/1, Body),
    %% Note that we express the conditions for "needs more than key" and negate.
    not(wild_in_body(BodyVars) orelse
        case bound_in_headpat(HP) of
            {all,V} -> lists:member(V, BodyVars);
            Vars when is_list(Vars) -> any_in_body(lists:keydelete(2,1,Vars), BodyVars)
        end).

extract_vars([H|T]) ->
    extract_vars(H) ++ extract_vars(T);
extract_vars(T) when is_tuple(T) ->
    extract_vars(tuple_to_list(T));
extract_vars(T) when T=='$$'; T=='$_' ->
    [T];
extract_vars(T) when is_atom(T) ->
    case is_wild(T) of
        true ->
            [T];
        false ->
            []
    end;
extract_vars(_) ->
    [].

any_in_body(Vars, BodyVars) ->
    lists:any(fun({_,Vs}) ->
                      intersection(Vs, BodyVars) =/= []
              end, Vars).

intersection(A,B) when is_list(A), is_list(B) ->
    A -- (A -- B).

is_wild('_') ->
    true;
is_wild(A) when is_atom(A) ->
    case atom_to_list(A) of
        "\$" ++ S ->
            try begin
                    _ = list_to_integer(S),
                    true
                end
            catch
                error:_ ->
                    false
            end;
        _ ->
            false
    end.

wild_in_body(BodyVars) ->
    intersection(BodyVars, ['$$','$_']) =/= [].

bound_in_headpat(HP) when is_atom(HP) ->
    {all, HP};
bound_in_headpat(HP) when is_tuple(HP) ->
    [_|T] = tuple_to_list(HP),
    map_vars(T, 2).

map_vars([H|T], P) ->
    case extract_vars(H) of
        [] ->
            map_vars(T, P+1);
        Vs ->
            [{P, Vs}|map_vars(T, P+1)]
    end;
map_vars([], _) ->
    [].

select_traverse({ok, K, V}, Limit, Pfx, MS, I, #sel{ref = R, direction = Dir} = Sel,
                AccKeys, Acc) ->
    case is_prefix(Pfx, K) of
        true ->
            DecKey = decode_key(K, R),
            Rec0 = decode_val(V, DecKey, R),
            RecL = derive_object(Rec0, Sel),
            case ms_run(RecL, MS) of
                [] ->
                    select_traverse(
                      rocksdb:iterator_move(I, next_or_prev(Dir)), Limit, Pfx, MS,
                      I, Sel, AccKeys, Acc);
                [Match] ->
                    Acc1 = if AccKeys ->
                                  [{K, Match}|Acc];
                              true ->
                                  [Match|Acc]
                           end,
                    traverse_continue(K, decr(Limit), Pfx, MS, I, Sel, AccKeys, Acc1)
            end;
        false when Dir == reverse, K > Pfx ->
            select_traverse(rocksdb:iterator_move(I, prev), Limit, Pfx, MS,
                            I, Sel, AccKeys, Acc);
        false when Limit == infinity ->
            lists:reverse(Acc);
        false ->
            {lists:reverse(Acc), '$end_of_table'}
    end;
select_traverse({error, _}, Limit, _, _, _, _, _, Acc) ->
    select_return(Limit, {lists:reverse(Acc), '$end_of_table'}).

next_or_prev(forward) -> next;
next_or_prev(reverse) -> prev.

select_return(infinity, {L, '$end_of_table'}) ->
    L;
select_return(_, Ret) ->
    Ret.

is_prefix(A, B) when is_binary(A), is_binary(B) ->
    Sa = byte_size(A),
    case B of
        <<A:Sa/binary, _/binary>> ->
            true;
        _ ->
            false
    end.

decr(I) when is_integer(I) ->
    I-1;
decr(infinity) ->
    infinity.

traverse_continue(K, 0, Pfx, MS, _I, #sel{limit = Limit, ref = Ref, direction = Dir} = Sel, AccKeys, Acc) ->
    {lists:reverse(Acc),
     fun(sel) -> Sel;
        (cont) ->
             mrdb:with_rdb_iterator(
               Ref,
               fun(NewI) ->
                       select_traverse(iterator_next(NewI, K, Dir),
                                       Limit, Pfx, MS, NewI, Sel,
                                       AccKeys, [])
               end)
     end};
traverse_continue(_K, Limit, Pfx, MS, I, #sel{direction = Dir} = Sel, AccKeys, Acc) ->
    select_traverse(rocksdb:iterator_move(I, next_or_prev(Dir)), Limit, Pfx, MS, I, Sel, AccKeys, Acc).

iterator_next(I, K, Dir) ->
    case i_move(I, K, Dir) of
        {ok, K, _} ->
            rocksdb:iterator_move(I, next_or_prev(Dir));
        Other ->
            Other
    end.

i_move(I, Tgt) ->
    rocksdb:iterator_move(I, Tgt).

i_move(I, K, reverse) ->
    rocksdb:iterator_move(I, {seek_for_prev, K});
i_move(I, K, forward) ->
    rocksdb:iterator_move(I, K).

derive_object(R, #sel{derive_obj_f = F}) ->
    F(R).

keypat([H|T], KeyPos, Ref) ->
    keypat(T, KeyPos, Ref, keypat_pfx(H, KeyPos, Ref)).

keypat(_, _, _, <<>>) -> <<>>;
keypat([H|T], KeyPos, Ref, Pfx0) ->
    Pfx = keypat_pfx(H, KeyPos, Ref),
    keypat(T, KeyPos, Ref, common_prefix(Pfx, Pfx0));
keypat([], _, _, Pfx) ->
    Pfx.

common_prefix(<<H, T/binary>>, <<H, T1/binary>>) ->
    <<H, (common_prefix(T, T1))/binary>>;
common_prefix(_, _) ->
    <<>>.

keypat_pfx({HeadPat,_Gs,_}, KeyPos, #{encoding := {sext,_}}) when is_tuple(HeadPat) ->
    KP      = element(KeyPos, HeadPat),
    sext:prefix(KP);
keypat_pfx(_, _, _) ->
    <<>>.

derive_f(#{derive_obj_f := F}) when is_function(F, 1) -> F;
derive_f(_) -> fun unit_l/1.

unit_l(X) ->
    [X].

ms_compile(MS) ->
  ets:match_spec_compile(MS).

ms_run(RecL, MS) ->
    ets:match_spec_run(RecL, MS).
