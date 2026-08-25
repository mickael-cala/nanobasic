unit NanoTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  SYM_CAP = 256;
  ARENA_MAX_BYTES = 16 * 1024 * 1024;
  DEFAULT_MAX_INSTRUCTIONS = 10000000;

type
  TPrintCallback = procedure(const s: string; newline: Boolean);
  TInputCallback = procedure(const prompt: string; out resultStr: string);

  VType = (T_NIL, T_NUM, T_INT, T_STR, T_BOOL, T_ARR);

  PValue = ^Value;

  PArrayData = ^TArrayData;
  TArrayData = record
    dims: Integer;
    dim1, dim2, dim3: Integer;
    data: PValue;
  end;

  Value = record
    case t: VType of
      T_NUM:  (n: Double);
      T_INT:  (i: Int64);
      T_STR:  (s: PChar);
      T_BOOL: (b: Boolean);
      T_ARR:  (arr: PArrayData);
      T_NIL:  ();
  end;

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
    total_allocated: SizeInt;
  end;

  PSym = ^TSym;
  TSym = record
    name: PChar;
    val: Value;
    next: PSym;
  end;

  PSymTab = ^TSymTab;
  TSymTab = record
    parent: PSymTab;
    buckets: array[0..SYM_CAP-1] of PSym;
    a: PArena;
  end;

  Tok = (
    T_EOF, T_NUM_L, T_INT_L, T_STR_L, T_ID,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_CARET,
    T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE,
    T_AND, T_OR, T_NOT, T_XOR,
    T_LPAREN, T_RPAREN, T_COMMA, T_SEMI, T_COLON,
    T_PRINT, T_LET, T_IF, T_THEN, T_ELSE, T_ELSEIF, T_ENDIF,
    T_GOTO, T_GOSUB, T_RETURN,
    T_FOR, T_TO, T_STEP, T_NEXT,
    T_WHILE, T_WEND, T_ENDWHILE,
    T_REPEAT, T_UNTIL,
    T_BREAK, T_EXIT,
    T_DIM,
    T_INPUT, T_REM, T_END, T_NEWLINE,
    T_OPEN, T_CLOSE, T_OUTPUT, T_APPEND, T_AS, T_HASH,
    T_SLEEP, T_CALL,
    T_SUB, T_ENDSUB, T_FUNCTION, T_ENDFUNCTION,
    T_SELECT, T_CASE, T_ENDSELECT // <--- Ajout SELECT CASE
  );

  NodeKind = (
    N_NUM, N_INT, N_STR, N_BOOL, N_VAR, N_CALL, N_ARRAY_GET, N_BINOP, N_UNOP,
    N_PRINT, N_LET, N_ARRAY_SET, N_DIM,
    N_IF_SINGLE, N_IF_BLOCK, N_IF_BRANCH,
    N_WHILE, N_REPEAT, N_BREAK,
    N_GOTO, N_GOSUB, N_RETURN,
    N_FOR, N_NEXT, N_INPUT, N_REM, N_END,
    N_OPEN, N_CLOSE, N_PRINT_HASH, N_INPUT_HASH, N_PRINT_ARG,
    N_SLEEP, N_CALL_STMT,
    N_SUB_DEF, N_FUNC_DEF,
    N_SELECT, N_CASE_BRANCH // <--- Noeuds AST SELECT CASE
  );

  PNode = ^TNode;

  TNode = record
    k: NodeKind;
    source_line: Integer;
    source_col: Integer;
    next: PNode;
    num: Double;
    int_val: Int64;
    bool_val: Boolean;
    str: PChar;
    op: Tok;
    flag: Boolean;
    p1: PNode;
    p2: PNode;
    p3: PNode;
  end;

  TLabelEntry = record
    lineno: Integer;
    name: PChar;
    stmt_index: Integer;
  end;

  PLabelMap = ^TLabelMap;
  TLabelMap = record
    entries: array of TLabelEntry;
  end;

function MakeNum(val: Double): Value; inline;
function MakeInt(val: Int64): Value; inline;
function MakeBool(val: Boolean): Value; inline;
function MakeStr(val: PChar): Value; inline;
function MakeNil: Value; inline;
function MakeArr(arr: PArrayData): Value; inline;
function to_bool(const v: Value): Boolean; inline;
function to_int(const v: Value): Int64; inline;
function to_num(const v: Value): Double; inline;

function arena_alloc(a: PArena; n: SizeInt): Pointer;
function arena_strdup(a: PArena; const s: PChar): PChar;
procedure arena_free_all(a: PArena);

function sym_get(tab: PSymTab; const name: PChar): PValue;
function sym_set(tab: PSymTab; const name: PChar; v: Value): PValue;

procedure label_set_num(var map: TLabelMap; lineno, stmtIdx: Integer);
procedure label_set_text(var map: TLabelMap; a: PArena; const name: PChar; stmtIdx: Integer);
function label_find_num(const map: TLabelMap; lineno: Integer): Integer;
function label_find_text(const map: TLabelMap; const name: PChar): Integer;

implementation

function MakeNum(val: Double): Value; inline; begin Result.t := T_NUM; Result.n := val; end;
function MakeInt(val: Int64): Value; inline; begin Result.t := T_INT; Result.i := val; end;
function MakeBool(val: Boolean): Value; inline; begin Result.t := T_BOOL; Result.b := val; end;
function MakeStr(val: PChar): Value; inline; begin Result.t := T_STR; Result.s := val; end;
function MakeNil: Value; inline; begin Result.t := T_NIL; Result.n := 0.0; end;
function MakeArr(arr: PArrayData): Value; inline; begin Result.t := T_ARR; Result.arr := arr; end;

function to_bool(const v: Value): Boolean; inline;
begin
  case v.t of
    T_BOOL: Result := v.b;
    T_INT:  Result := (v.i <> 0);
    T_NUM:  Result := (v.n <> 0.0);
    T_STR:  Result := (v.s <> nil) and (v.s^ <> #0);
  else Result := False;
  end;
end;

function to_int(const v: Value): Int64; inline;
begin
  case v.t of
    T_INT:  Result := v.i;
    T_NUM:  Result := Trunc(v.n);
    T_BOOL: Result := Ord(v.b);
    T_STR:  Result := StrToInt64Def(string(v.s), 0);
  else Result := 0;
  end;
end;

function to_num(const v: Value): Double; inline;
begin
  case v.t of
    T_NUM:  Result := v.n;
    T_INT:  Result := v.i;
    T_BOOL: Result := Ord(v.b);
    T_STR:  Result := StrToFloatDef(string(v.s), 0.0);
  else Result := 0.0;
  end;
end;

function arena_alloc(a: PArena; n: SizeInt): Pointer;
var block: PArenaBlock; nc: SizeInt;
begin
  if (a = nil) or (n <= 0) then Exit(nil);
  n := (n + 7) and not 7;
  if a^.total_allocated + n > ARENA_MAX_BYTES then
  begin
    WriteLn(ErrOutput, 'Runtime Error: Plafond memoire depasse');
    Exit(nil);
  end;
  if (a^.current = nil) or (a^.current^.used + n > a^.current^.cap) then
  begin
    New(block);
    if a^.current = nil then nc := 8192 else nc := a^.current^.cap * 2;
    if nc < n + 512 then nc := n + 8192;
    GetMem(block^.buf, nc); FillChar(block^.buf^, nc, 0);
    block^.cap := nc; block^.used := 0; block^.next := nil;
    if a^.head = nil then a^.head := block else a^.current^.next := block;
    a^.current := block;
  end;
  Result := a^.current^.buf + a^.current^.used;
  Inc(a^.current^.used, n); Inc(a^.total_allocated, n);
end;

function arena_strdup(a: PArena; const s: PChar): PChar;
var len: SizeInt; p: PChar;
begin
  if s = nil then Exit(nil);
  len := StrLen(s) + 1; p := arena_alloc(a, len);
  if p <> nil then Move(s^, p^, len); Result := p;
end;

procedure arena_free_all(a: PArena);
var block, next: PArenaBlock;
begin
  if a = nil then Exit;
  block := a^.head;
  while block <> nil do
  begin
    next := block^.next;
    if block^.buf <> nil then FreeMem(block^.buf);
    Dispose(block); block := next;
  end;
  a^.head := nil; a^.current := nil; a^.total_allocated := 0;
end;

function hash(s: PChar): Cardinal;
var h: Cardinal;
begin
  if s = nil then Exit(0);
  h := 2166136261;
  while s^ <> #0 do begin h := (h xor Ord(s^)) * 16777619; Inc(s); end;
  Result := h;
end;

function sym_get(tab: PSymTab; const name: PChar): PValue;
var h: Cardinal; s: PSym; currTab: PSymTab;
begin
  if (name = nil) or (name^ = #0) or (tab = nil) then Exit(nil);
  currTab := tab;
  
  while currTab <> nil do
  begin
    h := hash(name) mod SYM_CAP; s := currTab^.buckets[h];
    while s <> nil do
    begin
      if (s^.name <> nil) and (StrIComp(s^.name, name) = 0) then Exit(@s^.val);
      s := s^.next;
    end;
    currTab := currTab^.parent;
  end;
  
  Result := nil;
end;

function sym_set(tab: PSymTab; const name: PChar; v: Value): PValue;
var h: Cardinal; s: PSym;
begin
  if (name = nil) or (name^ = #0) or (tab = nil) then Exit(nil);
  
  h := hash(name) mod SYM_CAP; s := tab^.buckets[h];
  while s <> nil do
  begin
    if (s^.name <> nil) and (StrIComp(s^.name, name) = 0) then
    begin
      s^.val := v; Exit(@s^.val);
    end;
    s := s^.next;
  end;
  
  s := arena_alloc(tab^.a, sizeof(TSym)); if s = nil then Exit(nil);
  s^.name := arena_strdup(tab^.a, name); s^.val := v; s^.next := tab^.buckets[h];
  tab^.buckets[h] := s; Result := @s^.val;
end;

procedure label_set_num(var map: TLabelMap; lineno, stmtIdx: Integer);
var idx: Integer;
begin
  idx := Length(map.entries); SetLength(map.entries, idx + 1);
  map.entries[idx].lineno := lineno; map.entries[idx].name := nil; map.entries[idx].stmt_index := stmtIdx;
end;

procedure label_set_text(var map: TLabelMap; a: PArena; const name: PChar; stmtIdx: Integer);
var idx: Integer;
begin
  idx := Length(map.entries); SetLength(map.entries, idx + 1);
  map.entries[idx].lineno := -1; map.entries[idx].name := arena_strdup(a, name); map.entries[idx].stmt_index := stmtIdx;
end;

function label_find_num(const map: TLabelMap; lineno: Integer): Integer;
var i: Integer;
begin
  for i := 0 to High(map.entries) do if map.entries[i].lineno = lineno then Exit(map.entries[i].stmt_index); Result := -1;
end;

function label_find_text(const map: TLabelMap; const name: PChar): Integer;
var i: Integer;
begin
  if name = nil then Exit(-1);
  for i := 0 to High(map.entries) do if (map.entries[i].name <> nil) and (StrIComp(map.entries[i].name, name) = 0) then Exit(map.entries[i].stmt_index);
  Result := -1;
end;

end.