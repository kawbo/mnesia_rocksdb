

# Mnesia Rocksdb - Rocksdb backend plugin for Mnesia #

Copyright (c) 2013-21 Klarna AB

__Authors:__ Ulf Wiger ([`ulf@wiger.net`](mailto:ulf@wiger.net)).

The Mnesia DBMS, part of Erlang/OTP, supports 'backend plugins', making
it possible to utilize more capable key-value stores than the `dets`
module (limited to 2 GB per table). Unfortunately, this support is
undocumented. Below, some informal documentation for the plugin system
is provided.


### <a name="Table_of_Contents">Table of Contents</a> ###


1. [Usage](#Usage)
1. [Prerequisites](#Prerequisites)
1. [Getting started](#Getting_started)
1. [Special features](#Special_features)
1. [Customization](#Customization)
1. [Caveats](#Caveats)

1. [Mnesia backend plugins](#Mnesia_backend_plugins)
1. [Background](#Background)
1. [Design](#Design)

1. [Mnesia index plugins](#Mnesia_index_plugins)

1. [Modules](#Modules)



### <a name="Usage">Usage</a> ###


#### <a name="Prerequisites">Prerequisites</a> ####

* rocksdb (included as dependency: the
  [kawbo/erlang-rocksdb](https://github.com/kawbo/erlang-rocksdb) fork, branch
  `master`, pinned in `rebar.lock`)

* sext (included as dependency)

* Erlang/OTP 23 or newer (https://github.com/erlang/otp)

The test suites need Erlang/OTP 25 or newer (one test starts a peer node), and
run on a distributed node (`dist_node` in `rebar.config`).



#### <a name="Getting_started">Getting started</a> ####

Call `mnesia_rocksdb:register()` immediately after
starting mnesia.

Put `{rocksdb_copies, [node()]}` into the table definitions of
tables you want to be in RocksDB.


#### <a name="Special_features">Special features</a> ####

RocksDB tables support efficient selects on _prefix keys_.

The backend uses the `sext` module (see
[`https://github.com/uwiger/sext`](https://github.com/uwiger/sext)) for mapping between Erlang terms and the
binary keys of `ordered_set` and `bag` tables. This provides two useful properties:

* The records are stored in the Erlang term order of their keys.

* A prefix of a composite key is ordered just before any key for which
  it is a prefix. For example, `{x, '_'}` is a prefix for keys `{x, a}`,`{x, b}` and so on.


This means that a prefix key identifies the start of the sequence of
entries whose keys match the prefix. The backend uses this to optimize
selects on prefix keys.

The keys of `set` tables are encoded with `term_to_binary` by default: they are
not stored in term order, and selects on them get no prefix optimization.

The encoding of a table can be chosen with the `mrdb_encoding` user property,
`{mrdb_encoding, {KeyEncoding, ValueEncoding}}`:

* `KeyEncoding`: `sext`, `term` or `raw` (the key, a binary, stored as is).
* `ValueEncoding`: for a table with two attributes (key and value),
  `{value, E}` or `raw`; for more attributes, `{object, E}`, where `E` is
  `term`, `sext` or `raw`. `term` and `sext` alone pick `value` or `object`
  from the attributes.

The defaults are `sext` keys for `ordered_set` and `bag`, `term` keys for
`set`, and `term` values (`{value, term}` or `{object, term}`). Prefix selects
are optimized only for `sext` keys.

### <a name="Customization">Customization</a> ###

#### Tables and instances

By default, all tables of one alias are column families in one RocksDB
instance, the alias' admin db, at
`<mnesia dir>/mnesia_rocksdb-<Alias>-_db.extrdb`.

A table with the user property `{rocksdb_standalone, true}` gets a RocksDB
instance of its own instead, at `<mnesia dir>/<Tab>-_tab.extrdb`; so do its
indexes (`<Tab>-<Pos>-_ix.extrdb`). With the OS environment variable
`MRDB_LEGACY=true`, every table is standalone.

A table that exists standalone on disk but is now defined as a column family
keeps using its standalone instance, unless it is listed in the application
env `auto_migrate_to_cf`, in which case its data is migrated into the alias'
instance when it is loaded. `mnesia_rocksdb_admin:migrate_standalone(Alias, Tabs)`
migrates tables on request.

#### Table options

RocksDB options of a table are given as a list named `rocksdb_opts` under
`user_properties`, for example:

```erlang
mnesia:create_table(foo, [{rocksdb_copies, [node()]},
                          ...
                          {user_properties,
                              [{rocksdb_opts, [{write_buffer_size, 67108864},
                                               {block_based_table_options,
                                                [{block_size, 16384}]}]}]
                          }])
```

`rocksdb_opts` are a proplist: `{Key, Value}` pairs, with a bare atom standing
for `{Atom, true}`. A later option overrides an earlier one with the same key;
`block_based_table_options` and `compaction_options_fifo` are merged the same
way, so overriding one of their sub-options keeps the others. A table whose
`rocksdb_opts` are malformed is refused with `{invalid_rocksdb_opts, Tab}`; a column
family table whose stored `rocksdb_opts` are malformed (written before they
were checked) is reopened with the defaults, with a warning.

The `rocksdb_opts` of a column family table carry column family options
(`compaction_style`, `compaction_options_fifo`, `ttl`,
`block_based_table_options`, `write_buffer_size`, `compression`, ...); DB-level
options in them (`max_open_files`, `max_background_jobs`, `statistics`, ...)
belong to the instance, which all tables of the alias share, and are ignored.
The `rocksdb_opts` of a standalone table carry both: the DB-level ones for its
own instance, the column family ones for its data.

Column family options are given again each time an instance is opened, so they
still apply after a restart.

Consult the [RocksDB documentation](https://github.com/facebook/rocksdb/wiki/Setup-Options-and-Basic-Tuning)
for information on configuration parameters.

The option names accepted are those of the erlang-rocksdb version mnesia_rocksdb
is compiled against (unknown ones are dropped, with a warning when an instance
is created); `compaction_options_fifo` needs a version that supports it, such
as the one in `rebar.config`.

#### Defaults

An instance is opened with `{create_if_missing, true}` and
`{max_open_files, 30}` under its own options. A table's column family gets
RocksDB's own defaults, under the table's `rocksdb_opts`, with mnesia_rocksdb's
merge operator.

The library's default list (`default_open_opts()` in `mnesia_rocksdb_lib.erl`)
also has `cache_size`, `block_size`,
`write_buffer_size`, `compression` and `use_bloomfilter` (some read from the OS
environment variables `ROCKSDB_CACHE_SIZE`, `ROCKSDB_WRITE_BUFFER_SIZE` and
`ROCKSDB_COMPRESSION`), but they reach no column family: when an instance is
opened, RocksDB reads only DB-level options from that list, and `cache_size`,
`block_size` and `use_bloomfilter` are not erlang-rocksdb options at all. Give
such options in a table's `rocksdb_opts` (`block_size` under
`block_based_table_options`).

#### Shared block cache

`{block_based_table_options, [{block_cache_size, Size}]}` makes a column family
use one native LRU cache of `Size` bytes for the whole node: every column
family and every standalone instance opened with the same size shares it, so
the size is the node's total budget rather than a per-table one. The cache is
kept in a persistent term, so it survives mnesia restarts within the VM.

#### <a name="Instances_and_DB_level_options">RocksDB instances and DB-level options</a>

The options of the alias instances come from the application environment:

* `default_rocksdb_opts` - applied to the instance of every alias.
* `alias_rocksdb_opts` - `[{Alias, Opts}]`, applied to the instance of `Alias`
  only, on top of `default_rocksdb_opts` (an option present in both takes the
  alias value).

Column family options in these lists apply to the admin db's own column
families, which hold the table metadata. Compaction options
(`compaction_style`, `compaction_options_fifo`, `ttl`) reach no column family,
so that metadata never ages out; a table takes them from its own
`rocksdb_opts`. An instance opened with them logs a warning.

To put some tables in an instance of their own, with DB-level options of its
own, register an extra alias for them and configure it. For example, FIFO
compaction, which RocksDB only accepts in an instance opened with
`{max_open_files, -1}`:

```erlang
%% sys.config
{mnesia_rocksdb, [{alias_rocksdb_opts, [{rocksdb_traffic_copies, [{max_open_files, -1}]}]}]}
```

```erlang
%% once, after mnesia has started (the alias is kept in the schema)
{ok, rocksdb_traffic_copies} = mnesia_rocksdb:register(rocksdb_traffic_copies),

mnesia:create_table(venue_traffic_wp,
                    [{rocksdb_traffic_copies, [node()]},
                     {attributes, [key, value]},
                     {user_properties,
                      [{rocksdb_opts, [{compaction_style, fifo},
                                       {compaction_options_fifo,
                                        [{max_table_files_size, 1073741824}]}]}]}]).
```

The environment is read every time an instance is opened, so it must be in
place at every start of mnesia, not only when the alias is registered. A
change to it takes effect when the instance is next opened: until then, tables
are checked against the options the running instance was opened with.

#### Indexes and retainers

An index takes from its table the options bounding how long data is kept
(`compaction_style`, `compaction_options_fifo`, `ttl`) and `max_open_files`,
which the index of a standalone table needs for an instance of its own. It
follows changes to them: a cleared or reopened index takes its table's current
options. A retainer keeps the defaults.

#### FIFO compaction

The FIFO rules are checked by every schema operation on a table
(`create_table`, `add_table_index`, `write_table_property`, ...), and again
before an alias' instance is opened:

* a FIFO table needs an instance with `{max_open_files, -1}`. The node running
  the schema operation judges every node holding the table against that node's
  own instance; a node it cannot reach judges the table itself when its
  instance opens. A standalone FIFO table needs `{max_open_files, -1}` in its
  own `rocksdb_opts`.
* a FIFO table with indexes must expire by age, `{ttl, T}` with `T > 0`, with
  its size caps off, `{max_table_files_size, infinity}` and
  `max_data_files_size` (which caps in its place when set) unset, `0` or
  `infinity`: under a size cap, the smaller index column family keeps entries
  of rows already dropped.

`infinity` stands for RocksDB's largest size, `18446744073709551615`.

A table breaking the index rule is refused, and an alias' instance holding one
does not open. `{mnesia_rocksdb, [{fifo_index_rule, warn}]}` accepts such
tables with a warning instead.

A column family left in an alias' instance by a table this node now stores in
another alias is reopened with the defaults, with a warning.

#### Access type

`{rocksdb_access_type, direct}` in a table's user properties makes mnesia's
reads and writes on it go to RocksDB from the calling process, instead of
through the table's server process (`legacy`, the default; the application
env `default_access_type` changes it). `bag` tables always use `legacy`.

#### Tuning

It is also possible, for larger databases, to produce a tuning parameter file.
This is experimental, and mostly copied from `mnesia_leveldb`. Consult the
source code in `mnesia_rocksdb_tuning.erl` and `mnesia_rocksdb_params.erl`.
Contributions are welcome.


#### <a name="Caveats">Caveats</a> ####

Avoid placing `bag` tables in RocksDB. Although they work, each write
requires additional reads, causing substantial runtime overheads. There
are better ways to represent and process bag data (see above about
_prefix keys_).

The `mnesia:table_info(T, size)` call returns RocksDB's estimate of the number
of keys (`rocksdb.estimate-num-keys`), not an exact count: RocksDB does not
track the number of elements in a table, and maintaining an exact counter
would force every write and delete to first read the key. If you depend on an
exact count, maintain it yourself, or traverse the table to count the
elements. `mnesia:table_info(T, memory)` returns the total size of the table's
SST files.

When `mrdb` transactions abort, they will return a stacktrace caught
from within the transaction fun, giving much better debugging info.
This is different from how mnesia does it.

If behavior closer to mnesia's abort returns are needed, say, for backwards
compatibility, this can be controlled by setting the environment variable
`-mnesia_rocksdb mnesia_compatible_aborts true`, or by adding a transaction
option, e.g. `mrdb:activity({tx, #{mnesia_compatible => true}}, fun() ... end)`.
For really performance-critical transactions which may abort often, it might
make a difference to set this option to `true`, since there is a cost involved
in producing stacktraces.


### <a name="Mnesia_backend_plugins">Mnesia backend plugins</a> ###


#### <a name="Background">Background</a> ####

Mnesia was initially designed to be a RAM-only DBMS, and Erlang's
`ets` tables were developed for this purpose. In order to support
persistence, e.g. for configuration data, a disk-based version of `ets`
(called `dets`) was created. The `dets` API mimicks the `ets` API,
and `dets` is quite convenient and fast for (nowadays) small datasets.
However, using a 32-bit bucket system, it is limited to 2GB of data.
It also doesn't support ordered sets. When used in Mnesia, dets-based
tables are called `disc_only_copies`.

To circumvent these limitations, another table type, called `disc_copies`
was added. This is a combination of `ets` and `disk_log`, where Mnesia
periodically snapshots the `ets` data to a log file on disk, and meanwhile
maintains a log of updates, which can be applied at startup. These tables
are quite performant (especially on read access), but all data is kept in
RAM, which can become a serious limitation.

A backend plugin system was proposed by Ulf Wiger in 2016, and further
developed with Klarna's support, to finally become included in OTP 19.
Klarna uses a LevelDb backend, but Aeternity, in 2017, instead chose
to implement a Rocksdb backend plugin.


### <a name="Design">Design</a> ###

As backend plugins were added on a long-since legacy-stable Mnesia,
they had to conform to the existing code structure. For this reason,
the plugin callbacks hook into the already present low-level access
API in the `mnesia_lib` module. As a consequence, backend plugins have
the same access semantics and granularity as `ets` and `dets`. This
isn't much of a disadvantage for key-value stores like LevelDb and RocksDB,
but a more serious issue is that the update part of this API is called
on _after_ the point of no return. That is, Mnesia does not expect
these updates to fail, and has no recourse if they do. As an aside,
this could also happen if a `disc_only_copies` table exceeds the 2 GB
limit (mnesia will not check it, and `dets` will not complain, but simply
drop the update.)


### <a name="Mnesia_index_plugins">Mnesia index plugins</a> ###

When adding support for backend plugins, index plugins were also added. Unfortunately, they remain undocumented.

An index plugin can be added in one of two ways:

1. When creating a schema, provide `{index_plugins, [{Name, Module, Function}]}` options.

1. Call the function `mnesia_schema:add_index_plugin(Name, Module, Function)`


`Name` must be an atom wrapped as a 1-tuple, e.g. `{words}`.

The plugin callback is called as `Module:Function(Table, Pos, Obj)`, where `Pos=={words}` in
our example. It returns a list of index terms.

<strong>Example</strong>

Given the following index plugin implementation:

```erlang
-module(words).
-export([words_f/3]).

words_f(_,_,Obj) when is_tuple(Obj) ->
    words_(tuple_to_list(Obj)).

words_(Str) when is_binary(Str) ->
    string:lexemes(Str, [$\s, $\n, [$\r,$\n]]);
words_(L) when is_list(L) ->
    lists:flatmap(fun words_/1, L);
words_(_) ->
    [].
```

We can register the plugin and use it in table definitions:

```erlang
Eshell V12.1.3  (abort with ^G)
1> mnesia:start().
ok
2> mnesia_schema:add_index_plugin({words}, words, words_f).
{atomic,ok}
3> mnesia:create_table(i, [{index, [{words}]}]).
{atomic,ok}
```

Note that in this case, we had neither a backend plugin, nor even a persistent schema.
Index plugins can be used with all table types. The registered indexing function (arity 3) must exist
as an exported function along the node's code path.

To see what happens when we insert an object, we can turn on call trace.

```erlang
4> dbg:tracer().
{ok,<0.108.0>}
5> dbg:tp(words, x).
{ok,[{matched,nonode@nohost,3},{saved,x}]}
6> dbg:p(all,[c]).
{ok,[{matched,nonode@nohost,60}]}
7> mnesia:dirty_write({i,<<"one two">>, [<<"three">>, <<"four">>]}).
(<0.84.0>) call words:words_f(i,{words},{i,<<"one two">>,[<<"three">>,<<"four">>]})
(<0.84.0>) returned from words:words_f/3 -> [<<"one">>,<<"two">>,<<"three">>,
                                             <<"four">>]
(<0.84.0>) call words:words_f(i,{words},{i,<<"one two">>,[<<"three">>,<<"four">>]})
(<0.84.0>) returned from words:words_f/3 -> [<<"one">>,<<"two">>,<<"three">>,
                                             <<"four">>]
ok
8> dbg:ctp('_'), dbg:stop().
ok
9> mnesia:dirty_index_read(i, <<"one">>, {words}).
[{i,<<"one two">>,[<<"three">>,<<"four">>]}]
```

(The fact that the indexing function is called twice, seems like a performance bug.)

We can observe that the indexing callback is able to operate on the whole object.
It needs to be side-effect free and efficient, since it will be called at least once for each update
(if an old object exists in the table, the indexing function will be called on it too, before it is
replaced by the new object.)


## <a name="Modules">Modules</a> ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="doc/mnesia_rocksdb.md" class="module">mnesia_rocksdb</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_admin.md" class="module">mnesia_rocksdb_admin</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_app.md" class="module">mnesia_rocksdb_app</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_lib.md" class="module">mnesia_rocksdb_lib</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_params.md" class="module">mnesia_rocksdb_params</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_sup.md" class="module">mnesia_rocksdb_sup</a></td></tr>
<tr><td><a href="doc/mnesia_rocksdb_tuning.md" class="module">mnesia_rocksdb_tuning</a></td></tr>
<tr><td><a href="doc/mrdb.md" class="module">mrdb</a></td></tr>
<tr><td><a href="doc/mrdb_index.md" class="module">mrdb_index</a></td></tr>
<tr><td><a href="doc/mrdb_mutex.md" class="module">mrdb_mutex</a></td></tr>
<tr><td><a href="doc/mrdb_select.md" class="module">mrdb_select</a></td></tr>
<tr><td>mrdb_mutex_serializer</td></tr>
<tr><td>mrdb_stats</td></tr>
<tr><td>rdb_type_extractor</td></tr></table>
