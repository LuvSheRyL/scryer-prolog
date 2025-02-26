/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Written 2020, 2021 by Markus Triska (triska@metalevel.at)
   Part of Scryer Prolog.

   This library provides the nonterminal format_//2 to describe
   formatted strings. format/[2,3] are provided for impure output.

   Usage:
   ======

   phrase(format_(FormatString, Arguments), Ls)

   format_//2 describes a list of characters Ls that are formatted
   according to FormatString. FormatString is a string (i.e.,
   a list of characters) that specifies the layout of Ls.
   The characters in FormatString are used literally, except
   for the following tokens with special meaning:

     ~w    use the next available argument from Arguments here
     ~q    use the next argument here, formatted as by writeq/1
     ~a    use the next argument here, which must be an atom
     ~s    use the next argument here, which must be a string
     ~d    use the next argument here, which must be an integer
     ~f    use the next argument here, a floating point number
     ~Nf   where N is an integer: format the float argument
           using N digits after the decimal point
     ~Nd   like ~d, placing the last N digits after a decimal point;
           if N is 0 or omitted, no decimal point is used.
     ~ND   like ~Nd, separating digits to the left of the decimal point
           in groups of three, using the character "," (comma)
     ~Nr   where N is an integer between 2 and 36: format the
           next argument, which must be an integer, in radix N.
           The characters "a" to "z" are used for radices 10 to 36.
           If N is omitted, it defaults to 8 (octal).
     ~NR   like ~Nr, except that "A" to "Z" are used for radices > 9
     ~|    place a tab stop at this position
     ~N|   where N is an integer: place a tab stop at text column N
     ~N+   where N is an integer: place a tab stop N characters
           after the previous tab stop (or start of line)
     ~t    distribute spaces evenly between the two closest tab stops
     ~`Ct  like ~t, use character C instead of spaces to fill the space
     ~n    newline
     ~Nn   N newlines
     ~i    ignore the next argument
     ~~    the literal ~

   Instead of ~N, you can write ~* to use the next argument from Arguments
   as the numeric argument.

   The predicate format/2 is like format_//2, except that it outputs
   the text on the terminal instead of describing it declaratively.

   format/3, used as format(Stream, FormatString, Arguments), outputs
   the described string to the given Stream. If Stream is a binary
   stream, then the code of each emitted character must be in 0..255.

   If at all possible, format_//2 should be used, to stress pure parts
   that enable easy testing etc. If necessary, you can emit the list Ls
   with maplist(put_char, Ls).

   The entire library only works if the Prolog flag double_quotes
   is set to chars, the default value in Scryer Prolog. This should
   also stay that way, to encourage a sensible environment.

   Example:

   ?- phrase(format_("~s~n~`.t~w!~12|", ["hello",there]), Cs).
   %@    Cs = "hello\n......there!".

   I place this code in the public domain. Use it in any way you want.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(format, [format_//2,
                   format/2,
                   format/3,
                   portray_clause/1,
                   portray_clause/2,
                   listing/1
                  ]).

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(charsio)).
:- use_module(library(between)).

format_(Fs, Args) -->
        { must_be(list, Fs),
          must_be(list, Args),
          unique_variable_names(Args, VNs),
          phrase(cells(Fs,Args,0,[],VNs), Cells) },
        format_cells(Cells).

format_cells([]) --> [].
format_cells([Cell|Cells]) -->
        format_cell(Cell),
        format_cells(Cells).

format_cell(newline) --> "\n".
format_cell(cell(From,To,Es)) -->
        % distribute the space between the glue elements
        { phrase(elements_gluevars(Es, 0, Length), Vs),
          (   Vs = [] -> true
          ;   Space is To - From - Length,
              (   Space =< 0 -> maplist(=(0), Vs)
              ;   length(Vs, NumGlue),
                  Distr is Space // NumGlue,
                  Delta is Space - Distr*NumGlue,
                  (   Delta =:= 0 ->
                      maplist(=(Distr), Vs)
                  ;   BigGlue is Distr + Delta,
                      reverse(Vs, [BigGlue|Rest]),
                      maplist(=(Distr), Rest)
                  )
              )
          ) },
        format_elements(Es).

format_elements([]) --> [].
format_elements([E|Es]) -->
        format_element(E),
        format_elements(Es).

format_element(chars(Cs)) --> list(Cs).
format_element(glue(Fill,Num)) -->
        { length(Ls, Num),
          maplist(=(Fill), Ls) },
        list(Ls).

list([]) --> [].
list([L|Ls]) --> [L], list(Ls).

elements_gluevars([], N, N) --> [].
elements_gluevars([E|Es], N0, N) -->
        element_gluevar(E, N0, N1),
        elements_gluevars(Es, N1, N).

element_gluevar(chars(Cs), N0, N) -->
        { length(Cs, L),
          N is N0 + L }.
element_gluevar(glue(_,V), N, N) --> [V].

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Our key datastructure is a list of cells and newlines.
   A cell has the shape cell(From,To,Elements), where
   From and To denote the positions of surrounding tab stops.

   Elements is a list of elements that occur in a cell,
   namely terms of the form chars(Cs) and glue(Char, Var).
   "glue" elements (TeX terminology) are evenly stretched
   to fill the remaining whitespace in the cell. For each
   glue element, the character Char is used for filling,
   and Var is a free variable that is used when the
   available space is distributed.

   newline is used if ~n occurs in a format string.
   It is used because a newline character does not
   consume whitespace in the sense of format strings.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

cells([], Args, Tab, Es, _) --> !,
        (   { Args == [] } -> cell(Tab, Tab, Es)
        ;   { domain_error(empty_list, Args, format_//2) }
        ).
cells([~,~|Fs], Args, Tab, Es, VNs) --> !,
        cells(Fs, Args, Tab, [chars("~")|Es], VNs).
cells([~,w|Fs], [Arg|Args], Tab, Es, VNs) --> !,
        { write_term_to_chars(Arg, [variable_names(VNs)], Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es], VNs).
cells([~,q|Fs], [Arg|Args], Tab, Es, VNs) --> !,
        { write_term_to_chars(Arg, [quoted(true),variable_names(VNs)], Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es], VNs).
cells([~,a|Fs], [Arg|Args], Tab, Es, VNs) --> !,
        { atom_chars(Arg, Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es], VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, [d|Fs], Args0, [Arg0|Args]) },
        !,
        { Arg is Arg0, % evaluate compound expression
          must_be(integer, Arg),
          number_chars(Arg, Cs0) },
        (   { Num =:= 0 } -> { Cs = Cs0 }
        ;   { length(Cs0, L),
              (   L =< Num ->
                  Delta is Num - L,
                  length(Zs, Delta),
                  maplist(=('0'), Zs),
                  phrase(("0.",list(Zs),list(Cs0)), Cs)
              ;   BeforeComma is L - Num,
                  length(Bs, BeforeComma),
                  append(Bs, Ds, Cs0),
                  phrase((list(Bs),".",list(Ds)), Cs)
              ) }
        ),
        cells(Fs, Args, Tab, [chars(Cs)|Es], VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, ['D'|Fs], Args0, [Arg|Args]) },
        !,
        { number_chars(Num, NCs),
          phrase(("~",list(NCs),"d"), FStr),
          phrase(format_(FStr, [Arg]), Cs0),
          phrase(upto_what(Bs0, .), Cs0, Ds),
          reverse(Bs0, Bs1),
          phrase(groups_of_three(Bs1), Bs2),
          reverse(Bs2, Bs),
          append(Bs, Ds, Cs) },
        cells(Fs, Args, Tab, [chars(Cs)|Es], VNs).
cells([~,i|Fs], [_|Args], Tab, Es, VNs) --> !,
        cells(Fs, Args, Tab, Es, VNs).
cells([~,n|Fs], Args, Tab, Es, VNs) --> !,
        cell(Tab, Tab, Es),
        n_newlines(1),
        cells(Fs, Args, 0, [], VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, [n|Fs], Args0, Args) },
        !,
        cell(Tab, Tab, Es),
        n_newlines(Num),
        cells(Fs, Args, 0, [], VNs).
cells([~,s|Fs], [Arg|Args], Tab, Es, VNs) --> !,
        cells(Fs, Args, Tab, [chars(Arg)|Es], VNs).
cells([~,f|Fs], [Arg|Args], Tab, Es, VNs) --> !,
        { format_number_chars(Arg, Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es], VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, [f|Fs], Args0, [Arg|Args]) },
        !,
        { format_number_chars(Arg, Cs0),
          phrase(upto_what(Bs, .), Cs0, Cs),
          (   Num =:= 0 -> Chars = Bs
          ;   (   Cs = ['.'|Rest] ->
                  length(Rest, L),
                  (   Num < L ->
                      length(Ds, Num),
                      append(Ds, _, Rest)
                  ;   Num =:= L ->
                      Ds = Rest
                  ;   Num > L,
                      Delta is Num - L,
                      % we should look into the float with
                      % greater accuracy here, and use the
                      % actual digits instead of 0.
                      length(Zs, Delta),
                      maplist(=('0'), Zs),
                      append(Rest, Zs, Ds)
                  )
              ;   length(Ds, Num),
                  maplist(=('0'), Ds)
              ),
              append(Bs, ['.'|Ds], Chars)
          ) },
        cells(Fs, Args, Tab, [chars(Chars)|Es], VNs).
cells([~,r|Fs], Args, Tab, Es, VNs) --> !,
        cells([~,'8',r|Fs], Args, Tab, Es, VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, [r|Fs], Args0, [Arg|Args]) },
        !,
        { integer_to_radix(Arg, Num, lowercase, Cs) },
        cells(Fs, Args, Tab, [chars(Cs)|Es], VNs).
cells([~,'R'|Fs], Args, Tab, Es, VNs) --> !,
        cells([~,'8','R'|Fs], Args, Tab, Es, VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, ['R'|Fs], Args0, [Arg|Args]) },
        !,
        { integer_to_radix(Arg, Num, uppercase, Cs) },
        cells(Fs, Args, Tab, [chars(Cs)|Es], VNs).
cells([~,'`',Char,t|Fs], Args, Tab, Es, VNs) --> !,
        cells(Fs, Args, Tab, [glue(Char,_)|Es], VNs).
cells([~,t|Fs], Args, Tab, Es, VNs) --> !,
        cells(Fs, Args, Tab, [glue(' ',_)|Es], VNs).
cells([~,'|'|Fs], Args, Tab0, Es, VNs) --> !,
        { phrase(elements_gluevars(Es, 0, Width), _),
          Tab is Tab0 + Width },
        cell(Tab0, Tab, Es),
        cells(Fs, Args, Tab, [], VNs).
cells([~|Fs0], Args0, Tab, Es, VNs) -->
        { numeric_argument(Fs0, Num, ['|'|Fs], Args0, Args) },
        !,
        cell(Tab, Num, Es),
        cells(Fs, Args, Num, [], VNs).
cells([~|Fs0], Args0, Tab0, Es, VNs) -->
        { numeric_argument(Fs0, Num, [+|Fs], Args0, Args) },
        !,
        { Tab is Tab0 + Num },
        cell(Tab0, Tab, Es),
        cells(Fs, Args, Tab, [], VNs).
cells([~|Cs], Args, _, _, _) -->
        (   { Args == [] } ->
            { domain_error(non_empty_list, [], format_//2) }
        ;   { domain_error(format_string, [~|Cs], format_//2) }
        ).
cells(Fs0, Args, Tab, Es, VNs) -->
        { phrase(upto_what(Fs1, ~), Fs0, Fs),
          Fs1 = [_|_] },
        cells(Fs, Args, Tab, [chars(Fs1)|Es], VNs).

format_number_chars(N0, Chars) :-
        N is N0, % evaluate compound expression
        number_chars(N, Chars).

n_newlines(0) --> !.
n_newlines(N0) --> { N0 > 0, N is N0 - 1 }, [newline], n_newlines(N).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- phrase(upto_what(Cs, ~), "abc~test", Rest).
Cs = [a,b,c], Rest = [~,t,e,s,t].
?- phrase(upto_what(Cs, ~), "abc", Rest).
Cs = [a,b,c], Rest = [].
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

upto_what([], W), [W] --> [W], !.
upto_what([C|Cs], W) --> [C], !, upto_what(Cs, W).
upto_what([], _) --> [].

groups_of_three([A,B,C,D|Rs]) --> !, [A,B,C], ",", groups_of_three([D|Rs]).
groups_of_three(Ls) --> list(Ls).

cell(From, To, Es0) -->
        (   { Es0 == [] } -> []
        ;   { reverse(Es0, Es) },
            [cell(From,To,Es)]
        ).

%?- numeric_argument("2f", Num, ['f'|Fs], Args0, Args).

%?- numeric_argument("100b", Num, Rs, Args0, Args).

numeric_argument(Ds, Num, Rest, Args0, Args) :-
        (   Ds = [*|Rest] ->
            Args0 = [Num|Args]
        ;   numeric_argument_(Ds, [], Ns, Rest),
            foldl(pow10, Ns, 0-0, Num-_),
            Args0 = Args
        ).

numeric_argument_([D|Ds], Ns0, Ns, Rest) :-
        (   member(D, "0123456789") ->
            number_chars(N, [D]),
            numeric_argument_(Ds, [N|Ns0], Ns, Rest)
        ;   Ns = Ns0,
            Rest = [D|Ds]
        ).


pow10(D, N0-Pow0, N-Pow) :-
        N is N0 + D*10^Pow0,
        Pow is Pow0 + 1.

radix_error(lowercase, R) --> format_("~~~dr", [R]).
radix_error(uppercase, R) --> format_("~~~dR", [R]).

integer_to_radix(I0, R, Which, Cs) :-
        I is I0, % evaluate compound expression
        must_be(integer, I),
        must_be(integer, R),
        (   \+ between(2, 36, R) ->
            phrase(radix_error(Which,R), Es),
            domain_error(format_string, Es, format_//2)
        ;   true
        ),
        digits(Which, Ds),
        (   I < 0 ->
            Pos is abs(I),
            phrase(integer_to_radix_(Pos, R, Ds), Cs0, "-")
        ;   I =:= 0 -> Cs0 = "0"
        ;   phrase(integer_to_radix_(I, R, Ds), Cs0)
        ),
        reverse(Cs0, Cs).

integer_to_radix_(0, _, _) --> !.
integer_to_radix_(I0, R, Ds) -->
        { M is I0 mod R,
          nth0(M, Ds, D),
          I is I0 // R
          },
        [D],
        integer_to_radix_(I, R, Ds).

digits(lowercase, "0123456789abcdefghijklmnopqrstuvwxyz").
digits(uppercase, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ").


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Impure I/O, implemented as a small wrapper over format_//2.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

format(Fs, Args) :-
        current_output(Stream),
        format(Stream, Fs, Args).

format(Stream, Fs, Args) :-
        phrase(format_(Fs, Args), Cs),
        % we use a specialised internal predicate that uses only a
        % single "write" operation for efficiency. It is equivalent to
        % maplist(put_char(Stream), Cs). It also works for binary streams.
        '$put_chars'(Stream, Cs),
        flush_output(Stream).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- phrase(format:cells("hello", [], 0, [], []), Cs).

?- phrase(format:cells("hello~10|", [], 0, [], []), Cs).
?- phrase(format:cells("~ta~t~10|", [], 0, [], []), Cs).

?- phrase(format_("~`at~50|", []), Ls).

?- phrase(format:cells("~`at~50|", [], 0, [], []), Cs),
   phrase(format:format_cells(Cs), Ls).
?- phrase(format:cells("~ta~t~tb~tc~21|", [], 0, [], []), Cs).
Cs = [cell(0,21,[glue(' ',_A),chars("a"),glue(' ',_B),glue(' ',_C),chars("b"),glue(' ',_D),chars("c ...")])]
?- phrase(format:cells("~ta~t~4|", [], 0, [], []), Cs).
Cs = [cell(0,4,[glue(' ',_A),chars("a"),glue(' ',_B)])]

?- phrase(format:format_cell(cell(0,1,[glue(a,_94)])), Ls).

?- phrase(format:format_cell(cell(0,50,[chars("hello")])), Ls).

?- phrase(format_("~`at~50|~n", []), Ls).
?- phrase(format_("hello~n~tthere~6|", []), Ls).

?- format("~ta~t~4|", []).
 a     true.

?- format("~ta~tb~tc~10|", []).
  a  b   c   true.

?- format("~tabc~3|", []).

?- format("~ta~t~4|", []).

?- format("~ta~t~tb~tc~20|", []).
    a        b     c   true.

?- format("~2f~n", [3]).
3.00
   true.

?- format("~20f", [0.1]).
0.10000000000000000000   true.

?- X is atan(2), format("~7f~n", [X]).
1.1071487
   X = 1.1071487177940906.

?- format("~`at~50|~n", []).
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
   true

?- format("~t~N", []).

?- format("~q", [.]).
'.'   true.

?- format("~12r", [300]).
210   true.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   We also provide rudimentary versions of portray_clause/1 and listing/1.

   In the eventual library organization, portray_clause/1 and
   related predicates may be placed in their own dedicated library.

   portray_clause/1 is useful for printing solutions in such a way
   that they can be read back with read/1.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

portray_clause(Term) :-
        current_output(Out),
        portray_clause(Out, Term).

portray_clause(Stream, Term) :-
        phrase(portray_clause_(Term), Ls),
        format(Stream, "~s", [Ls]).

portray_clause_(Term) -->
        { unique_variable_names(Term, VNs) },
        portray_(Term, VNs), ".\n".

unique_variable_names(Term, VNs) :-
        term_variables(Term, Vs),
        foldl(var_name, Vs, VNs, 0, _).

var_name(V, Name=V, Num0, Num) :-
        charsio:fabricate_var_name(numbervars, Name, Num0),
        Num is Num0 + 1.

literal(Lit, VNs) -->
        { write_term_to_chars(Lit, [quoted(true),variable_names(VNs)], Ls) },
        list(Ls).

portray_(Var, VNs) --> { var(Var) }, !, literal(Var, VNs).
portray_((Head :- Body), VNs) --> !,
        literal(Head, VNs), " :-\n",
        body_(Body, 0, 3, VNs).
portray_((Head --> Body), VNs) --> !,
        literal(Head, VNs), " -->\n",
        body_(Body, 0, 3, VNs).
portray_(Any, VNs) --> literal(Any, VNs).


body_(Var, C, I, VNs) --> { var(Var) }, !,
        indent_to(C, I),
        literal(Var, VNs).
body_((A,B), C, I, VNs) --> !,
        body_(A, C, I, VNs), ",\n",
        body_(B, 0, I, VNs).
body_(Body, C, I, VNs) -->
        { body_if_then_else(Body, If, Then, Else) },
        !,
        indent_to(C, I),
        "(  ",
        { C1 is I + 3 },
        body_(If, C1, C1, VNs), " ->\n",
        body_(Then, 0, C1, VNs), "\n",
        else_branch(Else, I, VNs).
body_((A;B), C, I, VNs) --> !,
        indent_to(C, I),
        "(  ",
        { C1 is I + 3 },
        body_(A, C1, C1, VNs), "\n",
        else_branch(B, I, VNs).
body_(Goal, C, I, VNs) -->
        indent_to(C, I), literal(Goal, VNs).


% True iff Body has the shape ( If -> Then ; Else ).
body_if_then_else(Body, If, Then, Else) :-
        nonvar(Body),
        Body = (A ; Else),
        nonvar(A),
        A = (If -> Then).

else_branch(Else, I, VNs) -->
        indent_to(0, I),
        ";  ",
        { C is I + 3 },
        (   { body_if_then_else(Else, If, Then, NextElse) } ->
            body_(If, C, C, VNs), " ->\n",
            body_(Then, 0, C, VNs), "\n",
            else_branch(NextElse, I, VNs)
        ;   { nonvar(Else), Else = ( A ; B ) } ->
            body_(A, C, C, VNs), "\n",
            else_branch(B, I, VNs)
        ;   body_(Else, C, C, VNs), "\n",
            indent_to(0, I),
            ")"
        ).

indent_to(CurrentColumn, Indent) -->
        format_("~t~*|", [Indent-CurrentColumn]).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- portray_clause(a).
a.

?- portray_clause((a :- b)).
a :-
   b.

?- portray_clause((a :- b, c, d)).
a :-
   b,
   c,
   d.
   true.


?- portray_clause([a,b,c,d]).
"abcd".

?- portray_clause(X).
?- portray_clause((f(X) :- X)).

?- portray_clause((h :- ( a -> b; c))).

?- portray_clause((h :- ( (a -> x ; y) -> b; c))).

?- portray_clause((h(X) :- ( (a(X) ; y(A,B)) -> b; c))).

?- portray_clause((h :- (a,d;b,c) ; (b,e;d))).

?- portray_clause((a :- b ; c ; d)).

?- portray_clause((h :- L = '.')).

?- portray_clause(-->(a, (b, {t}, d))).

?- portray_clause((A :- B)).

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

listing(PI) :-
        nonvar(PI),
        (   PI = Name/Arity0 ->
            Arity = Arity0
        ;   PI = Name//Arity0 ->
            Arity is Arity0 + 2
        ;   type_error(predicate_indicator, PI, listing/1)
        ),
        functor(Head, Name, Arity),
        \+ \+ clause(Head, _), % only true if there is at least one clause
        (   clause(Head, Body),
            (   Body == true ->
                portray_clause(Head)
            ;   portray_clause((Head :- Body))
            ),
            false
        ;   true
        ).
