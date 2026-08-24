unit NanoTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  SYM_CAP = 256;

type
  VType = (T_NIL, T_NUM, T_STR);

  PValue = ^Value;
  Value = record
    case t: VType of
      T_NUM: (n: Double);
      T_STR: (s: PChar);
      T_NIL: ();
  end;

  (* --- Allocateur d'Arène --- *)
  PArenaBlock = ^TArenaBlock;
  TArenaBlock = record
    buf: PChar;
    cap, used: SizeInt;
    next: PArenaBlock;
  end;

  PArena = ^TArena;
  TArena = record
    head: PArenaBlock;
    current: PArenaBlock;
  end;

  (* --- Table des Symboles --- *)
  PSym = ^TSym;
  TSym = record
    name: PChar;
    val: Value;
    next: PSym;
  end;

  PSymTab = ^TSymTab;
  TSymTab = record
    buckets: array[0..SYM_CAP-1] of PSym;
    a: PArena;
  end;

  (* --- Tokens --- *)
  Tok = (
    T_EOF, T_NUM_L, T_STR_L, T_ID,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_CARET,
    T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE,
    T_LPAREN, T_RPAREN, T_COMMA, T_COLON,
    T_PRINT, T_LET, T_IF, T_THEN, T_ELSE,
    T_GOTO, T_GOSUB, T_RETURN,
    T_FOR, T_TO, T_STEP, T_NEXT,
    T_INPUT, T_REM, T_END, T_NEWLINE
  );

  (* --- Arbre Syntaxique Abstrait (AST) --- *)
  NodeKind = (
    N_NUM, N_STR, N_VAR, N_BINOP, N_UNOP,
    N_PRINT, N_LET, N_IF, N_GOTO, N_GOSUB, N_RETURN,
    N_FOR, N_NEXT, N_INPUT, N_REM, N_END
  );

  PNode = ^TNode;
  TNode = record
    k: NodeKind;
    source_line: Integer;
    num: Double;
    str: PChar;
    name: PChar;
    bin_op: Tok;
    bin_l: PNode;
    bin_r: PNode;
    un_op: Char;
    un_child: PNode;
    print_expr: PNode;
    print_semi: Integer;
    let_name: PChar;
    let_expr: PNode;
    if_cond: PNode;
    if_thenb: PNode;
    if_elseb: PNode;
    goto_target: Integer;
    for_var: PChar;
    for_from: PNode;
    for_to: PNode;
    for_step: PNode;
    next_var: PChar;
    input_name: PChar;
  end;

  (* --- Table des Labels --- *)
  TLabelEntry = record
    lineno: Integer;
    stmt_index: Integer;
  end;

  PLabelMap = ^TLabelMap;
  TLabelMap = record
    entries: array of TLabelEntry;
  end;

function MakeNum(val: Double): Value; inline;
function MakeStr(val: PChar): Value; inline;
function MakeNil: Value; inline;

function arena_alloc(a: PArena; n: SizeInt): Pointer;
function arena_strdup(a: PArena; const s: PChar): PChar;
procedure arena_free_all(a: PArena);

function sym_get(var tab: TSymTab; const name: PChar): PValue;
function sym_set(var tab: TSymTab; const name: PChar; v: Value): PValue;

procedure label_set(var map: TLabelMap; lineno, stmtIdx: Integer);
function label_find(const map: TLabelMap; lineno: Integer): Integer;

implementation

function MakeNum(val: Double): Value; inline;
begin
  Result.t := T_NUM;
  Result.n := val;
end;

function MakeStr(val: PChar): Value; inline;
begin
  Result.t := T_STR;
  Result.s := val;
end;

function MakeNil: Value; inline;
begin
  Result.t := T_NIL;
  Result.n := 0.0;
end;

function arena_alloc(a: PArena; n: SizeInt): Pointer;
var
  block: PArenaBlock;
  nc: SizeInt;
begin
  if n <= 0 then Exit(nil);
  n := (n + 7) and not 7;
  if (a^.current = nil) or (a^.current^.used + n > a^.current^.cap) then
  begin
    New(block);
    if a^.current = nil then
      nc := 8192
    else
      nc := a^.current^.cap * 2;
    if nc < n + 512 then
      nc := n + 8192;
    GetMem(block^.buf, nc);
    FillChar(block^.buf^, nc, 0);
    block^.cap := nc;
    block^.used := 0;
    block^.next := nil;
    if a^.head = nil then
      a^.head := block
    else
      a^.current^.next := block;
    a^.current := block;
  end;
  Result := a^.current^.buf + a^.current^.used;
  Inc(a^.current^.used, n);
end;

function arena_strdup(a: PArena; const s: PChar): PChar;
var
  len: SizeInt;
  p: PChar;
begin
  if s = nil then Exit(nil);
  len := StrLen(s) + 1;
  p := arena_alloc(a, len);
  if p <> nil then
    Move(s^, p^, len);
  Result := p;
end;

procedure arena_free_all(a: PArena);
var
  block, next: PArenaBlock;
begin
  block := a^.head;
  while block <> nil do
  begin
    next := block^.next;
    if block^.buf <> nil then
      FreeMem(block^.buf);
    Dispose(block);
    block := next;
  end;
  a^.head := nil;
  a^.current := nil;
end;

function hash(s: PChar): Cardinal;
var
  h: Cardinal;
begin
  if s = nil then Exit(0);
  h := 2166136261;
  while s^ <> #0 do
  begin
    h := (h xor Ord(s^)) * 16777619;
    Inc(s);
  end;
  Result := h;
end;

function sym_get(var tab: TSymTab; const name: PChar): PValue;
var
  h: Cardinal;
  s: PSym;
begin
  if (name = nil) or (name^ = #0) then Exit(nil);
  h := hash(name) mod SYM_CAP;
  s := tab.buckets[h];
  while s <> nil do
  begin
    if (s^.name <> nil) and (StrComp(s^.name, name) = 0) then
      Exit(@s^.val);
    s := s^.next;
  end;
  Result := nil;
end;

function sym_set(var tab: TSymTab; const name: PChar; v: Value): PValue;
var
  h: Cardinal;
  s: PSym;
begin
  if (name = nil) or (name^ = #0) then Exit(nil);
  h := hash(name) mod SYM_CAP;
  s := tab.buckets[h];
  while s <> nil do
  begin
    if (s^.name <> nil) and (StrComp(s^.name, name) = 0) then
    begin
      s^.val := v;
      Exit(@s^.val);
    end;
    s := s^.next;
  end;
  s := arena_alloc(tab.a, sizeof(TSym));
  s^.name := arena_strdup(tab.a, name);
  s^.val := v;
  s^.next := tab.buckets[h];
  tab.buckets[h] := s;
  Result := @s^.val;
end;

procedure label_set(var map: TLabelMap; lineno, stmtIdx: Integer);
var
  idx: Integer;
begin
  idx := Length(map.entries);
  SetLength(map.entries, idx + 1);
  map.entries[idx].lineno := lineno;
  map.entries[idx].stmt_index := stmtIdx;
end;

function label_find(const map: TLabelMap; lineno: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(map.entries) do
    if map.entries[i].lineno = lineno then
      Exit(map.entries[i].stmt_index);
  Result := -1;
end;

end.