%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Library for working with abstract code.
%%% @end
%%% @author Thomas Järvstrand <tjarvstrand@gmail.com>
%%% @copyright
%%% Copyright 2012 Thomas Järvstrand <tjarvstrand@gmail.com>
%%%
%%% This file is part of Pollock.
%%%
%%% Pollock is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU Lesser General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% Pollock is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public License
%%% along with Pollock. If not, see <http://www.gnu.org/licenses/>.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =======================================================
-module(pollock).

%%%_* Includes =================================================================
-include_lib("eunit/include/eunit.hrl").

%%%_* Exports ==================================================================

-export([free_vars/1,
         free_vars/2,
         get_abstract_code/1,
         parse_expressions/1,
         parse_forms/1,
         split_forms_at_function/3]).

%%%_* Defines ==================================================================

%%%_* Types ====================================================================

-type abstract_forms() :: [erl_parse:abstract_forms()].

%%%_* API ======================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Equivalent to free_vars(Snippet, 1).
%% @end
-spec free_vars(Text::string()) -> {ok, FreeVars::[atom()]} |
                                   {error, term()}.
%% @equiv free_vars(Text, 1)
%%------------------------------------------------------------------------------
free_vars(Snippet) -> free_vars(Snippet, 1).

%%------------------------------------------------------------------------------
%% @doc
%% Return a list of free variables in Snippet.
%% @end
-spec free_vars(Text::string(), pos_integer()) -> {ok, FreeVars::[atom()]} |
                                                  {error, term()}.
%% @equiv free_vars(Text, 1)
%%------------------------------------------------------------------------------
free_vars(Text, StartLine) ->
  %% StartLine/EndLine may be useful in error messages.
  {ok, Ts, EndLine} = erl_scan:string(Text, StartLine),
  %%Ts1 = reverse(strip(reverse(Ts))),
  Ts2 = [{'begin', 1}] ++ Ts ++ [{'end', EndLine}, {dot, EndLine}],
  case erl_parse:parse_exprs(Ts2) of
    {ok, Es} ->
      E = erl_syntax:block_expr(Es),
      E1 = erl_syntax_lib:annotate_bindings(E, ordsets:new()),
      {value, {free, Vs}} =
        lists:keysearch(free, 1, erl_syntax:get_ann(E1)),
      {ok, Vs};
    {error, {_Line, erl_parse, _Reason}} = Err -> Err
    end.

%%------------------------------------------------------------------------------
%% @doc
%% Return the abstract code of Module
%% @end
-spec get_abstract_code(Module::module()) -> abstract_forms().
%%------------------------------------------------------------------------------
get_abstract_code(Module) ->
  {Module, Bin, _File} = code:get_object_code(Module),
  {ok, {Module, [{abstract_code, {_Vsn, Abstract}}]}} =
    beam_lib:chunks(Bin, [abstract_code]),
  Abstract.


%%------------------------------------------------------------------------------
%% @doc
%% Tokenize and parse String as a sequence of forms.
%% @end
-spec parse_forms(string()) -> Forms::erl_parse:abstract_form().
%%------------------------------------------------------------------------------
parse_forms(String) -> parse(scan(String)).

%%------------------------------------------------------------------------------
%% @doc
%% Tokenize and parse String as a sequence of expressions.
%% @end
-spec parse_expressions(string()) -> Forms::erl_parse:abstract_form().
%%------------------------------------------------------------------------------
parse_expressions(String) ->
  case erl_parse:parse_exprs(scan(String)) of
    {ok, _}    = Res -> Res;
    {error, _} = Err -> Err
  end.


%%------------------------------------------------------------------------------
%% @doc
%% Return Abstract split into three parts. Everything before the function
%% F/A, the function's abstract code, and everything after
%% the function's abstract code.
-spec split_forms_at_function(Abstract::[erl_parse:abstract_form()],
                                F::atom(),
                                A::integer()) ->
                                   {[erl_parse:abstract_form()],
                                    [erl_parse:abstract_form()],
                                    [erl_parse:abstract_form()]}.
split_forms_at_function(Abstract, F, A) ->
  PredF =
    fun({function, _, F0, A0, _}) when F0 =:= F andalso A0 =:= A -> false;
       (_)                                                       -> true
    end,
  case lists:splitwith(PredF, Abstract) of
    {_, []}                     -> {error, not_found};
    {Pre, [FunAbstract | Post]} -> {Pre, [FunAbstract], Post}
  end.

%%%_* Internal functions =======================================================

%% Tokenize String
scan(String) ->
  case erl_scan:string(String) of
    {ok, Toks, _}       -> Toks;
    {error, _, _} = Err -> Err
  end.

parse(Toks) ->
  case parse(Toks, []) of
    {error, _} = Err -> Err;
    Res              -> {ok, Res}
  end.

%% Separate
parse([Tok = {dot, _}| T], Unparsed) ->
  [get_form(lists:reverse([Tok | Unparsed])) | parse(T, [])];
parse([Tok | T], Unparsed) -> parse(T, [Tok | Unparsed]);
parse([], []) -> [];
parse([], Unparsed) -> get_form(lists:reverse(Unparsed)).

get_form(Toks) ->
  case erl_parse:parse_form(Toks) of
    {ok, Forms}      -> Forms;
    {error, _} = Err -> Err
  end.

%%%_* Unit tests ===============================================================

split_forms_at_function_test_() ->
  Forms = test_file_forms("minimal_mod"),
  [
   ?_assertEqual({error, not_found}, split_forms_at_function([], foo, 1)),
   ?_assertEqual({error, not_found}, split_forms_at_function(Forms, foo, 1)),
   ?_assertEqual({error, not_found}, split_forms_at_function(Forms, min, 1)),
   ?_assertMatch({[_], [_], []}, split_forms_at_function(Forms, min, 0))
  ].


parse_expressions_test_() ->
  [?_assertMatch({error, {_, erl_parse, _}},
                 parse_expressions("foo(fun() -> ok end)")),
   ?_assertMatch({ok, [{call,1, {atom, 1, foo}, [_]}]},
                 parse_expressions("foo(fun() -> ok end)."))
  ].

parse_forms_test_() ->
  [?_assertMatch({error, {_, erl_parse, _}},
                 parse_forms("foo(fun() -> ok end)")),
   ?_assertMatch({ok, [{function, 1, foo, _, [_]}]},
                 parse_forms("foo() -> ok."))
  ].

free_vars_test_() ->
  [?_assertMatch({error, {_, erl_parse, _}}, free_vars("foo sth,")),
   ?_assertEqual({ok, []}, free_vars("ok")),
   ?_assertEqual({ok, ['Bar', 'Baz']}, free_vars("foo(Bar, Baz)"))
  ].

%%%_* Test helpers =============================================================

test_file_forms(File) ->
  Path = filename:join([code:priv_dir(pollock), File]),
  {ok, Bin} = file:read_file(Path),
  {ok, Forms} = parse_forms(unicode:characters_to_list(Bin)),
  Forms.


%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:

