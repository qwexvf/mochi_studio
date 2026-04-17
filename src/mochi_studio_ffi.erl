-module(mochi_studio_ffi).
-export([erlang_timestamp/0]).

erlang_timestamp() ->
    {Mega, Sec, _} = erlang:timestamp(),
    Mega * 1000000 + Sec.
