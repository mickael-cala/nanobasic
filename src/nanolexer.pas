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

unit NanoLexer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, NanoTypes;

type
  TLexer = record
    src: PChar;
    pos: Integer;
    tok: Tok;
    num: Double;
    int_val: Int64;
    id: array[0..63] of Char;
    str: PChar;
    line: Integer;
    col: Integer;
    tok_line: Integer;
    tok_col: Integer;
    a: PArena;
  end;

procedure lex_init(var L: TLexer; a: PArena; const src: PChar);
procedure lex_next(var L: TLexer);

implementation

procedure lex_init(var L: TLexer; a: PArena; const src: PChar);
begin
  FillChar(L, sizeof(L), 0);
  L.a := a;
  L.src := src;
  L.line := 1;
  L.col := 1;
  L.pos := 0;
  lex_next(L);
end;

procedure lex_advance(var L: TLexer); inline;
begin
  if L.src[L.pos] = #10 then
  begin
    Inc(L.line);
    L.col := 1;
  end
  else
    Inc(L.col);
  Inc(L.pos);
end;

procedure lex_next(var L: TLexer);
var
  c: Char;
  start, len, code, outIdx: Integer;
  numBuf: array[0..63] of Char;
  isFloat: Boolean;
  pStr: PChar;
begin
  while (L.src[L.pos] = ' ') or (L.src[L.pos] = #9) or (L.src[L.pos] = #13) do
  begin
    if L.src[L.pos] = #9 then
      Inc(L.col, 4)
    else if L.src[L.pos] = ' ' then
      Inc(L.col);
    Inc(L.pos);
  end;

  L.tok_line := L.line;
  L.tok_col := L.col;

  c := L.src[L.pos];
  if c = #0 then
  begin
    L.tok := T_EOF;
    Exit;
  end;

  if c = #10 then
  begin
    L.tok := T_NEWLINE;
    lex_advance(L);
    Exit;
  end;

  if c = '''' then
  begin
    while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
      lex_advance(L);
    L.tok := T_REM;
    Exit;
  end;

  if ((c >= '0') and (c <= '9')) or ((c = '.') and (L.src[L.pos+1] in ['0'..'9'])) then
  begin
    start := L.pos;
    isFloat := (c = '.');
    while (L.src[L.pos] in ['0'..'9', '.']) do
    begin
      if L.src[L.pos] = '.' then isFloat := True;
      lex_advance(L);
    end;
    if (L.src[L.pos] in ['e', 'E']) and (L.src[L.pos+1] in ['+', '-', '0'..'9']) then
    begin
      isFloat := True;
      lex_advance(L);
      if L.src[L.pos] in ['+', '-'] then lex_advance(L);
      while (L.src[L.pos] in ['0'..'9']) do lex_advance(L);
    end;
    len := L.pos - start;
    if len >= sizeof(numBuf) then len := sizeof(numBuf) - 1;
    Move(L.src[start], numBuf[0], len);
    numBuf[len] := #0;

    if isFloat then
    begin
      Val(numBuf, L.num, code);
      if code <> 0 then L.num := 0.0;
      L.tok := T_NUM_L;
    end
    else
    begin
      Val(numBuf, L.int_val, code);
      if code <> 0 then
      begin
        Val(numBuf, L.num, code);
        L.tok := T_NUM_L;
      end
      else
        L.tok := T_INT_L;
    end;
    Exit;
  end;

  if c = '"' then
  begin
    lex_advance(L);
    start := L.pos;
    while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
    begin
      if (L.src[L.pos] = '\') and (L.src[L.pos+1] <> #0) then
      begin
        lex_advance(L);
        lex_advance(L);
      end
      else if (L.src[L.pos] = '"') and (L.src[L.pos+1] = '"') then
      begin
        lex_advance(L);
        lex_advance(L);
      end
      else if L.src[L.pos] = '"' then
        Break
      else
        lex_advance(L);
    end;

    len := L.pos - start;
    pStr := arena_alloc(L.a, len + 1);
    outIdx := 0;

    L.pos := start;
    while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
    begin
      if (L.src[L.pos] = '\') and (L.src[L.pos+1] <> #0) then
      begin
        Inc(L.pos);
        if L.src[L.pos] = 'n' then pStr[outIdx] := #10
        else if L.src[L.pos] = 't' then pStr[outIdx] := #9
        else pStr[outIdx] := L.src[L.pos];
        Inc(outIdx);
        Inc(L.pos);
      end
      else if (L.src[L.pos] = '"') and (L.src[L.pos+1] = '"') then
      begin
        pStr[outIdx] := '"';
        Inc(outIdx);
        Inc(L.pos, 2);
      end
      else if L.src[L.pos] = '"' then
        Break
      else
      begin
        pStr[outIdx] := L.src[L.pos];
        Inc(outIdx);
        Inc(L.pos);
      end;
    end;

    pStr[outIdx] := #0;
    L.str := pStr;
    if L.src[L.pos] = '"' then lex_advance(L);
    L.tok := T_STR_L;
    Exit;
  end;

  if ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) then
  begin
    start := L.pos;
    while (L.src[L.pos] in ['A'..'Z', 'a'..'z', '0'..'9', '$', '_', '%']) do
      lex_advance(L);
    len := L.pos - start;
    if len >= sizeof(L.id) then len := sizeof(L.id) - 1;
    Move(L.src[start], numBuf[0], len);
    numBuf[len] := #0;
    for start := 0 to len-1 do
      L.id[start] := UpCase(numBuf[start]);
    L.id[len] := #0;

    if StrComp(L.id, 'PRINT') = 0 then L.tok := T_PRINT
    else if StrComp(L.id, 'LET') = 0 then L.tok := T_LET
    else if StrComp(L.id, 'IF') = 0 then L.tok := T_IF
    else if StrComp(L.id, 'THEN') = 0 then L.tok := T_THEN
    else if StrComp(L.id, 'ELSEIF') = 0 then L.tok := T_ELSEIF
    else if StrComp(L.id, 'ELSE') = 0 then L.tok := T_ELSE
    else if StrComp(L.id, 'ENDIF') = 0 then L.tok := T_ENDIF
    else if StrComp(L.id, 'GOTO') = 0 then L.tok := T_GOTO
    else if StrComp(L.id, 'GOSUB') = 0 then L.tok := T_GOSUB
    else if StrComp(L.id, 'RETURN') = 0 then L.tok := T_RETURN
    else if StrComp(L.id, 'FOR') = 0 then L.tok := T_FOR
    else if StrComp(L.id, 'TO') = 0 then L.tok := T_TO
    else if StrComp(L.id, 'STEP') = 0 then L.tok := T_STEP
    else if StrComp(L.id, 'NEXT') = 0 then L.tok := T_NEXT
    else if StrComp(L.id, 'WHILE') = 0 then L.tok := T_WHILE
    else if StrComp(L.id, 'WEND') = 0 then L.tok := T_WEND
    else if StrComp(L.id, 'ENDWHILE') = 0 then L.tok := T_ENDWHILE
    else if StrComp(L.id, 'REPEAT') = 0 then L.tok := T_REPEAT
    else if StrComp(L.id, 'UNTIL') = 0 then L.tok := T_UNTIL
    else if StrComp(L.id, 'BREAK') = 0 then L.tok := T_BREAK
    else if StrComp(L.id, 'EXIT') = 0 then L.tok := T_EXIT
    else if StrComp(L.id, 'AND') = 0 then L.tok := T_AND
    else if StrComp(L.id, 'OR') = 0 then L.tok := T_OR
    else if StrComp(L.id, 'NOT') = 0 then L.tok := T_NOT
    else if StrComp(L.id, 'XOR') = 0 then L.tok := T_XOR
    else if StrComp(L.id, 'DIM') = 0 then L.tok := T_DIM
    else if StrComp(L.id, 'INPUT') = 0 then L.tok := T_INPUT
    else if StrComp(L.id, 'OPEN') = 0 then L.tok := T_OPEN
    else if StrComp(L.id, 'CLOSE') = 0 then L.tok := T_CLOSE
    else if StrComp(L.id, 'OUTPUT') = 0 then L.tok := T_OUTPUT
    else if StrComp(L.id, 'APPEND') = 0 then L.tok := T_APPEND
    else if StrComp(L.id, 'AS') = 0 then L.tok := T_AS
    else if StrComp(L.id, 'SLEEP') = 0 then L.tok := T_SLEEP
    else if StrComp(L.id, 'CALL') = 0 then L.tok := T_CALL
    else if StrComp(L.id, 'SUB') = 0 then L.tok := T_SUB
    else if StrComp(L.id, 'ENDSUB') = 0 then L.tok := T_ENDSUB
    else if StrComp(L.id, 'FUNCTION') = 0 then L.tok := T_FUNCTION
    else if StrComp(L.id, 'ENDFUNCTION') = 0 then L.tok := T_ENDFUNCTION
    else if StrComp(L.id, 'SELECT') = 0 then L.tok := T_SELECT     // <-- ICI
    else if StrComp(L.id, 'CASE') = 0 then L.tok := T_CASE         // <-- ICI
    else if StrComp(L.id, 'ENDSELECT') = 0 then L.tok := T_ENDSELECT // <-- ICI
    else if StrComp(L.id, 'REM') = 0 then
    begin
      while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
        lex_advance(L);
      L.tok := T_REM;
    end
    else if StrComp(L.id, 'END') = 0 then L.tok := T_END
    else L.tok := T_ID;
    Exit;
  end;

  lex_advance(L);
  case c of
    ':': L.tok := T_COLON;
    ';': L.tok := T_SEMI;
    ',': L.tok := T_COMMA;
    '+': L.tok := T_PLUS;
    '-': L.tok := T_MINUS;
    '*': L.tok := T_STAR;
    '/': L.tok := T_SLASH;
    '^': L.tok := T_CARET;
    '(': L.tok := T_LPAREN;
    ')': L.tok := T_RPAREN;
    '=': L.tok := T_EQ;
    '#': L.tok := T_HASH;
    '<':
      if L.src[L.pos] = '=' then
      begin
        lex_advance(L);
        L.tok := T_LTE;
      end
      else if L.src[L.pos] = '>' then
      begin
        lex_advance(L);
        L.tok := T_NEQ;
      end
      else
        L.tok := T_LT;
    '>':
      if L.src[L.pos] = '=' then
      begin
        lex_advance(L);
        L.tok := T_GTE;
      end
      else
        L.tok := T_GT;
    else
      L.tok := T_EOF;
  end;
end;

end.