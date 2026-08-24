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
    id: array[0..63] of Char;
    str: PChar;
    line: Integer;
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
  L.pos := 0;
  lex_next(L);
end;

procedure lex_next(var L: TLexer);
var
  c: Char;
  start, len, code: Integer;
  numBuf: array[0..63] of Char;
  pStr: PChar;
begin
  while (L.src[L.pos] = ' ') or (L.src[L.pos] = #9) or (L.src[L.pos] = #13) do
    Inc(L.pos);

  c := L.src[L.pos];
  if c = #0 then
  begin
    L.tok := T_EOF;
    Exit;
  end;

  if c = #10 then
  begin
    L.tok := T_NEWLINE;
    Inc(L.pos);
    Inc(L.line);
    Exit;
  end;

  if ((c >= '0') and (c <= '9')) or ((c = '.') and (L.src[L.pos+1] in ['0'..'9'])) then
  begin
    start := L.pos;
    while (L.src[L.pos] in ['0'..'9', '.']) do
      Inc(L.pos);
    if (L.src[L.pos] in ['e', 'E']) and (L.src[L.pos+1] in ['+', '-', '0'..'9']) then
    begin
      Inc(L.pos);
      if L.src[L.pos] in ['+', '-'] then Inc(L.pos);
      while (L.src[L.pos] in ['0'..'9']) do Inc(L.pos);
    end;
    len := L.pos - start;
    if len >= sizeof(numBuf) then len := sizeof(numBuf) - 1;
    Move(L.src[start], numBuf[0], len);
    numBuf[len] := #0;
    Val(numBuf, L.num, code);
    if code <> 0 then L.num := 0.0;
    L.tok := T_NUM_L;
    Exit;
  end;

  if c = '"' then
  begin
    Inc(L.pos);
    start := L.pos;
    while (L.src[L.pos] <> #0) and (L.src[L.pos] <> '"') and (L.src[L.pos] <> #10) do
      Inc(L.pos);
    len := L.pos - start;
    pStr := arena_alloc(L.a, len + 1);
    if len > 0 then Move(L.src[start], pStr^, len);
    pStr[len] := #0;
    L.str := pStr;
    if L.src[L.pos] = '"' then Inc(L.pos);
    L.tok := T_STR_L;
    Exit;
  end;

  if ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) then
  begin
    start := L.pos;
    while (L.src[L.pos] in ['A'..'Z', 'a'..'z', '0'..'9', '$', '_']) do
      Inc(L.pos);
    len := L.pos - start;
    if len >= sizeof(L.id) then len := sizeof(L.id) - 1;
    Move(L.src[start], L.id[0], len);
    L.id[len] := #0;
    for start := 0 to len-1 do
      L.id[start] := UpCase(L.id[start]);

    if StrComp(L.id, 'PRINT') = 0 then L.tok := T_PRINT
    else if StrComp(L.id, 'LET') = 0 then L.tok := T_LET
    else if StrComp(L.id, 'IF') = 0 then L.tok := T_IF
    else if StrComp(L.id, 'THEN') = 0 then L.tok := T_THEN
    else if StrComp(L.id, 'ELSE') = 0 then L.tok := T_ELSE
    else if StrComp(L.id, 'GOTO') = 0 then L.tok := T_GOTO
    else if StrComp(L.id, 'GOSUB') = 0 then L.tok := T_GOSUB
    else if StrComp(L.id, 'RETURN') = 0 then L.tok := T_RETURN
    else if StrComp(L.id, 'FOR') = 0 then L.tok := T_FOR
    else if StrComp(L.id, 'TO') = 0 then L.tok := T_TO
    else if StrComp(L.id, 'STEP') = 0 then L.tok := T_STEP
    else if StrComp(L.id, 'NEXT') = 0 then L.tok := T_NEXT
    else if StrComp(L.id, 'INPUT') = 0 then L.tok := T_INPUT
    else if StrComp(L.id, 'REM') = 0 then
    begin
      while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
        Inc(L.pos);
      L.tok := T_REM;
    end
    else if StrComp(L.id, 'END') = 0 then L.tok := T_END
    else L.tok := T_ID;
    Exit;
  end;

  Inc(L.pos);
  case c of
    ':': L.tok := T_COLON;
    '+': L.tok := T_PLUS;
    '-': L.tok := T_MINUS;
    '*': L.tok := T_STAR;
    '/': L.tok := T_SLASH;
    '^': L.tok := T_CARET;
    '(': L.tok := T_LPAREN;
    ')': L.tok := T_RPAREN;
    ',': L.tok := T_COMMA;
    '=': L.tok := T_EQ;
    '<':
      if L.src[L.pos] = '=' then
      begin
        Inc(L.pos);
        L.tok := T_LTE;
      end
      else if L.src[L.pos] = '>' then
      begin
        Inc(L.pos);
        L.tok := T_NEQ;
      end
      else
        L.tok := T_LT;
    '>':
      if L.src[L.pos] = '=' then
      begin
        Inc(L.pos);
        L.tok := T_GTE;
      end
      else
        L.tok := T_GT;
    else
      L.tok := T_EOF;
  end;
end;

end.