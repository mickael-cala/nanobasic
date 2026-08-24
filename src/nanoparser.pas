unit NanoParser;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, NanoTypes, NanoLexer;

type
  PParserr = ^TParserr;
  TParserr = record
    L: TLexer;
    a: PArena;
    error: Integer;
    errmsg: array[0..255] of Char;
    stmts: array of PNode;
    labels: TLabelMap;
  end;

procedure parser_init(var P: TParserr; a: PArena; const src: PChar);
procedure parse_program(P: PParserr);
function parse_stmt(P: PParserr): PNode;
function parse_expr(P: PParserr): PNode;

implementation

procedure parser_init(var P: TParserr; a: PArena; const src: PChar);
begin
  FillChar(P, sizeof(P), 0);
  P.a := a;
  lex_init(P.L, a, src);
end;

function node_new(P: PParserr; k: NodeKind): PNode;
var
  n: PNode;
begin
  n := arena_alloc(P^.a, sizeof(TNode));
  FillChar(n^, sizeof(TNode), 0);
  n^.k := k;
  n^.source_line := P^.L.line;
  Result := n;
end;

procedure parse_error(P: PParserr; const msg: string);
var
  tmp: string;
begin
  if P^.error = 0 then
  begin
    P^.error := 1;
    tmp := 'Line ' + IntToStr(P^.L.line) + ': ' + msg;
    if Length(tmp) >= sizeof(P^.errmsg) then
      tmp := Copy(tmp, 1, sizeof(P^.errmsg) - 1);
    StrPCopy(P^.errmsg, tmp);
  end;
end;

function parse_primary(P: PParserr): PNode;
var
  n: PNode;
begin
  case P^.L.tok of
    T_NUM_L:
      begin
        n := node_new(P, N_NUM);
        n^.num := P^.L.num;
        lex_next(P^.L);
        Exit(n);
      end;
    T_STR_L:
      begin
        n := node_new(P, N_STR);
        n^.str := P^.L.str;
        lex_next(P^.L);
        Exit(n);
      end;
    T_ID:
      begin
        n := node_new(P, N_VAR);
        n^.name := arena_strdup(P^.a, P^.L.id);
        lex_next(P^.L);
        Exit(n);
      end;
    T_LPAREN:
      begin
        lex_next(P^.L);
        n := parse_expr(P);
        if P^.L.tok <> T_RPAREN then
          parse_error(P, 'Parenthese fermante attendue')
        else
          lex_next(P^.L);
        Exit(n);
      end;
    else
      parse_error(P, 'Expression attendue');
      n := node_new(P, N_NUM);
      n^.num := 0.0;
      Exit(n);
  end;
end;

function parse_unary(P: PParserr): PNode;
var
  n: PNode;
begin
  if P^.L.tok = T_MINUS then
  begin
    lex_next(P^.L);
    n := node_new(P, N_UNOP);
    n^.un_op := '-';
    n^.un_child := parse_unary(P);
    Exit(n);
  end;
  if P^.L.tok = T_PLUS then
  begin
    lex_next(P^.L);
    Exit(parse_unary(P));
  end;
  Result := parse_primary(P);
end;

function precedence(t: Tok): Integer; inline;
begin
  case t of
    T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE: Result := 1;
    T_PLUS, T_MINUS: Result := 2;
    T_STAR, T_SLASH: Result := 3;
    T_CARET: Result := 4;
  else
    Result := 0;
  end;
end;

function parse_binop(P: PParserr; min_prec: Integer): PNode;
var
  left, right, n: PNode;
  op: Tok;
  p_prec: Integer;
begin
  left := parse_unary(P);
  while (precedence(P^.L.tok) >= min_prec) and (P^.error = 0) do
  begin
    op := P^.L.tok;
    p_prec := precedence(op);
    lex_next(P^.L);
    right := parse_binop(P, p_prec + 1);
    n := node_new(P, N_BINOP);
    n^.bin_op := op;
    n^.bin_l := left;
    n^.bin_r := right;
    left := n;
  end;
  Result := left;
end;

function parse_expr(P: PParserr): PNode;
begin
  Result := parse_binop(P, 1);
end;

function parse_stmt(P: PParserr): PNode;
var
  n: PNode;
  name: PChar;
begin
  case P^.L.tok of
    T_PRINT:
      begin
        lex_next(P^.L);
        n := node_new(P, N_PRINT);
        if (P^.L.tok = T_NEWLINE) or (P^.L.tok = T_EOF) or (P^.L.tok = T_COLON) or (P^.L.tok = T_ELSE) then
        begin
          n^.print_expr := nil;
          Exit(n);
        end;
        n^.print_expr := parse_expr(P);
        n^.print_semi := Ord(P^.L.tok = T_COMMA);
        if n^.print_semi <> 0 then
          lex_next(P^.L);
        Exit(n);
      end;

    T_LET, T_ID:
      begin
        if P^.L.tok = T_LET then
          lex_next(P^.L);
        if P^.L.tok <> T_ID then
        begin
          parse_error(P, 'Identifiant attendu');
          Exit(node_new(P, N_REM));
        end;
        name := arena_strdup(P^.a, P^.L.id);
        lex_next(P^.L);
        if P^.L.tok <> T_EQ then
        begin
          parse_error(P, '= attendu');
          Exit(node_new(P, N_REM));
        end;
        lex_next(P^.L);
        n := node_new(P, N_LET);
        n^.let_name := name;
        n^.let_expr := parse_expr(P);
        Exit(n);
      end;

    T_IF:
      begin
        lex_next(P^.L);
        n := node_new(P, N_IF);
        n^.if_cond := parse_expr(P);
        if P^.L.tok <> T_THEN then
          parse_error(P, 'THEN attendu')
        else
          lex_next(P^.L);
        n^.if_thenb := parse_stmt(P);
        if P^.L.tok = T_ELSE then
        begin
          lex_next(P^.L);
          n^.if_elseb := parse_stmt(P);
        end;
        Exit(n);
      end;

    T_GOTO:
      begin
        lex_next(P^.L);
        n := node_new(P, N_GOTO);
        if P^.L.tok <> T_NUM_L then
          parse_error(P, 'Numero de ligne attendu pour GOTO')
        else
        begin
          n^.goto_target := Round(P^.L.num);
          lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_GOSUB:
      begin
        lex_next(P^.L);
        n := node_new(P, N_GOSUB);
        if P^.L.tok <> T_NUM_L then
          parse_error(P, 'Numero de ligne attendu pour GOSUB')
        else
        begin
          n^.goto_target := Round(P^.L.num);
          lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_RETURN:
      begin
        lex_next(P^.L);
        Exit(node_new(P, N_RETURN));
      end;

    T_FOR:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then
        begin
          parse_error(P, 'Variable FOR attendue');
          Exit(node_new(P, N_REM));
        end;
        n := node_new(P, N_FOR);
        n^.for_var := arena_strdup(P^.a, P^.L.id);
        lex_next(P^.L);
        if P^.L.tok <> T_EQ then
          parse_error(P, '= attendu apres variable FOR')
        else
          lex_next(P^.L);
        n^.for_from := parse_expr(P);
        if P^.L.tok <> T_TO then
          parse_error(P, 'TO attendu')
        else
          lex_next(P^.L);
        n^.for_to := parse_expr(P);
        if P^.L.tok = T_STEP then
        begin
          lex_next(P^.L);
          n^.for_step := parse_expr(P);
        end
        else
        begin
          n^.for_step := node_new(P, N_NUM);
          n^.for_step^.num := 1.0;
        end;
        Exit(n);
      end;

    T_NEXT:
      begin
        lex_next(P^.L);
        n := node_new(P, N_NEXT);
        if P^.L.tok = T_ID then
        begin
          n^.next_var := arena_strdup(P^.a, P^.L.id);
          lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_INPUT:
      begin
        lex_next(P^.L);
        n := node_new(P, N_INPUT);
        if P^.L.tok <> T_ID then
          parse_error(P, 'Variable attendue apres INPUT')
        else
        begin
          n^.input_name := arena_strdup(P^.a, P^.L.id);
          lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_REM:
      begin
        lex_next(P^.L);
        Exit(node_new(P, N_REM));
      end;

    T_END:
      begin
        lex_next(P^.L);
        Exit(node_new(P, N_END));
      end;

    else
      parse_error(P, 'Instruction inconnue');
      lex_next(P^.L);
      Exit(node_new(P, N_REM));
  end;
end;

procedure parse_program(P: PParserr);
var
  lineno, currentIdx, i: Integer;
  stmt: PNode;
begin
  while (P^.L.tok <> T_EOF) and (P^.error = 0) do
  begin
    while P^.L.tok = T_NEWLINE do
      lex_next(P^.L);

    if P^.L.tok = T_EOF then
      Break;

    if P^.L.tok = T_NUM_L then
    begin
      lineno := Round(P^.L.num);
      lex_next(P^.L);
      currentIdx := Length(P^.stmts);
      if label_find(P^.labels, lineno) >= 0 then
      begin
        parse_error(P, 'Numero de ligne en double: ' + IntToStr(lineno));
        Break;
      end;
      label_set(P^.labels, lineno, currentIdx);
    end;

    if (P^.L.tok = T_NEWLINE) or (P^.L.tok = T_EOF) then
      Continue;

    while (P^.L.tok <> T_NEWLINE) and (P^.L.tok <> T_EOF) and (P^.error = 0) do
    begin
      stmt := parse_stmt(P);
      SetLength(P^.stmts, Length(P^.stmts) + 1);
      P^.stmts[High(P^.stmts)] := stmt;

      if P^.L.tok = T_COLON then
        lex_next(P^.L)
      else if (P^.L.tok <> T_NEWLINE) and (P^.L.tok <> T_EOF) then
      begin
        parse_error(P, 'Fin d''instruction ou ":" attendu');
        Break;
      end;
    end;
  end;

  // Validation statique des cibles GOTO et GOSUB
  if P^.error = 0 then
  begin
    for i := 0 to High(P^.stmts) do
    begin
      if P^.stmts[i]^.k in [N_GOTO, N_GOSUB] then
      begin
        if label_find(P^.labels, P^.stmts[i]^.goto_target) < 0 then
        begin
          P^.L.line := P^.stmts[i]^.source_line;
          parse_error(P, 'Cible de saut introuvable: ' + IntToStr(P^.stmts[i]^.goto_target));
          Break;
        end;
      end;
    end;
  end;
end;

end.