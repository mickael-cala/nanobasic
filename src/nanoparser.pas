{
  Nanobasic - A minimal BASIC interpreter
  Copyright (c) 2026 Mickaël Cala
  This file is part of Nanobasic.

  Nanobasic is free software: you can redistribute it and/or modify
  it under the terms of the GNU Affero General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Nanobasic is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License
  along with Nanobasic.  If not, see <https://www.gnu.org/licenses/>.

  For commercial licensing, please contact the author (Mickaël Cala).
}

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

function parse_expr_list(P: PParserr; endTok: Tok): PNode;
var head, tail, item: PNode;
begin
  head := nil; tail := nil;
  while (P^.error = 0) do
  begin
    item := parse_expr(P);
    if head = nil then head := item else tail^.next := item;
    tail := item;
    if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
  end;
  if P^.L.tok <> endTok then parse_error(P, 'Caractere de fin inattendu dans la liste');
  if P^.L.tok = endTok then lex_next(P^.L);
  Result := head;
end;

function parse_primary(P: PParserr): PNode;
var n: PNode; identName: PChar;
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
            n := node_new(P, N_CALL); n^.str := identName;
            if P^.L.tok <> T_RPAREN then n^.p1 := parse_expr_list(P, T_RPAREN) else begin n^.p1 := nil; lex_next(P^.L); end;
            Exit(n);
          end
          else
          begin
            n := node_new(P, N_ARRAY_GET); n^.str := identName;
            if P^.L.tok <> T_RPAREN then n^.p1 := parse_expr_list(P, T_RPAREN) else begin n^.p1 := nil; lex_next(P^.L); end;
            Exit(n);
          end;
        end
        else
        begin
          n := node_new(P, N_VAR); n^.str := identName; Exit(n);
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
    savedTok := P^.L.tok; lex_next(P^.L);
    n := node_new(P, N_UNOP); n^.op := savedTok; n^.p1 := parse_unary(P); Exit(n);
  end;
  if P^.L.tok = T_MINUS then
  begin
    lex_next(P^.L);
    n := node_new(P, N_UNOP); n^.op := T_MINUS; n^.p1 := parse_unary(P); Exit(n);
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
var left, right, n: PNode; opVal: Tok; p_prec: Integer;
begin
  left := parse_unary(P);
  while (precedence(P^.L.tok) >= min_prec) and (P^.error = 0) do
  begin
    opVal := P^.L.tok; p_prec := precedence(opVal); lex_next(P^.L);
    right := parse_binop(P, p_prec + 1);
    n := node_new(P, N_BINOP); n^.op := opVal; n^.p1 := left; n^.p2 := right;
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
var
  n, exprNode, argNode, headArgs, tailArgs, headBody, tailBody, headBranch, tailBranch, branch: PNode;
  name: PChar; sepTok: Tok; isEndIf, isEndWhile, singleLine, isFunc: Boolean;
begin
  case P^.L.tok of
    // --- INTEGRATION DE SELECT CASE ---
    T_SELECT:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_CASE then begin parse_error(P, 'CASE attendu apres SELECT'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        n := node_new(P, N_SELECT);
        n^.p1 := parse_expr(P); // L'expression a tester

        headBranch := nil; tailBranch := nil;
        
        while (P^.L.tok <> T_EOF) and (P^.error = 0) do
        begin
          skip_newlines_and_labels(P);
          
          if P^.L.tok = T_ENDSELECT then begin lex_next(P^.L); Break; end;
          if P^.L.tok = T_END then
          begin
            lex_next(P^.L);
            if P^.L.tok = T_SELECT then begin lex_next(P^.L); Break; end
            else begin parse_error(P, 'SELECT attendu apres END'); Break; end;
          end;

          if P^.L.tok <> T_CASE then begin parse_error(P, 'CASE ou END SELECT attendu'); Break; end;
          lex_next(P^.L);

          branch := node_new(P, N_CASE_BRANCH);
          
          if P^.L.tok = T_ELSE then
          begin
            lex_next(P^.L);
            branch^.p1 := nil; // CASE ELSE (nil)
            if P^.L.tok = T_COLON then lex_next(P^.L)
            else if P^.L.tok = T_NEWLINE then lex_next(P^.L);
          end
          else
          begin
            // Liste d'expressions a matcher
            headArgs := nil; tailArgs := nil;
            while P^.error = 0 do
            begin
              argNode := parse_expr(P);
              if headArgs = nil then headArgs := argNode else tailArgs^.next := argNode;
              tailArgs := argNode;
              if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
            end;
            branch^.p1 := headArgs;
            if P^.L.tok = T_COLON then lex_next(P^.L)
            else if P^.L.tok = T_NEWLINE then lex_next(P^.L)
            else begin parse_error(P, 'Fin de ligne attendue apres valeur CASE'); Break; end;
          end;

          // Recuperation des instructions du CASE
          headBody := nil; tailBody := nil;
          while (P^.L.tok <> T_EOF) and (P^.error = 0) do
          begin
            skip_newlines_and_labels(P);
            // On s'arrete au prochain CASE ou a la fin du SELECT
            if (P^.L.tok = T_CASE) or (P^.L.tok = T_ENDSELECT) or (P^.L.tok = T_END) then Break;
            
            argNode := parse_stmt(P);
            if headBody = nil then headBody := argNode else tailBody^.next := argNode;
            tailBody := argNode;
            if P^.L.tok = T_COLON then lex_next(P^.L);
          end;
          branch^.p2 := headBody;

          if headBranch = nil then headBranch := branch else tailBranch^.next := branch;
          tailBranch := branch;
        end;
        n^.p2 := headBranch;
        Exit(n);
      end;

    T_PRINT:
      begin
        lex_next(P^.L);
        if P^.L.tok = T_HASH then
        begin
          lex_next(P^.L); n := node_new(P, N_PRINT_HASH);
          n^.p1 := parse_expr(P);
          if P^.L.tok = T_COMMA then lex_next(P^.L);
        end
        else n := node_new(P, N_PRINT);

        n^.flag := False; headArgs := nil; tailArgs := nil;
        while not (P^.L.tok in [T_NEWLINE, T_EOF, T_COLON, T_ELSE, T_ELSEIF, T_REM]) and (P^.error = 0) do
        begin
          exprNode := parse_expr(P); sepTok := T_EOF;
          if P^.L.tok in [T_SEMI, T_COMMA] then begin sepTok := P^.L.tok; lex_next(P^.L); end;
          argNode := node_new(P, N_PRINT_ARG); argNode^.p1 := exprNode; argNode^.op := sepTok;
          if headArgs = nil then headArgs := argNode else tailArgs^.next := argNode;
          tailArgs := argNode;
          
          if sepTok in [T_SEMI, T_COMMA] then n^.flag := True
          else begin n^.flag := False; Break; end;
        end;
        if n^.k = N_PRINT then n^.p1 := headArgs else n^.p2 := headArgs;
        Exit(n);
      end;

    T_SLEEP:
      begin
        lex_next(P^.L); n := node_new(P, N_SLEEP); n^.p1 := parse_expr(P); Exit(n);
      end;

    T_CALL:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu apres CALL'); Exit(node_new(P, N_REM)); end;
        n := node_new(P, N_CALL_STMT); n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        if P^.L.tok = T_LPAREN then
        begin
          lex_next(P^.L);
          if P^.L.tok <> T_RPAREN then n^.p1 := parse_expr_list(P, T_RPAREN) else begin n^.p1 := nil; lex_next(P^.L); end;
        end;
        Exit(n);
      end;

    T_SUB, T_FUNCTION:
      begin
        isFunc := (P^.L.tok = T_FUNCTION);
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu'); Exit(node_new(P, N_REM)); end;
        if isFunc then n := node_new(P, N_FUNC_DEF) else n := node_new(P, N_SUB_DEF);
        n^.str := arena_strdup(P^.a, P^.L.id);
        lex_next(P^.L);
        
        if P^.L.tok = T_LPAREN then
        begin
          lex_next(P^.L);
          headArgs := nil; tailArgs := nil;
          while (P^.error = 0) and (P^.L.tok = T_ID) do
          begin
            argNode := node_new(P, N_VAR); argNode^.str := arena_strdup(P^.a, P^.L.id);
            if headArgs = nil then headArgs := argNode else tailArgs^.next := argNode;
            tailArgs := argNode;
            lex_next(P^.L);
            if P^.L.tok = T_COMMA then lex_next(P^.L) else Break;
          end;
          if P^.L.tok <> T_RPAREN then parse_error(P, 'Parenthese fermante attendue');
          lex_next(P^.L);
          n^.p1 := headArgs;
        end;

        headBody := nil; tailBody := nil;
        while (P^.L.tok <> T_EOF) and (P^.error = 0) do
        begin
          skip_newlines_and_labels(P);
          if (isFunc and (P^.L.tok = T_ENDFUNCTION)) or ((not isFunc) and (P^.L.tok = T_ENDSUB)) then
          begin
            lex_next(P^.L); Break;
          end
          else if P^.L.tok = T_END then
          begin
            lex_next(P^.L);
            if (isFunc and (P^.L.tok = T_FUNCTION)) or ((not isFunc) and (P^.L.tok = T_SUB)) then
            begin
              lex_next(P^.L); Break;
            end else begin parse_error(P, 'END SUB ou END FUNCTION attendu'); Break; end;
          end;

          argNode := parse_stmt(P);
          if headBody = nil then headBody := argNode else tailBody^.next := argNode;
          tailBody := argNode;
          if P^.L.tok = T_COLON then lex_next(P^.L);
        end;
        n^.p2 := headBody;
        Exit(n);
      end;

    T_OPEN:
      begin
        lex_next(P^.L); n := node_new(P, N_OPEN); n^.p1 := parse_expr(P);
        if P^.L.tok <> T_FOR then parse_error(P, 'FOR attendu');
        lex_next(P^.L);
        if P^.L.tok = T_INPUT then n^.str := 'I'
        else if P^.L.tok = T_OUTPUT then n^.str := 'O'
        else if P^.L.tok = T_APPEND then n^.str := 'A'
        else parse_error(P, 'INPUT, OUTPUT ou APPEND attendu');
        lex_next(P^.L);
        if P^.L.tok <> T_AS then parse_error(P, 'AS attendu'); lex_next(P^.L);
        if P^.L.tok = T_HASH then lex_next(P^.L);
        n^.p2 := parse_expr(P);
        Exit(n);
      end;

    T_CLOSE:
      begin
        lex_next(P^.L); n := node_new(P, N_CLOSE);
        if not (P^.L.tok in [T_NEWLINE, T_EOF, T_COLON, T_ELSE, T_ELSEIF, T_REM]) then
        begin
          if P^.L.tok = T_HASH then lex_next(P^.L);
          n^.p1 := parse_expr(P);
        end;
        Exit(n);
      end;

    T_DIM:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Identifiant attendu'); Exit(node_new(P, N_REM)); end;
        name := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        if P^.L.tok <> T_LPAREN then begin parse_error(P, '"(" attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        n := node_new(P, N_DIM); n^.str := name;
        n^.p1 := parse_expr_list(P, T_RPAREN);
        Exit(n);
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
          lex_next(P^.L); n := node_new(P, N_ARRAY_SET); n^.str := name;
          n^.p1 := parse_expr_list(P, T_RPAREN);
          if P^.L.tok <> T_EQ then begin parse_error(P, '= attendu'); Exit(node_new(P, N_REM)); end;
          lex_next(P^.L);
          n^.p2 := parse_expr(P); Exit(n);
        end;

        if P^.L.tok <> T_EQ then begin parse_error(P, '= attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        n := node_new(P, N_LET); n^.str := name; n^.p1 := parse_expr(P); Exit(n);
      end;

    T_IF:
      begin
        lex_next(P^.L); exprNode := parse_expr(P);
        if P^.L.tok <> T_THEN then begin parse_error(P, 'THEN attendu'); Exit(node_new(P, N_REM)); end;
        lex_next(P^.L);
        singleLine := not (P^.L.tok in [T_NEWLINE, T_EOF, T_REM]);
        if singleLine then
        begin
          n := node_new(P, N_IF_SINGLE); n^.p1 := exprNode; n^.p2 := parse_stmt(P);
          if P^.L.tok = T_ELSE then begin lex_next(P^.L); n^.p3 := parse_stmt(P); end;
          Exit(n);
        end
        else
        begin
          n := node_new(P, N_IF_BLOCK); headBranch := nil; tailBranch := nil;
          branch := node_new(P, N_IF_BRANCH); branch^.p1 := exprNode; headBody := nil; tailBody := nil;
          
          while (P^.L.tok <> T_EOF) and (P^.error = 0) do
          begin
            skip_newlines_and_labels(P);
            isEndIf := False;
            if P^.L.tok = T_ENDIF then begin lex_next(P^.L); isEndIf := True; end
            else if P^.L.tok = T_END then
            begin
              lex_next(P^.L);
              if P^.L.tok = T_IF then begin lex_next(P^.L); isEndIf := True; end else begin parse_error(P, 'IF attendu'); Break; end;
            end;
            
            if isEndIf then
            begin
              branch^.p2 := headBody;
              if headBranch = nil then headBranch := branch else tailBranch^.next := branch;
              Break;
            end;

            if P^.L.tok = T_ELSEIF then
            begin
              lex_next(P^.L);
              branch^.p2 := headBody;
              if headBranch = nil then headBranch := branch else tailBranch^.next := branch;
              tailBranch := branch;
              branch := node_new(P, N_IF_BRANCH); branch^.p1 := parse_expr(P); headBody := nil; tailBody := nil;
              if P^.L.tok <> T_THEN then begin parse_error(P, 'THEN attendu'); Break; end;
              lex_next(P^.L); Continue;
            end;

            if P^.L.tok = T_ELSE then
            begin
              lex_next(P^.L);
              branch^.p2 := headBody;
              if headBranch = nil then headBranch := branch else tailBranch^.next := branch;
              tailBranch := branch;
              branch := node_new(P, N_IF_BRANCH); branch^.p1 := nil; headBody := nil; tailBody := nil;
              Continue;
            end;

            argNode := parse_stmt(P);
            if headBody = nil then headBody := argNode else tailBody^.next := argNode;
            tailBody := argNode;
            if P^.L.tok = T_COLON then lex_next(P^.L);
          end;
          n^.p1 := headBranch;
          Exit(n);
        end;
      end;

    T_WHILE:
      begin
        lex_next(P^.L); n := node_new(P, N_WHILE); n^.p1 := parse_expr(P); headBody := nil; tailBody := nil;
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
          argNode := parse_stmt(P);
          if headBody = nil then headBody := argNode else tailBody^.next := argNode;
          tailBody := argNode;
          if P^.L.tok = T_COLON then lex_next(P^.L);
        end;
        n^.p2 := headBody;
        Exit(n);
      end;

    T_REPEAT:
      begin
        lex_next(P^.L); n := node_new(P, N_REPEAT); headBody := nil; tailBody := nil;
        while (P^.L.tok <> T_EOF) and (P^.error = 0) do
        begin
          skip_newlines_and_labels(P);
          if P^.L.tok = T_UNTIL then begin lex_next(P^.L); n^.p1 := parse_expr(P); Break; end;
          argNode := parse_stmt(P);
          if headBody = nil then headBody := argNode else tailBody^.next := argNode;
          tailBody := argNode;
          if P^.L.tok = T_COLON then lex_next(P^.L);
        end;
        n^.p2 := headBody;
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
          if P^.L.tok = T_INT_L then n^.int_val := P^.L.int_val else n^.int_val := Round(P^.L.num);
          n^.str := nil; lex_next(P^.L);
        end
        else if P^.L.tok = T_ID then
        begin
          n^.int_val := -1; n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        end
        else parse_error(P, 'Cible de saut attendue');
        Exit(n);
      end;

    T_GOSUB:
      begin
        lex_next(P^.L); n := node_new(P, N_GOSUB);
        if P^.L.tok in [T_NUM_L, T_INT_L] then
        begin
          if P^.L.tok = T_INT_L then n^.int_val := P^.L.int_val else n^.int_val := Round(P^.L.num);
          n^.str := nil; lex_next(P^.L);
        end
        else if P^.L.tok = T_ID then
        begin
          n^.int_val := -1; n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        end
        else parse_error(P, 'Cible de saut attendue');
        Exit(n);
      end;

    T_RETURN: begin lex_next(P^.L); Exit(node_new(P, N_RETURN)); end;

    T_FOR:
      begin
        lex_next(P^.L);
        if P^.L.tok <> T_ID then begin parse_error(P, 'Variable attendue'); Exit(node_new(P, N_REM)); end;
        n := node_new(P, N_FOR); n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L);
        if P^.L.tok <> T_EQ then parse_error(P, '= attendu') else lex_next(P^.L);
        n^.p1 := parse_expr(P);
        if P^.L.tok <> T_TO then parse_error(P, 'TO attendu') else lex_next(P^.L);
        n^.p2 := parse_expr(P);
        if P^.L.tok = T_STEP then begin lex_next(P^.L); n^.p3 := parse_expr(P); end
        else begin n^.p3 := node_new(P, N_INT); n^.p3^.int_val := 1; end;
        Exit(n);
      end;

    T_NEXT:
      begin
        lex_next(P^.L); n := node_new(P, N_NEXT);
        if P^.L.tok = T_ID then begin n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
        Exit(n);
      end;

    T_INPUT:
      begin
        lex_next(P^.L);
        if P^.L.tok = T_HASH then
        begin
          lex_next(P^.L); n := node_new(P, N_INPUT_HASH); n^.p1 := parse_expr(P);
          if P^.L.tok = T_COMMA then lex_next(P^.L);
          if P^.L.tok <> T_ID then parse_error(P, 'Variable attendue') else begin n^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
        end
        else
        begin
          n := node_new(P, N_INPUT);
          if P^.L.tok = T_STR_L then
          begin
            n^.str := P^.L.str; lex_next(P^.L);
            if P^.L.tok in [T_COMMA, T_SEMI] then lex_next(P^.L) else parse_error(P, 'Separateur attendu');
          end;
          if P^.L.tok <> T_ID then parse_error(P, 'Variable attendue') else begin n^.p1 := node_new(P, N_VAR); n^.p1^.str := arena_strdup(P^.a, P^.L.id); lex_next(P^.L); end;
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
        if P^.stmts[i]^.int_val >= 0 then targetIdx := label_find_num(P^.labels, P^.stmts[i]^.int_val)
        else targetIdx := label_find_text(P^.labels, P^.stmts[i]^.str);
        if targetIdx < 0 then
        begin
          if P^.stmts[i]^.int_val >= 0 then parse_error_at(P, P^.stmts[i]^.source_line, P^.stmts[i]^.source_col, 'Cible introuvable')
          else parse_error_at(P, P^.stmts[i]^.source_line, P^.stmts[i]^.source_col, 'Label introuvable');
          Break;
        end;
      end;
    end;
  end;
end;

end.