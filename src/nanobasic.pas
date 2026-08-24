program NanoBasic;

{$mode objfpc}{$H+}
uses
  SysUtils, Math;

(* ============================================================
   1. VALEURS TYPÉES
   ============================================================ *)
type
  VType = (T_NIL, T_NUM, T_STR);

  PValue = ^Value;
  Value = record
    case t: VType of
      T_NUM: (n: Double);
      T_STR: (s: PChar);
      T_NIL: ();
  end;

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

(* ============================================================
   2. ARENA ALLOCATOR
   ============================================================ *)
type
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

(* ============================================================
   3. TABLE DES SYMBOLES
   ============================================================ *)
const
  SYM_CAP = 256;

type
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

function hash(s: PChar): Cardinal;
var
  h: Cardinal;
begin
  if s = nil then Exit(0);
  h := 2166136261;
  while s^ <> #0 do
  begin
    h := h xor Ord(s^);
    h := h * 16777619;
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

(* ============================================================
   4. LEXER
   ============================================================ *)
type
  Tok = (
    T_EOF, T_NUM_L, T_STR_L, T_ID,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_CARET,
    T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE,
    T_LPAREN, T_RPAREN, T_COMMA, T_ASSIGN,
    T_PRINT, T_LET, T_IF, T_THEN, T_ELSE,
    T_GOTO, T_FOR, T_TO, T_STEP, T_NEXT,
    T_INPUT, T_REM, T_END, T_NEWLINE
  );

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

  // Nombres (positifs uniquement dans le lexer, le unaire gère le négatif)
  if ((c >= '0') and (c <= '9')) or ((c = '.') and (L.src[L.pos+1] in ['0'..'9'])) then
  begin
    start := L.pos;
    while (L.src[L.pos] in ['0'..'9', '.']) do
      Inc(L.pos);
    // Gestion exposant optionnel
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

  // Chaînes entre guillemets
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

  // Identifiants et Mots-clés
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
    else if StrComp(L.id, 'FOR') = 0 then L.tok := T_FOR
    else if StrComp(L.id, 'TO') = 0 then L.tok := T_TO
    else if StrComp(L.id, 'STEP') = 0 then L.tok := T_STEP
    else if StrComp(L.id, 'NEXT') = 0 then L.tok := T_NEXT
    else if StrComp(L.id, 'INPUT') = 0 then L.tok := T_INPUT
    else if StrComp(L.id, 'REM') = 0 then
    begin
      // PURGE IMMEDIATE DU COMMENTAIRE JUSQU'AU RETOUR CHARIOT
      while (L.src[L.pos] <> #0) and (L.src[L.pos] <> #10) do
        Inc(L.pos);
      L.tok := T_REM;
    end
    else if StrComp(L.id, 'END') = 0 then L.tok := T_END
    else L.tok := T_ID;
    Exit;
  end;

  // Opérateurs
  Inc(L.pos);
  case c of
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

(* ============================================================
   5. AST
   ============================================================ *)
type
  NodeKind = (
    N_NUM, N_STR, N_VAR, N_BINOP, N_UNOP,
    N_PRINT, N_LET, N_IF, N_GOTO, N_LINE,
    N_FOR, N_NEXT, N_INPUT, N_REM, N_END
  );

  PNode = ^TNode;
  TNode = record
    k: NodeKind;
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
    line_lineno: Integer;
    line_stmt: PNode;
    for_var: PChar;
    for_from: PNode;
    for_to: PNode;
    for_step: PNode;
    next_var: PChar;
    input_name: PChar;
  end;

(* ============================================================
   6. PARSER
   ============================================================ *)
type
  PParserr = ^TParserr;
  TParserr = record
    L: TLexer;
    a: PArena;
    error: Integer;
    errmsg: array[0..255] of Char;
    lines: array of PNode;
  end;

function node_new(P: PParserr; k: NodeKind): PNode;
var
  n: PNode;
begin
  n := arena_alloc(P^.a, sizeof(TNode));
  FillChar(n^, sizeof(TNode), 0);
  n^.k := k;
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

function parse_expr(P: PParserr): PNode; forward;
function parse_stmt(P: PParserr): PNode; forward;

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
          parse_error(P, 'Expected )')
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
        if (P^.L.tok = T_NEWLINE) or (P^.L.tok = T_EOF) then
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
  lineno: Integer;
  stmt, line: PNode;
begin
  while (P^.L.tok <> T_EOF) and (P^.error = 0) do
  begin
    while P^.L.tok = T_NEWLINE do
      lex_next(P^.L);

    if P^.L.tok = T_EOF then
      Break;

    if P^.L.tok <> T_NUM_L then
    begin
      parse_error(P, 'Numero de ligne attendu');
      Break;
    end;

    lineno := Round(P^.L.num);
    lex_next(P^.L);

    stmt := parse_stmt(P);

    line := node_new(P, N_LINE);
    line^.line_lineno := lineno;
    line^.line_stmt := stmt;

    SetLength(P^.lines, Length(P^.lines) + 1);
    P^.lines[High(P^.lines)] := line;

    // Purge de fin de ligne propre
    while (P^.L.tok <> T_NEWLINE) and (P^.L.tok <> T_EOF) do
      lex_next(P^.L);
  end;
end;

(* ============================================================
   7. INTERPRÉTEUR
   ============================================================ *)
type
  TForFrame = record
    var_name: PChar;
    return_line: Integer;
    to_val, step_val: Double;
  end;

  TVM = record
    sym: PSymTab;
    lines: array of PNode;
    pc: Integer;
    running: Integer;
    forstk: array[0..63] of TForFrame;
    forsp: Integer;
    call_depth: Integer;
  end;

function find_line(var vm: TVM; lineno: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(vm.lines) do
    if (vm.lines[i] <> nil) and (vm.lines[i]^.line_lineno = lineno) then
      Exit(i);
  Result := -1;
end;

function to_num(v: Value): Double; inline;
begin
  if v.t = T_NUM then
    Result := v.n
  else
    Result := 0.0;
end;

function value_to_str(var vm: TVM; v: Value): PChar;
var
  buf: string;
begin
  if v.t = T_STR then
  begin
    if v.s = nil then Exit(arena_strdup(vm.sym^.a, ''))
    else Exit(v.s);
  end
  else
  begin
    buf := FloatToStr(v.n);
    Result := arena_strdup(vm.sym^.a, PChar(buf));
  end;
end;

function eval_node(var vm: TVM; n: PNode): Value;
var
  l, r: Value;
  sL, sR, concatBuf: PChar;
  lenL, lenR: SizeInt;
  c: Integer;
  p: PValue;
begin
  if (n = nil) or (vm.running = 0) then Exit(MakeNil);
  
  Inc(vm.call_depth);
  if vm.call_depth > 512 then
  begin
    WriteLn(ErrOutput, 'Runtime Error: Stack Overflow dans l''evaluation');
    vm.running := 0;
    Dec(vm.call_depth);
    Exit(MakeNil);
  end;

  case n^.k of
    N_NUM: Result := MakeNum(n^.num);
    N_STR: Result := MakeStr(n^.str);
    N_VAR:
      begin
        p := sym_get(vm.sym^, n^.name);
        if p <> nil then
          Result := p^
        else
          Result := MakeNum(0.0);
      end;
    N_UNOP:
      if n^.un_op = '-' then
        Result := MakeNum(-to_num(eval_node(vm, n^.un_child)))
      else
        Result := MakeNil;
    N_BINOP:
      begin
        l := eval_node(vm, n^.bin_l);
        r := eval_node(vm, n^.bin_r);
        
        if (l.t = T_STR) or (r.t = T_STR) then
        begin
          sL := value_to_str(vm, l);
          sR := value_to_str(vm, r);
          
          if n^.bin_op = T_PLUS then
          begin
            lenL := StrLen(sL);
            lenR := StrLen(sR);
            concatBuf := arena_alloc(vm.sym^.a, lenL + lenR + 1);
            if lenL > 0 then Move(sL^, concatBuf^, lenL);
            if lenR > 0 then Move(sR^, (concatBuf + lenL)^, lenR);
            concatBuf[lenL + lenR] := #0;
            Result := MakeStr(concatBuf);
          end
          else
          begin
            c := StrComp(sL, sR);
            case n^.bin_op of
              T_EQ:  Result := MakeNum(Ord(c = 0));
              T_NEQ: Result := MakeNum(Ord(c <> 0));
              T_LT:  Result := MakeNum(Ord(c < 0));
              T_GT:  Result := MakeNum(Ord(c > 0));
              T_LTE: Result := MakeNum(Ord(c <= 0));
              T_GTE: Result := MakeNum(Ord(c >= 0));
            else
              Result := MakeNil;
            end;
          end;
        end
        else
        begin
          case n^.bin_op of
            T_PLUS:  Result := MakeNum(l.n + r.n);
            T_MINUS: Result := MakeNum(l.n - r.n);
            T_STAR:  Result := MakeNum(l.n * r.n);
            T_SLASH:
              if r.n = 0.0 then
              begin
                WriteLn(ErrOutput, 'Runtime Warning: Division par zero');
                Result := MakeNum(0.0);
              end
              else
                Result := MakeNum(l.n / r.n);
            T_CARET: Result := MakeNum(Power(l.n, r.n));
            T_EQ:    Result := MakeNum(Ord(l.n = r.n));
            T_NEQ:   Result := MakeNum(Ord(l.n <> r.n));
            T_LT:    Result := MakeNum(Ord(l.n < r.n));
            T_GT:    Result := MakeNum(Ord(l.n > r.n));
            T_LTE:   Result := MakeNum(Ord(l.n <= r.n));
            T_GTE:   Result := MakeNum(Ord(l.n >= r.n));
          else
            Result := MakeNil;
          end;
        end;
      end;
  else
    Result := MakeNil;
  end;
  
  Dec(vm.call_depth);
end;

procedure exec_node(var vm: TVM; n: PNode);
var
  v: Value;
  idx: Integer;
  p: PValue;
  fr: ^TForFrame;
  nv: Double;
  done: Boolean;
  bufStr: string;
  code: Integer;
  inputVal: Double;
begin
  if (n = nil) or (vm.running = 0) then Exit;
  case n^.k of
    N_PRINT:
      begin
        if n^.print_expr <> nil then
        begin
          v := eval_node(vm, n^.print_expr);
          if v.t = T_STR then
          begin
            if v.s <> nil then Write(v.s);
          end
          else
            Write(v.n:0:4);
        end;
        if n^.print_semi = 0 then
          WriteLn;
      end;

    N_LET:
      begin
        v := eval_node(vm, n^.let_expr);
        sym_set(vm.sym^, n^.let_name, v);
      end;

    N_IF:
      begin
        v := eval_node(vm, n^.if_cond);
        if to_num(v) <> 0.0 then
          exec_node(vm, n^.if_thenb)
        else if n^.if_elseb <> nil then
          exec_node(vm, n^.if_elseb);
      end;

    N_GOTO:
      begin
        idx := find_line(vm, n^.goto_target);
        if idx < 0 then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Ligne ', n^.goto_target, ' introuvable');
          vm.running := 0;
        end
        else
          vm.pc := idx - 1;
      end;

    N_FOR:
      begin
        v := eval_node(vm, n^.for_from);
        sym_set(vm.sym^, n^.for_var, v);
        if vm.forsp >= High(vm.forstk) then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Debordement de la pile FOR');
          vm.running := 0;
          Exit;
        end;
        fr := @vm.forstk[vm.forsp];
        fr^.var_name := n^.for_var;
        fr^.return_line := vm.pc + 1;
        fr^.to_val := to_num(eval_node(vm, n^.for_to));
        fr^.step_val := to_num(eval_node(vm, n^.for_step));
        Inc(vm.forsp);
      end;

    N_NEXT:
      begin
        if vm.forsp <= 0 then
        begin
          WriteLn(ErrOutput, 'Runtime Error: NEXT sans FOR');
          vm.running := 0;
          Exit;
        end;
        fr := @vm.forstk[vm.forsp - 1];
        p := sym_get(vm.sym^, fr^.var_name);
        if p = nil then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Variable de boucle FOR corrompue');
          vm.running := 0;
          Exit;
        end;
        nv := p^.n + fr^.step_val;
        if fr^.step_val >= 0 then
          done := nv > fr^.to_val
        else
          done := nv < fr^.to_val;
        if not done then
        begin
          p^.n := nv;
          vm.pc := fr^.return_line - 1;
        end
        else
          Dec(vm.forsp);
      end;

    N_INPUT:
      begin
        Write('? ');
        ReadLn(bufStr);
        Val(bufStr, inputVal, code);
        if code = 0 then
          sym_set(vm.sym^, n^.input_name, MakeNum(inputVal))
        else
          sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))));
      end;

    N_END:
      vm.running := 0;

    else
      // N_REM ou no-op
  end;
end;

(* ============================================================
   8. RUNTIME & API
   ============================================================ *)
function basic_run(const src: PChar): Integer;
var
  arena: TArena;
  sym: TSymTab;
  P: TParserr;
  vm: TVM;
begin
  if (src = nil) or (src^ = #0) then Exit(0);

  FillChar(arena, sizeof(arena), 0);
  FillChar(sym, sizeof(sym), 0);
  sym.a := @arena;

  FillChar(P, sizeof(P), 0);
  P.a := @arena;
  P.L.a := @arena;
  P.L.src := src;
  P.L.line := 1;
  lex_next(P.L);
  parse_program(@P);

  if P.error <> 0 then
  begin
    WriteLn(ErrOutput, P.errmsg);
    arena_free_all(@arena);
    Exit(1);
  end;

  FillChar(vm, sizeof(vm), 0);
  vm.sym := @sym;
  vm.lines := P.lines;
  vm.running := 1;
  vm.pc := 0;

  while (vm.pc >= 0) and (vm.pc < Length(vm.lines)) and (vm.running <> 0) do
  begin
    exec_node(vm, vm.lines[vm.pc]^.line_stmt);
    Inc(vm.pc);
  end;

  arena_free_all(@arena);
  SetLength(P.lines, 0);
  Result := 0;
end;

(* ============================================================
   9. ENTRY POINT
   ============================================================ *)
var
  f: TextFile;
  srcBuf, lineBuf: string;
begin
  if ParamCount < 1 then
  begin
    WriteLn(ErrOutput, 'Usage: nanobasic <fichier.bas>');
    Halt(1);
  end;

  if not FileExists(ParamStr(1)) then
  begin
    WriteLn(ErrOutput, 'Fichier introuvable: ', ParamStr(1));
    Halt(1);
  end;

  AssignFile(f, ParamStr(1));
  {$I-}
  Reset(f);
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn(ErrOutput, 'Impossible de lire le fichier: ', ParamStr(1));
    Halt(1);
  end;

  srcBuf := '';
  while not EOF(f) do
  begin
    ReadLn(f, lineBuf);
    srcBuf := srcBuf + lineBuf + LineEnding;
  end;
  CloseFile(f);

  Halt(basic_run(PChar(srcBuf)));
end.