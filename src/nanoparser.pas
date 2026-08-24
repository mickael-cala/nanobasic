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
    raw_src: PChar;
    error: Integer;
    err_line: Integer;
    err_col: Integer;
    errmsg: array[0..255] of Char;
    stmts: array of PNode;
    labels: TLabelMap;
  end;

procedure parser_init(var P: TParserr; a: PArena; const src: PChar);
procedure parse_program(P: PParserr);
function parse_stmt(P: PParserr): PNode;
function parse_expr(P: PParserr): PNode;
procedure format_error_context(P: PParserr);

implementation

function IsBuiltinName(const name: string): Boolean;
begin
  Result := (name = 'ABS') or (name = 'INT') or (name = 'SQR') or
            (name = 'RND') or (name = 'SIN') or (name = 'COS') or
            (name = 'TAN') or (name = 'LEN') or (name = 'LEFT$') or
            (name = 'RIGHT$') or (name = 'MID$') or (name = 'CHR$') or
            (name = 'ASC') or (name = 'STR$') or (name = 'VAL') or
            (name = 'EOF') or (name = 'TIMER');
end;

procedure parser_init(var P: TParserr; a: PArena; const src: PChar);
begin
  FillChar(P, sizeof(P), 0);
  P.a := a;
  P.raw_src := src;
  lex_init(P.L, a, src);
end;

function node_new(P: PParserr; k: NodeKind): PNode;
var n: PNode;
begin
  n := arena_alloc(P^.a, sizeof(TNode));
  if n = nil then
  begin
    P^.error := 1; P^.err_line := P^.L.tok_line; P^.err_col := P^.L.tok_col;
    StrPCopy(P^.errmsg, 'Out of memory during AST allocation'); Exit(nil);
  end;
  FillChar(n^, sizeof(TNode), 0);
  n^.k := k; n^.source_line := P^.L.tok_line; n^.source_col := P^.L.tok_col; Result := n;
end;

procedure parse_error_at(P: PParserr; line, col: Integer; const msg: string);
var tmp: string;
begin
  if P^.error = 0 then
  begin
    P^.error := 1; P^.err_line := line; P^.err_col := col;
    tmp := Format('Erreur Syntaxique [Ligne %d, Col %d]: %s', [line, col, msg]);
    if Length(tmp) >= sizeof(P^.errmsg) then tmp := Copy(tmp, 1, sizeof(P^.errmsg) - 1);
    StrPCopy(P^.errmsg, tmp);
  end;
end;

procedure parse_error(P: PParserr; const msg: string);
begin
  parse_error_at(P, P^.L.tok_line, P^.L.tok_col, msg);
end;

procedure format_error_context(P: PParserr);
var currLine, pIdx, lineStart, lineEnd: Integer; lineContent, caretLine: string;
begin
  if (P^.error = 0) or (P^.raw_src = nil) then Exit;
  WriteLn(ErrOutput, P^.errmsg);
  currLine := 1; pIdx := 0; lineStart := 0;
  while (P^.raw_src[pIdx] <> #0) and (currLine < P^.err_line) do
  begin
    if P^.raw_src[pIdx] = #10 then begin Inc(currLine); lineStart := pIdx + 1; end;
    Inc(pIdx);
  end;
  lineEnd := lineStart;
  while (P^.raw_src[lineEnd] <> #0) and (P^.raw_src[lineEnd] <> #10) and (P^.raw_src[lineEnd] <> #13) do Inc(lineEnd);
  SetLength(lineContent, lineEnd - lineStart);
  if Length(lineContent) > 0 then Move(P^.raw_src[lineStart], lineContent[1], Length(lineContent));
  if Length(lineContent) > 0 then
  begin
    WriteLn(ErrOutput, '  ', P^.err_line, ' | ', lineContent);
    caretLine := StringOfChar(' ', P^.err_col - 1 + Length(IntToStr(P^.err_line)) + 5) + '^';
    WriteLn(ErrOutput, caretLine);
  end;
end;

function parse_primary(P: PParserr): PNode;
var n: PNode; identName: PChar; argCount, idxCount: Integer;
begin
  case P^.L.tok of
    T_INT_L: begin n := node_new(P, N_INT); n^.int_val := P^.L.int_val; lex_next(P^.L); Exit(n); end;
    T_NUM_L: begin n := node_new(P, N_NUM); n^.num := P^.L.num; lex_next(P^.L); Exit(n); end;
    T_STR_L: begin n := node_new(P, N_STR); n^.str := P^.L.str; lex_next(P^.L); Exit(n); end;
    T_ID:
      begin
        if StrComp(P^.L.id, 'TRUE') = 0 then begin n := node_new(P, N_BOOL); n^.bool_val := True; lex_next(P^.L); Exit(n); end
        else if StrComp(P^.L.id, 'FALSE') = 0 then begin n := node_new(P, N_BOOL); n^.bool_val := False; lex_next(P^.L); Exit(n); end;

        identName := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);

        if P^.L.tok = T_LPAREN then
        begin
          lex_next(P^.L);
          if IsBuiltinName(UpperCase(string(identName))) then
          begin
            n := node_new(P, N_CALL); n^.call_name := identName;
            if P^.L.tok <> T_RPAREN then
            begin
              while (P^.error = 0) do
              begin
                argCount := Length(n^.call_args); SetLength(n^.call_args, argCount + 1);
                n^.call_args[argCount] := parse_expr(P);
                if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
              end;
            end;
            if P^.L.tok <> T_RPAREN then parse_error(P, 'Parenthese fermante attendue') else lex_next(P^.L);
            Exit(n);
          end
          else
          begin
            n := node_new(P, N_ARRAY_GET); n^.arr_get_name := identName;
            while (P^.error = 0) do
            begin
              idxCount := Length(n^.arr_get_indices);
              if idxCount >= 3 then begin parse_error(P, 'Maximum 3 dimensions supportees'); Break; end;
              SetLength(n^.arr_get_indices, idxCount + 1); n^.arr_get_indices[idxCount] := parse_expr(P);
              if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
            end;
            if P^.L.tok <> T_RPAREN then parse_error(P, 'Parenthese fermante attendue') else lex_next(P^.L);
            Exit(n);
          end;
        end
        else
        begin
          // GESTION DES FONCTIONS SANS PARENTHESES (TIMER, RND...)
          if IsBuiltinName(UpperCase(string(identName))) then
          begin
            n := node_new(P, N_CALL);
            n^.call_name := identName;
            Exit(n);
          end;

          n := node_new(P, N_VAR); n^.name := identName; Exit(n);
        end;
      end;
    T_LPAREN:
      begin
        lex_next(P^.L); n := parse_expr(P);
        if P^.L.tok <> T_RPAREN then parse_error(P, 'Parenthese fermante attendue') else lex_next(P^.L);
        Exit(n);
      end;
  else
    parse_error(P, 'Expression attendue');
    n := node_new(P, N_INT); n^.int_val := 0; Exit(n);
  end;
end;

function parse_unary(P: PParserr): PNode;
var n: PNode; savedTok: Tok;
begin
  if P^.L.tok = T_NOT then
  begin
    savedTok := P^.L.tok;
    lex_next(P^.L);
    n := node_new(P, N_UNOP); n^.un_tok := savedTok; n^.un_op := '!'; n^.un_child := parse_unary(P); Exit(n);
  end;
  if P^.L.tok = T_MINUS then
  begin
    lex_next(P^.L);
    n := node_new(P, N_UNOP); n^.un_tok := T_MINUS; n^.un_op := '-'; n^.un_child := parse_unary(P); Exit(n);
  end;
  if P^.L.tok = T_PLUS then begin lex_next(P^.L); Exit(parse_unary(P)); end;
  Result := parse_primary(P);
end;

function precedence(t: Tok): Integer; inline;
begin
  case t of
    T_OR, T_XOR:                          Result := 1;
    T_AND:                                Result := 2;
    T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE: Result := 3;
    T_PLUS, T_MINUS:                      Result := 4;
    T_STAR, T_SLASH:                      Result := 5;
    T_CARET:                              Result := 6;
  else Result := 0;
  end;
end;

function parse_binop(P: PParserr; min_prec: Integer): PNode;
var left, right, n: PNode; op: Tok; p_prec: Integer;
begin
  left := parse_unary(P);
  while (precedence(P^.L.tok) >= min_prec) and (P^.error = 0) do
  begin
    op := P^.L.tok; p_prec := precedence(op); lex_next(P^.L);
    right := parse_binop(P, p_prec + 1);
    n := node_new(P, N_BINOP); n^.bin_op := op; n^.bin_l := left; n^.bin_r := right;
    left := n;
  end;
  Result := left;
end;

function parse_expr(P: PParserr): PNode;
begin
  Result := parse_binop(P, 1);
end;

procedure skip_newlines_and_labels(P: PParserr);
var lineno, currentIdx: Integer;
begin
  while (P^.L.tok in [T_NEWLINE, T_REM]) and (P^.error = 0) do lex_next(P^.L);

  if P^.L.tok in [T_INT_L, T_NUM_L] then
  begin
    if P^.L.tok = T_INT_L then lineno := P^.L.int_val else lineno := Round(P^.L.num);
    lex_next(P^.L); currentIdx := Length(P^.stmts);
    if label_find_num(P^.labels, lineno) >= 0 then parse_error(P, 'Numero de ligne en double: ' + IntToStr(lineno))
    else label_set_num(P^.labels, lineno, currentIdx);
  end;
end;

function parse_stmt(P: PParserr): PNode;
var n, exprNode: PNode; name: PChar; argCount, idxCount, branchIdx, bodyIdx: Integer; sepTok: Tok; isEndIf, isEndWhile, singleLine: Boolean;
begin
  case P^.L.tok of
    T_PRINT:
      begin
        lex_next(P^.L);
        if P^.L.tok = T_HASH then
        begin
          lex_next(P^.L); n := node_new(P, N_PRINT_HASH);
          n^.print_hash_channel := parse_expr(P);
          if P^.L.tok = T_COMMA then lex_next(P^.L);
        end
        else n := node_new(P, N_PRINT);

        n^.print_trailing_sep := False;
        while not (P^.L.tok in [T_NEWLINE, T_EOF, T_COLON, T_ELSE, T_ELSEIF, T_REM]) and (P^.error = 0) do
        begin
          exprNode := parse_expr(P); sepTok := T_EOF;
          if P^.L.tok in [T_SEMI, T_COMMA] then begin sepTok := P^.L.tok; lex_next(P^.L); end;
          argCount := Length(n^.print_args); SetLength(n^.print_args, argCount + 1);
          n^.print_args[argCount].expr := exprNode; n^.print_args[argCount].sep := sepTok;
          if sepTok in [T_SEMI, T_COMMA] then n^.print_trailing_sep := True
          else begin n^.print_trailing_sep := False; Break; end;
        end;
        Exit(n);
      end;

    T_SLEEP:
      begin
        lex_next(P^.L);
        n := node_new(P, N_SLEEP);
        n^.sleep_expr := parse_expr(P);
        Exit(n);
      end;

    T_CALL:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu apres CALL'); Exit(node_new(P, N_REM)); end;
        n := node_new(P, N_CALL_STMT);
        n^.call_stmt_name := arena_strdup(P^.a, P^.L.id);
        lex_next(P^.L);
        
        if P^.L.tok = T_LPAREN then
        begin
          lex_next(P^.L);
          if P^.L.tok <> T_RPAREN then
          begin
            while P^.error = 0 do
            begin
              argCount := Length(n^.call_stmt_args);
              SetLength(n^.call_stmt_args, argCount + 1);
              n^.call_stmt_args[argCount] := parse_expr(P);
              if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
            end;
          end;
          if P^.L.tok <> T_RPAREN then parse_error(P, 'Parenthese fermante attendue') else lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_OPEN:
      begin
        lex_next(P^.L); n := node_new(P, N_OPEN);
        n^.open_file_expr := parse_expr(P);
        if P^.L.tok <> T_FOR then parse_error(P, 'FOR attendu');
        lex_next(P^.L);
        if P^.L.tok = T_INPUT then n^.open_mode := 'I'
        else if P^.L.tok = T_OUTPUT then n^.open_mode := 'O'
        else if P^.L.tok = T_APPEND then n^.open_mode := 'A'
        else parse_error(P, 'INPUT, OUTPUT ou APPEND attendu');
        lex_next(P^.L);
        if P^.L.tok <> T_AS then parse_error(P, 'AS attendu');
        lex_next(P^.L);
        if P^.L.tok = T_HASH then lex_next(P^.L);
        n^.open_channel := parse_expr(P);
        Exit(n);
      end;

    T_CLOSE:
      begin
        lex_next(P^.L); n := node_new(P, N_CLOSE);
        if not (P^.L.tok in [T_NEWLINE, T_EOF, T_COLON, T_ELSE, T_ELSEIF, T_REM]) then
        begin
          if P^.L.tok = T_HASH then lex_next(P^.L);
          n^.close_channel := parse_expr(P);
        end
        else n^.close_channel := nil;
        Exit(n);
      end;

    T_DIM:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu apres DIM'); Exit(node_new(P, N_REM)); end;
        name := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        if P^.L.tok <> T_LPAREN then begin parse_error(P, '"(" attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        n := node_new(P, N_DIM); n^.dim_name := name;
        while (P^.error = 0) do
        begin
          idxCount := Length(n^.dim_indices);
          if idxCount >= 3 then begin parse_error(P, 'Maximum 3 dimensions'); Break; end;
          SetLength(n^.dim_indices, idxCount + 1); n^.dim_indices[idxCount] := parse_expr(P);
          if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
        end;
        if P^.L.tok <> T_RPAREN then begin parse_error(P, '")" attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L); Exit(n);
      end;

    T_LET, T_ID:
      begin
        if P^.L.tok = T_LET then lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu'); Exit(node_new(P, N_REM)); end;
        name := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);

        if P^.L.tok = T_COLON then
        begin
          label_set_text(P^.labels, P^.a, name, Length(P^.stmts)); lex_next(P^.L); Exit(node_new(P, N_REM));
        end;

        if P^.L.tok = T_LPAREN then
        begin
          lex_next(P^.L); n := node_new(P, N_ARRAY_SET); n^.arr_set_name := name;
          while (P^.error = 0) do
          begin
            idxCount := Length(n^.arr_set_indices);
            if idxCount >= 3 then begin parse_error(P, 'Maximum 3 dimensions'); Break; end;
            SetLength(n^.arr_set_indices, idxCount + 1); n^.arr_set_indices[idxCount] := parse_expr(P);
            if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
          end;
          if P^.L.tok <> T_RPAREN then begin parse_error(P, '")" attendu'); Exit(node_new(P, N_REM)); end;
          lex_next(P^.L);
          if P^.L.tok <> T_EQ then begin parse_error(P, '= attendu'); Exit(node_new(P, N_REM)); end;
          lex_next(P^.L);
          n^.arr_set_expr := parse_expr(P); Exit(n);
        end;

        if P^.L.tok <> T_EQ then begin parse_error(P, '= attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        n := node_new(P, N_LET); n^.let_name := name; n^.let_expr := parse_expr(P); Exit(n);
      end;

    T_IF:
      begin
        lex_next(P^.L); exprNode := parse_expr(P);
        if P^.L.tok <> T_THEN then begin parse_error(P, 'THEN attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        singleLine := not (P^.L.tok in [T_NEWLINE, T_EOF, T_REM]);
        if singleLine then
        begin
          n := node_new(P, N_IF_SINGLE); n^.if_cond := exprNode; n^.if_thenb := parse_stmt(P);
          if P^.L.tok = T_ELSE then begin lex_next(P^.L); n^.if_elseb := parse_stmt(P); end;
          Exit(n);
        end
        else
        begin
          n := node_new(P, N_IF_BLOCK); SetLength(n^.if_branches, 1); n^.if_branches[0].cond := exprNode;
          while (P^.L.tok <> T_EOF) and (P^.error = 0) do
          begin
            skip_newlines_and_labels(P);
            isEndIf := False;
            if P^.L.tok = T_ENDIF then begin lex_next(P^.L); isEndIf := True; end
            else if P^.L.tok = T_END then
            begin
              lex_next(P^.L);
              if P^.L.tok = T_IF then begin lex_next(P^.L); isEndIf := True; end else begin parse_error(P, 'IF attendu apres END'); Break; end;
            end;
            if isEndIf then Break;

            if P^.L.tok = T_ELSEIF then
            begin
              lex_next(P^.L); branchIdx := Length(n^.if_branches); SetLength(n^.if_branches, branchIdx + 1);
              n^.if_branches[branchIdx].cond := parse_expr(P);
              if P^.L.tok <> T_THEN then begin parse_error(P, 'THEN attendu'); Break; end;
              lex_next(P^.L); Continue;
            end;

            if P^.L.tok = T_ELSE then
            begin
              lex_next(P^.L); branchIdx := Length(n^.if_branches); SetLength(n^.if_branches, branchIdx + 1);
              n^.if_branches[branchIdx].cond := nil; Continue;
            end;

            branchIdx := High(n^.if_branches); bodyIdx := Length(n^.if_branches[branchIdx].body);
            SetLength(n^.if_branches[branchIdx].body, bodyIdx + 1); n^.if_branches[branchIdx].body[bodyIdx] := parse_stmt(P);
            if P^.L.tok = T_COLON then lex_next(P^.L);
          end;
          Exit(n);
        end;
      end;

    T_WHILE:
      begin
        lex_next(P^.L); n := node_new(P, N_WHILE); n^.while_cond := parse_expr(P);
        while (P^.L.tok <> T_EOF) and (P^.error = 0) do
        begin
          skip_newlines_and_labels(P);
          isEndWhile := False;
          if (P^.L.tok = T_WEND) or (P^.L.tok = T_ENDWHILE) then begin lex_next(P^.L); isEndWhile := True; end
          else if P^.L.tok = T_END then
          begin
            lex_next(P^.L);
            if P^.L.tok = T_WHILE then begin lex_next(P^.L); isEndWhile := True; end else begin parse_error(P, 'WHILE attendu'); Break; end;
          end;
          if isEndWhile then Break;
          bodyIdx := Length(n^.while_body); SetLength(n^.while_body, bodyIdx + 1); n^.while_body[bodyIdx] := parse_stmt(P);
          if P^.L.tok = T_COLON then lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_REPEAT:
      begin
        lex_next(P^.L); n := node_new(P, N_REPEAT);
        while (P^.L.tok <> T_EOF) and (P^.error = 0) do
        begin
          skip_newlines_and_labels(P);
          if P^.L.tok = T_UNTIL then begin lex_next(P^.L); n^.repeat_cond := parse_expr(P); Break; end;
          bodyIdx := Length(n^.repeat_body); SetLength(n^.repeat_body, bodyIdx + 1); n^.repeat_body[bodyIdx] := parse_stmt(P);
          if P^.L.tok = T_COLON then lex_next(P^.L);
        end;
        Exit(n);
      end;

    T_BREAK, T_EXIT:
      begin
        lex_next(P^.L);
        if P^.L.tok in [T_FOR, T_WHILE, T_REPEAT] then lex_next(P^.L);
        Exit(node_new(P, N_BREAK));
      end;

    T_GOTO:
      begin
        lex_next(P^.L); n := node_new(P, N_GOTO);
        if P^.L.tok in [T_NUM_L, T_INT_L] then
        begin
          if P^.L.tok = T_INT_L then n^.goto_target_num := P^.L.int_val else n^.goto_target_num := Round(P^.L.num);
          n^.goto_target_lbl := nil; lex_next(P^.L);
        end
        else if P^.L.tok = T_ID then
        begin
          n^.goto_target_num := -1; n^.goto_target_lbl := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        end
        else parse_error(P, 'Cible de saut attendue');
        Exit(n);
      end;

    T_GOSUB:
      begin
        lex_next(P^.L); n := node_new(P, N_GOSUB);
        if P^.L.tok in [T_NUM_L, T_INT_L] then
        begin
          if P^.L.tok = T_INT_L then n^.goto_target_num := P^.L.int_val else n^.goto_target_num := Round(P^.L.num);
          n^.goto_target_lbl := nil; lex_next(P^.L);
        end
        else if P^.L.tok = T_ID then
        begin
          n^.goto_target_num := -1; n^.goto_target_lbl := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        end
        else parse_error(P, 'Cible de saut attendue');
        Exit(n);
      end;

    T_RETURN: begin lex_next(P^.L); Exit(node_new(P, N_RETURN)); end;

    T_FOR:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Variable FOR attendue'); Exit(node_new(P, N_REM)); end;
        n := node_new(P, N_FOR); n^.for_var := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        if P^.L.tok <> T_EQ then parse_error(P, '= attendu') else lex_next(P^.L);
        n^.for_from := parse_expr(P);
        if P^.L.tok <> T_TO then parse_error(P, 'TO attendu') else lex_next(P^.L);
        n^.for_to := parse_expr(P);
        if P^.L.tok = T_STEP then begin lex_next(P^.L); n^.for_step := parse_expr(P); end
        else begin n^.for_step := node_new(P, N_INT); n^.for_step^.int_val := 1; end;
        Exit(n);
      end;

    T_NEXT:
      begin
        lex_next(P^.L); n := node_new(P, N_NEXT);
        if P^.L.tok = T_ID then begin n^.next_var := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
        Exit(n);
      end;

    T_INPUT:
      begin
        lex_next(P^.L);
        if P^.L.tok = T_HASH then
        begin
          lex_next(P^.L); n := node_new(P, N_INPUT_HASH);
          n^.input_hash_channel := parse_expr(P);
          if P^.L.tok = T_COMMA then lex_next(P^.L);
          if P^.L.tok <> T_ID then parse_error(P, 'Variable attendue pour INPUT')
          else begin n^.input_name := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
        end
        else
        begin
          n := node_new(P, N_INPUT);
          if P^.L.tok = T_STR_L then
          begin
            n^.input_prompt := P^.L.str; lex_next(P^.L);
            if P^.L.tok in [T_COMMA, T_SEMI] then lex_next(P^.L) else parse_error(P, 'Separateur attendu');
          end else n^.input_prompt := nil;

          if P^.L.tok <> T_ID then parse_error(P, 'Variable attendue pour INPUT')
          else begin n^.input_name := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
        end;
        Exit(n);
      end;

    T_REM: begin lex_next(P^.L); Exit(node_new(P, N_REM)); end;
    T_END: begin lex_next(P^.L); Exit(node_new(P, N_END)); end;
  else
    parse_error(P, 'Instruction inconnue'); lex_next(P^.L); Exit(node_new(P, N_REM));
  end;
end;

procedure parse_program(P: PParserr);
var lineno, currentIdx, i, targetIdx: Integer; stmt: PNode;
begin
  while (P^.L.tok <> T_EOF) and (P^.error = 0) do
  begin
    while P^.L.tok in [T_NEWLINE, T_REM] do lex_next(P^.L);
    if P^.L.tok = T_EOF then Break;

    if P^.L.tok in [T_INT_L, T_NUM_L] then
    begin
      if P^.L.tok = T_INT_L then lineno := P^.L.int_val else lineno := Round(P^.L.num);
      lex_next(P^.L); currentIdx := Length(P^.stmts);
      if label_find_num(P^.labels, lineno) >= 0 then begin parse_error(P, 'Numero de ligne en double: ' + IntToStr(lineno)); Break; end;
      label_set_num(P^.labels, lineno, currentIdx);
    end;

    if (P^.L.tok = T_NEWLINE) or (P^.L.tok = T_EOF) or (P^.L.tok = T_REM) then Continue;

    while (P^.L.tok <> T_NEWLINE) and (P^.L.tok <> T_EOF) and (P^.error = 0) do
    begin
      stmt := parse_stmt(P);
      SetLength(P^.stmts, Length(P^.stmts) + 1); P^.stmts[High(P^.stmts)] := stmt;
      if P^.L.tok = T_COLON then lex_next(P^.L)
      else if P^.L.tok = T_REM then begin lex_next(P^.L); Break; end
      else if (P^.L.tok <> T_NEWLINE) and (P^.L.tok <> T_EOF) then begin parse_error(P, 'Fin d''instruction ou ":" attendu'); Break; end;
    end;
  end;

  if P^.error = 0 then
  begin
    for i := 0 to High(P^.stmts) do
    begin
      if P^.stmts[i]^.k in [N_GOTO, N_GOSUB] then
      begin
        if P^.stmts[i]^.goto_target_num >= 0 then targetIdx := label_find_num(P^.labels, P^.stmts[i]^.goto_target_num)
        else targetIdx := label_find_text(P^.labels, P^.stmts[i]^.goto_target_lbl);
        if targetIdx < 0 then
        begin
          if P^.stmts[i]^.goto_target_num >= 0 then parse_error_at(P, P^.stmts[i]^.source_line, P^.stmts[i]^.source_col, 'Cible introuvable')
          else parse_error_at(P, P^.stmts[i]^.source_line, P^.stmts[i]^.source_col, 'Label introuvable');
          Break;
        end;
      end;
    end;
  end;
end;

end.