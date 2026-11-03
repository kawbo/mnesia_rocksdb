-module(mnesia_rocksdb_lib_tests).

-include_lib("eunit/include/eunit.hrl").

latest_wins_test_() ->
    [
        {"a later option overrides an earlier one with the same key",
            ?_assertEqual([{max_open_files, -1}, {block_size, 4096}],
                          mnesia_rocksdb_lib:latest_wins([{max_open_files, 123}, {block_size, 4096}, {max_open_files, -1}]))},
        {"nested block based table options merge: overriding one sub-key keeps the others",
            ?_assertEqual([{block_based_table_options, [{block_cache_size, 8388608}, {block_size, 16384}]}],
                          mnesia_rocksdb_lib:latest_wins([{block_based_table_options, [{block_cache_size, 8388608}, {block_size, 4096}]},
                                                          {block_based_table_options, [{block_size, 16384}]}]))},
        {"nested fifo options merge: a size override keeps allow_compaction",
            ?_assertEqual([{compaction_options_fifo, [{allow_compaction, true}, {max_table_files_size, 1024}]}],
                          mnesia_rocksdb_lib:latest_wins([{compaction_options_fifo, [{allow_compaction, true}]},
                                                          {compaction_options_fifo, [{max_table_files_size, 1024}]}]))},
        {"a nested option list is de-duplicated on its own, a later sub-option overriding an earlier one",
            ?_assertEqual([{compaction_options_fifo, [{max_table_files_size, 1048576}, {allow_compaction, true}]}],
                          mnesia_rocksdb_lib:latest_wins([{compaction_options_fifo, [{max_table_files_size, infinity},
                                                                                     allow_compaction,
                                                                                     {max_table_files_size, 1048576}]}]))},
        {"a bare atom is an option set to true, as in a proplist",
            ?_assertEqual([{use_bloomfilter, true}, {block_size, 4096}],
                          mnesia_rocksdb_lib:latest_wins([use_bloomfilter, {block_size, 4096}]))},
        {"other list values are replaced whole",
            ?_assertEqual([{db_paths, [b]}],
                          mnesia_rocksdb_lib:latest_wins([{db_paths, [a]}, {db_paths, [b]}]))}
    ].

unlimited_fifo_size_test_() ->
    ?_assertEqual([{compaction_options_fifo, [{max_table_files_size, 18446744073709551615}, {max_data_files_size, 18446744073709551615}]}],
                  mnesia_rocksdb_lib:unlimited_fifo_size([{compaction_options_fifo, [{max_table_files_size, infinity},
                                                                                     {max_data_files_size, infinity}]}])).

fifo_problem_test_() ->
    Db = [{max_open_files, -1}],
    [
        {"the rules judge the options the column family is built from: a later size cap overrides an earlier infinity",
            ?_assertEqual({error, fifo_with_index_requires_ttl_and_no_size_cap},
                          mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                           {compaction_options_fifo, [{max_table_files_size, infinity}]},
                                                           {compaction_options_fifo, [{max_table_files_size, 1048576}]}], true, Db))},
        {"the FIFO size cap judged is the one RocksDB applies, the last within the nested list",
            ?_assertEqual({error, fifo_with_index_requires_ttl_and_no_size_cap},
                          mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                           {compaction_options_fifo, [{max_table_files_size, infinity},
                                                                                      {max_table_files_size, 1048576}]}], true, Db))},
        {"a later ttl of 0 overrides an earlier positive one",
            ?_assertEqual({error, fifo_with_index_requires_ttl_and_no_size_cap},
                          mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                           {compaction_options_fifo, [{max_table_files_size, infinity}]}, {ttl, 0}], true, Db))},
        {"max_data_files_size caps FIFO in place of max_table_files_size",
            ?_assertEqual({error, fifo_with_index_requires_ttl_and_no_size_cap},
                          mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                           {compaction_options_fifo, [{max_table_files_size, infinity},
                                                                                      {max_data_files_size, 1048576}]}], true, Db))},
        {"a data size cap of 0 or infinity is off",
            [?_assertEqual(ok, mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                                 {compaction_options_fifo, [{max_table_files_size, infinity},
                                                                                            {max_data_files_size, Off}]}], true, Db))
             || Off <- [0, infinity]]},
        {"RocksDB's largest size is infinity",
            ?_assertEqual(ok, mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                                {compaction_options_fifo, [{max_table_files_size, 18446744073709551615}]}], true, Db))},
        {"an indexed FIFO table with a ttl and no size cap is fine",
            ?_assertEqual(ok, mnesia_rocksdb_lib:fifo_problem([{ttl, 3600}, {compaction_style, fifo},
                                                                {compaction_options_fifo, [{max_table_files_size, infinity}]}], true, Db))}
    ].
