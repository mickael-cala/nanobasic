unit NanoVM;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, NanoTypes;

type
  PVM = ^TVM;
  TForeignFunction = function(vm: PVM; const args: array of Value): Value;

  TVFSOpen = function(vm: PVM; ch: Integer; const filename: string; mode: Char): Boolean;
  TVFSClose = procedure(vm: PVM; ch: Integer);
  TVFSPrint = procedure(vm: PVM; ch: Integer; const s: string; newline: Boolean);
  TVFSInput = function(vm: PVM; ch: Integer; out s: string): Boolean;
  TVFSEof = function(vm: PVM; ch: Integer): Boolean;

  TFFIRecord = record
    name: string;
    func: TForeignFunction;
  end;
  
  TUserFunc = record
    name: string;
    def_node: PNode;
  end;

  TForFrame = record
    var_name: PChar;
    return_stmt_idx: Integer;
    to_val: Value;
    step_val: Value;
  end;

  TVM = record
    sym: PSymTab;
    stmts: array of PNode;
    labels: PLabelMap;
    pc: Integer;
    running: Integer;
    break_requested: Boolean;
    instructions_left: Int64;
    forstk: array[0..63] of TForFrame;
    forsp: Integer;
    callstack: array[0..255] of Integer;
    callsp: Integer;
    
    call_depth: Integer;
    expr_depth: Integer;
    sym_stack: array[1..512] of TSymTab;

    on_print: TPrintCallback;
    on_input: TInputCallback;

    vfs_open: TVFSOpen;
    vfs_close: TVFSClose;
    vfs_print: TVFSPrint;
    vfs_input: TVFSInput;
    vfs_eof: TVFSEof;

    file_channels: array[1..8] of TextFile;
    file_open: array[1..8] of Boolean;
    file_mode: array[1..8] of Char;

    ffi_funcs: array of TFFIRecord;
    user_funcs: array of TUserFunc;
  end;

procedure vm_init(var vm: TVM; sym: PSymTab; const stmts: array of PNode; labels: PLabelMap);
function vm_run(var vm: TVM): Integer;
function eval_node(var vm: TVM; n: PNode): Value;
procedure exec_node(var vm: TVM; n: PNode);

procedure vm_set_int(var vm: TVM; const name: string; val: Int64);
procedure vm_set_num(var vm: TVM; const name: string; val: Double);
procedure vm_set_str(var vm: TVM; const name: string; const val: string);
function vm_get_int(var vm: TVM; const name: string; defVal: Int64 = 0): Int64;
function vm_get_num(var vm: TVM; const name: string; defVal: Double = 0.0): Double;
function vm_get_str(var vm: TVM; const name: string; const defVal: string = ''): string;

procedure vm_register_ffi(var vm: TVM; const name: string; func: TForeignFunction);
procedure vm_enable_standard_vfs(var vm: TVM);

implementation

function sym_get_local(tab: PSymTab; const name: PChar): PValue;
var h: Cardinal; s: PSym;
begin
  if (name = nil) or (name^ = #0) or (tab = nil) then Exit(nil);
  h := hash(name) mod SYM_CAP; s := tab^.buckets[h];
  while s <> nil do
  begin
    if (s^.name <> nil) and (StrIComp(s^.name, name) = 0) then Exit(@s^.val);
    s := s^.next;
  end;
  Result := nil;
end;

function StdVFSOpen(vm: PVM; ch: Integer; const filename: string; mode: Char): Boolean;
begin
  if (ch < 1) or (ch > 8) then Exit(False);
  if vm^.file_open[ch] then CloseFile(vm^.file_channels[ch]);
  AssignFile(vm^.file_channels[ch], filename);
  {$I-}
  if mode = 'O' then Rewrite(vm^.file_channels[ch])
  else if mode = 'A' then Append(vm^.file_channels[ch])
  else Reset(vm^.file_channels[ch]);
  {$I+}
  if IOResult <> 0 then Exit(False);
  vm^.file_open[ch] := True;
  vm^.file_mode[ch] := mode;
  Result := True;
end;

procedure StdVFSClose(vm: PVM; ch: Integer);
begin
  if (ch >= 1) and (ch <= 8) and vm^.file_open[ch] then
  begin
    CloseFile(vm^.file_channels[ch]);
    vm^.file_open[ch] := False;
  end;
end;

procedure StdVFSPrint(vm: PVM; ch: Integer; const s: string; newline: Boolean);
begin
  if (ch >= 1) and (ch <= 8) and vm^.file_open[ch] and (vm^.file_mode[ch] <> 'I') then
  begin
    Write(vm^.file_channels[ch], s);
    if newline then WriteLn(vm^.file_channels[ch]);
  end;
end;

function StdVFSInput(vm: PVM; ch: Integer; out s: string): Boolean;
begin
  if (ch >= 1) and (ch <= 8) and vm^.file_open[ch] and (vm^.file_mode[ch] = 'I') then
  begin
    if not EOF(vm^.file_channels[ch]) then
    begin
      ReadLn(vm^.file_channels[ch], s);
      Exit(True);
    end;
  end;
  Result := False;
end;

function StdVFSEof(vm: PVM; ch: Integer): Boolean;
begin
  if (ch >= 1) and (ch <= 8) and vm^.file_open[ch] then
    Result := EOF(vm^.file_channels[ch])
  else
    Result := True;
end;

procedure vm_enable_standard_vfs(var vm: TVM);
begin
  vm.vfs_open := @StdVFSOpen;
  vm.vfs_close := @StdVFSClose;
  vm.vfs_print := @StdVFSPrint;
  vm.vfs_input := @StdVFSInput;
  vm.vfs_eof := @StdVFSEof;
end;

procedure vm_set_int(var vm: TVM; const name: string; val: Int64); begin sym_set(vm.sym, PChar(name), MakeInt(val)); end;
procedure vm_set_num(var vm: TVM; const name: string; val: Double); begin sym_set(vm.sym, PChar(name), MakeNum(val)); end;
procedure vm_set_str(var vm: TVM; const name: string; const val: string); begin sym_set(vm.sym, PChar(name), MakeStr(arena_strdup(vm.sym^.a, PChar(val)))); end;

function vm_get_int(var vm: TVM; const name: string; defVal: Int64 = 0): Int64;
var p: PValue; begin p := sym_get(vm.sym, PChar(name)); if p <> nil then Result := to_int(p^) else Result := defVal; end;
function vm_get_num(var vm: TVM; const name: string; defVal: Double = 0.0): Double;
var p: PValue; begin p := sym_get(vm.sym, PChar(name)); if p <> nil then Result := to_num(p^) else Result := defVal; end;

function value_to_str(var vm: TVM; const v: Value): PChar; forward;
function vm_get_str(var vm: TVM; const name: string; const defVal: string = ''): string;
var p: PValue; begin p := sym_get(vm.sym, PChar(name)); if p <> nil then Result := string(value_to_str(vm, p^)) else Result := defVal; end;

procedure vm_register_ffi(var vm: TVM; const name: string; func: TForeignFunction);
var i: Integer;
begin
  i := Length(vm.ffi_funcs); SetLength(vm.ffi_funcs, i + 1);
  vm.ffi_funcs[i].name := UpperCase(name); vm.ffi_funcs[i].func := func;
end;

procedure vm_init(var vm: TVM; sym: PSymTab; const stmts: array of PNode; labels: PLabelMap);
var i, j: Integer;
begin
  FillChar(vm, sizeof(vm), 0);
  vm.sym := sym; vm.labels := labels; vm.running := 1; vm.pc := 0; vm.break_requested := False;
  vm.instructions_left := DEFAULT_MAX_INSTRUCTIONS;
  vm.call_depth := 0; 
  vm.expr_depth := 0;
  SetLength(vm.stmts, Length(stmts));
  for i := 0 to High(stmts) do vm.stmts[i] := stmts[i];
  for i := 1 to 8 do vm.file_open[i] := False;
  vm.on_print := nil; vm.on_input := nil;
  vm.vfs_open := nil; vm.vfs_close := nil; vm.vfs_print := nil; vm.vfs_input := nil; vm.vfs_eof := nil;
  SetLength(vm.ffi_funcs, 0); Randomize;

  SetLength(vm.user_funcs, 0);
  for i := 0 to High(stmts) do
  begin
    if (stmts[i] <> nil) and (stmts[i]^.k in [N_SUB_DEF, N_FUNC_DEF]) then
    begin
      j := Length(vm.user_funcs);
      SetLength(vm.user_funcs, j + 1);
      vm.user_funcs[j].name := UpperCase(string(stmts[i]^.str));
      vm.user_funcs[j].def_node := stmts[i];
    end;
  end;
end;

function value_to_str(var vm: TVM; const v: Value): PChar;
var buf: string;
begin
  case v.t of
    T_STR: if v.s = nil then Exit(arena_strdup(vm.sym^.a, '')) else Exit(v.s);
    T_INT:  buf := IntToStr(v.i);
    T_NUM:  buf := FloatToStr(v.n);
    T_BOOL: if v.b then buf := 'TRUE' else buf := 'FALSE';
    T_ARR:  buf := '<ARRAY>';
  else buf := '';
  end;
  Result := arena_strdup(vm.sym^.a, PChar(buf));
end;

function get_args_array(var vm: TVM; head: PNode): TArrayData;
var count: Integer; curr: PNode; arr: TArrayData;
begin
  count := 0; curr := head;
  while curr <> nil do begin Inc(count); curr := curr^.next; end;
  arr.dims := 1; arr.dim1 := count - 1; arr.dim2 := 0; arr.dim3 := 0;
  if count > 0 then arr.data := arena_alloc(vm.sym^.a, count * sizeof(Value)) else arr.data := nil;
  count := 0; curr := head;
  while curr <> nil do begin (arr.data + count)^ := eval_node(vm, curr); Inc(count); curr := curr^.next; end;
  Result := arr;
end;

function call_user_func(var vm: TVM; def_node: PNode; const args: array of Value): Value;
var
  localSym, oldSym: PSymTab;
  argDef, curr: PNode;
  i, count, old_pc: Integer;
  retVal: PValue;
  old_stmts: array of PNode;
begin
  Inc(vm.call_depth);
  if vm.call_depth > 512 then begin WriteLn(ErrOutput, 'Runtime Error: Call Stack Overflow'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;

  localSym := @vm.sym_stack[vm.call_depth];
  FillChar(localSym^.buckets, sizeof(localSym^.buckets), 0);
  localSym^.parent := vm.sym;
  localSym^.a := vm.sym^.a;

  argDef := def_node^.p1;
  i := 0;
  while (argDef <> nil) and (i < Length(args)) do
  begin
    sym_set(localSym, argDef^.str, args[i]);
    argDef := argDef^.next;
    Inc(i);
  end;

  oldSym := vm.sym;
  vm.sym := localSym;

  SetLength(old_stmts, Length(vm.stmts));
  for i := 0 to High(vm.stmts) do old_stmts[i] := vm.stmts[i];
  old_pc := vm.pc;

  count := 0; curr := def_node^.p2;
  while curr <> nil do begin Inc(count); curr := curr^.next; end;
  
  SetLength(vm.stmts, count);
  curr := def_node^.p2; i := 0;
  while curr <> nil do begin vm.stmts[i] := curr; Inc(i); curr := curr^.next; end;

  vm.pc := 0;
  while (vm.pc >= 0) and (vm.pc < Length(vm.stmts)) and (vm.running <> 0) and not vm.break_requested do
  begin
    Dec(vm.instructions_left);
    if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Limite Instructions Depassee'); vm.running := 0; Break; end;

    exec_node(vm, vm.stmts[vm.pc]);

    if vm.break_requested then
    begin
      vm.break_requested := False;
      if vm.forsp > 0 then begin while (vm.pc < Length(vm.stmts)) and (vm.stmts[vm.pc]^.k <> N_NEXT) do Inc(vm.pc); Dec(vm.forsp); end
      else Break;
    end;
    Inc(vm.pc);
  end;

  vm.break_requested := False;

  if def_node^.k = N_FUNC_DEF then
  begin
    retVal := sym_get(localSym, def_node^.str);
    if retVal <> nil then Result := retVal^
    else Result := MakeInt(0);
  end
  else
    Result := MakeNil;

  SetLength(vm.stmts, Length(old_stmts));
  for i := 0 to High(old_stmts) do vm.stmts[i] := old_stmts[i];
  vm.pc := old_pc;
  vm.sym := oldSym;
  
  Dec(vm.call_depth);
end;

function parse_basic_val(const s: string): Value;
var
  p, len: Integer;
  numStr: string;
  hasDot: Boolean;
  intVal: Int64;
  floatVal: Double;
  code: Integer;
begin
  len := Length(s);
  p := 1;
  while (p <= len) and (s[p] = ' ') do Inc(p);
  if p > len then Exit(MakeInt(0));

  numStr := '';
  hasDot := False;

  if s[p] in ['+', '-'] then
  begin
    numStr := numStr + s[p];
    Inc(p);
  end;

  while (p <= len) do
  begin
    if s[p] in ['0'..'9'] then
      numStr := numStr + s[p]
    else if (s[p] = '.') and not hasDot then
    begin
      hasDot := True;
      numStr := numStr + s[p];
    end
    else
      Break;
    Inc(p);
  end;

  if (numStr = '') or (numStr = '+') or (numStr = '-') then Exit(MakeInt(0));

  if hasDot then
  begin
    Val(numStr, floatVal, code);
    if code = 0 then Exit(MakeNum(floatVal)) else Exit(MakeInt(0));
  end
  else
  begin
    Val(numStr, intVal, code);
    if code = 0 then Exit(MakeInt(intVal)) else Exit(MakeInt(0));
  end;
end;

function call_builtin(var vm: TVM; const fnName: string; args_head: PNode): Value;
var
  argArr: TArrayData; args: array of Value; i, argCount, ch, strLenVal, startPos, subLen: Integer;
  intVal: Int64; valS, subStr: string; charBuf: array[0..1] of Char;
begin
  argArr := get_args_array(vm, args_head);
  argCount := argArr.dim1 + 1;
  SetLength(args, argCount);
  for i := 0 to argCount - 1 do args[i] := (argArr.data + i)^;

  for i := 0 to High(vm.user_funcs) do
    if vm.user_funcs[i].name = UpperCase(fnName) then Exit(call_user_func(vm, vm.user_funcs[i].def_node, args));

  for i := 0 to High(vm.ffi_funcs) do
    if vm.ffi_funcs[i].name = UpperCase(fnName) then Exit(vm.ffi_funcs[i].func(@vm, args));

  if fnName = 'ABS' then begin if argCount < 1 then Exit(MakeInt(0)); if args[0].t = T_INT then Exit(MakeInt(Abs(args[0].i))) else Exit(MakeNum(Abs(to_num(args[0])))); end
  else if fnName = 'INT' then begin if argCount < 1 then Exit(MakeInt(0)); Exit(MakeInt(to_int(args[0]))); end
  else if fnName = 'TIMER' then Exit(MakeInt(GetTickCount64))
  else if fnName = 'SQR' then begin if argCount < 1 then Exit(MakeNum(0.0)); if to_num(args[0]) < 0.0 then begin WriteLn(ErrOutput, 'Warning: SQR(-)'); Exit(MakeNum(0.0)); end; Exit(MakeNum(Sqrt(to_num(args[0])))); end
  else if fnName = 'RND' then begin if argCount = 0 then Exit(MakeNum(Random)) else begin intVal := to_int(args[0]); if intVal <= 0 then Exit(MakeNum(Random)) else Exit(MakeInt(Random(intVal))); end; end
  else if fnName = 'SIN' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Sin(to_num(args[0])))); end
  else if fnName = 'COS' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Cos(to_num(args[0])))); end
  else if fnName = 'TAN' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Tan(to_num(args[0])))); end
  else if fnName = 'LEN' then begin if argCount < 1 then Exit(MakeInt(0)); if args[0].t = T_STR then begin if args[0].s = nil then Exit(MakeInt(0)) else Exit(MakeInt(StrLen(args[0].s))); end else Exit(MakeInt(Length(string(value_to_str(vm, args[0]))))); end
  else if fnName = 'LEFT$' then begin if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, ''))); valS := string(value_to_str(vm, args[0])); subLen := to_int(args[1]); if subLen <= 0 then subStr := '' else subStr := Copy(valS, 1, subLen); Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr)))); end
  else if fnName = 'RIGHT$' then begin if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, ''))); valS := string(value_to_str(vm, args[0])); subLen := to_int(args[1]); strLenVal := Length(valS); if subLen <= 0 then subStr := '' else if subLen >= strLenVal then subStr := valS else subStr := Copy(valS, strLenVal - subLen + 1, subLen); Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr)))); end
  else if fnName = 'MID$' then begin if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, ''))); valS := string(value_to_str(vm, args[0])); startPos := to_int(args[1]); if argCount >= 3 then subLen := to_int(args[2]) else subLen := Length(valS); if (startPos < 1) or (startPos > Length(valS)) or (subLen <= 0) then subStr := '' else subStr := Copy(valS, startPos, subLen); Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr)))); end
  else if fnName = 'CHR$' then begin if argCount < 1 then Exit(MakeStr(arena_strdup(vm.sym^.a, ''))); intVal := to_int(args[0]) and 255; charBuf[0] := Chr(intVal); charBuf[1] := #0; Exit(MakeStr(arena_strdup(vm.sym^.a, charBuf))); end
  else if fnName = 'ASC' then begin if argCount < 1 then Exit(MakeInt(0)); valS := string(value_to_str(vm, args[0])); if Length(valS) = 0 then Exit(MakeInt(0)) else Exit(MakeInt(Ord(valS[1]))); end
  else if fnName = 'STR$' then begin if argCount < 1 then Exit(MakeStr(arena_strdup(vm.sym^.a, ''))); Exit(MakeStr(value_to_str(vm, args[0]))); end
  else if fnName = 'VAL' then begin if argCount < 1 then Exit(MakeInt(0)); Exit(parse_basic_val(string(value_to_str(vm, args[0])))); end
  else if fnName = 'EOF' then begin if argCount < 1 then Exit(MakeBool(True)); ch := to_int(args[0]); if Assigned(vm.vfs_eof) then Exit(MakeBool(vm.vfs_eof(@vm, ch))) else Exit(MakeBool(True)); end;

  WriteLn(ErrOutput, 'Runtime Error: Fonction/Sub inconnue: ', fnName); vm.running := 0; Result := MakeNil;
end;

function eval_node(var vm: TVM; n: PNode): Value;
var
  l, r: Value; sL, sR, concatBuf: PChar; lenL, lenR: SizeInt; c, offset, i1, i2, i3: Integer;
  p: PValue; arrData: PArrayData;
begin
  if (n = nil) or (vm.running = 0) then Exit(MakeNil);
  Inc(vm.expr_depth); 
  if vm.expr_depth > 512 then begin WriteLn(ErrOutput, 'Runtime Error: Expression Stack Overflow'); vm.running := 0; Dec(vm.expr_depth); Exit(MakeNil); end;

  case n^.k of
    N_INT:  Result := MakeInt(n^.int_val);
    N_NUM:  Result := MakeNum(n^.num);
    N_BOOL: Result := MakeBool(n^.bool_val);
    N_STR:  Result := MakeStr(n^.str);
    N_VAR:  begin p := sym_get(vm.sym, n^.str); if p <> nil then Result := p^ else Result := MakeInt(0); end;
    N_ARRAY_GET:
      begin
        p := sym_get(vm.sym, n^.str);
        if (p = nil) or (p^.t <> T_ARR) or (p^.arr = nil) then begin Result := call_builtin(vm, UpperCase(string(n^.str)), n^.p1); Dec(vm.expr_depth); Exit; end;
        arrData := p^.arr; i1 := to_int(eval_node(vm, n^.p1));
        if arrData^.dims = 1 then offset := i1
        else if arrData^.dims = 2 then begin i2 := to_int(eval_node(vm, n^.p1^.next)); offset := i1 * (arrData^.dim2 + 1) + i2; end
        else begin i2 := to_int(eval_node(vm, n^.p1^.next)); i3 := to_int(eval_node(vm, n^.p1^.next^.next)); offset := (i1 * (arrData^.dim2 + 1) + i2) * (arrData^.dim3 + 1) + i3; end;
        Result := (arrData^.data + offset)^;
      end;
    N_CALL: Result := call_builtin(vm, UpperCase(string(n^.str)), n^.p1);
    N_UNOP:
      begin
        l := eval_node(vm, n^.p1);
        if n^.op = T_NOT then begin if l.t = T_BOOL then Result := MakeBool(not l.b) else if l.t = T_INT then Result := MakeInt(not l.i) else Result := MakeBool(not to_bool(l)); end
        else if n^.op = T_MINUS then begin if l.t = T_INT then Result := MakeInt(-l.i) else Result := MakeNum(-to_num(l)); end else Result := MakeNil;
      end;
    N_BINOP:
      begin
        l := eval_node(vm, n^.p1); r := eval_node(vm, n^.p2);
        if n^.op in [T_AND, T_OR, T_XOR] then begin if (l.t = T_BOOL) and (r.t = T_BOOL) then case n^.op of T_AND: Result := MakeBool(l.b and r.b); T_OR: Result := MakeBool(l.b or r.b); T_XOR: Result := MakeBool(l.b xor r.b); end else if (l.t = T_INT) and (r.t = T_INT) then case n^.op of T_AND: Result := MakeInt(l.i and r.i); T_OR: Result := MakeInt(l.i or r.i); T_XOR: Result := MakeInt(l.i xor r.i); end else case n^.op of T_AND: Result := MakeBool(to_bool(l) and to_bool(r)); T_OR: Result := MakeBool(to_bool(l) or to_bool(r)); T_XOR: Result := MakeBool(to_bool(l) xor to_bool(r)); end; end
        else if (l.t = T_STR) or (r.t = T_STR) then begin sL := value_to_str(vm, l); sR := value_to_str(vm, r); if n^.op = T_PLUS then begin lenL := StrLen(sL); lenR := StrLen(sR); concatBuf := arena_alloc(vm.sym^.a, lenL + lenR + 1); if concatBuf <> nil then begin if lenL > 0 then Move(sL^, concatBuf^, lenL); if lenR > 0 then Move(sR^, (concatBuf + lenL)^, lenR); concatBuf[lenL + lenR] := #0; Result := MakeStr(concatBuf); end else Result := MakeNil; end else begin c := StrComp(sL, sR); case n^.op of T_EQ: Result := MakeBool(c = 0); T_NEQ: Result := MakeBool(c <> 0); T_LT: Result := MakeBool(c < 0); T_GT: Result := MakeBool(c > 0); T_LTE: Result := MakeBool(c <= 0); T_GTE: Result := MakeBool(c >= 0); else Result := MakeNil; end; end; end
        else if (l.t = T_INT) and (r.t = T_INT) and (n^.op in [T_PLUS, T_MINUS, T_STAR, T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE]) then begin case n^.op of T_PLUS: Result := MakeInt(l.i + r.i); T_MINUS: Result := MakeInt(l.i - r.i); T_STAR: Result := MakeInt(l.i * r.i); T_EQ: Result := MakeBool(l.i = r.i); T_NEQ: Result := MakeBool(l.i <> r.i); T_LT: Result := MakeBool(l.i < r.i); T_GT: Result := MakeBool(l.i > r.i); T_LTE: Result := MakeBool(l.i <= r.i); T_GTE: Result := MakeBool(l.i >= r.i); else Result := MakeNil; end; end
        else begin case n^.op of T_PLUS: Result := MakeNum(to_num(l) + to_num(r)); T_MINUS: Result := MakeNum(to_num(l) - to_num(r)); T_STAR: Result := MakeNum(to_num(l) * to_num(r)); T_SLASH: if to_num(r) = 0.0 then begin WriteLn(ErrOutput, 'Runtime Warning: Div 0'); Result := MakeNum(0.0); end else Result := MakeNum(to_num(l) / to_num(r)); T_CARET: Result := MakeNum(Power(to_num(l), to_num(r))); T_EQ: Result := MakeBool(to_num(l) = to_num(r)); T_NEQ: Result := MakeBool(to_num(l) <> to_num(r)); T_LT: Result := MakeBool(to_num(l) < to_num(r)); T_GT: Result := MakeBool(to_num(l) > to_num(r)); T_LTE: Result := MakeBool(to_num(l) <= to_num(r)); T_GTE: Result := MakeBool(to_num(l) >= to_num(r)); else Result := MakeNil; end; end;
      end;
  else Result := MakeNil;
  end;
  Dec(vm.expr_depth);
  if (Result.t = T_NUM) and (IsNaN(Result.n) or IsInfinite(Result.n)) then begin WriteLn(ErrOutput, 'Runtime Error: Flottant corrompu (NaN/Inf) - Arret d''urgence'); vm.running := 0; end;
end;

procedure exec_node(var vm: TVM; n: PNode);
var
  v, l: Value;
  curr, stmtNode: PNode; ch, i, numDims, totalSlots, i1, i2, i3, offset, targetIdx: Integer;
  bufStr, varNameStr: string; p: PValue; fr: ^TForFrame; done: Boolean; newArr: PArrayData;
  code: Integer; inputInt: Int64; inputNum: Double;
begin
  if (n = nil) or (vm.running = 0) then Exit;
  case n^.k of
    N_SUB_DEF, N_FUNC_DEF: ;

    // --- INTEGRATION DE L'EXECUTION DE SELECT CASE ---
    N_SELECT:
      begin
        v := eval_node(vm, n^.p1);
        curr := n^.p2;
        done := False;
        while (curr <> nil) do
        begin
          if curr^.p1 = nil then
            done := True
          else
          begin
            stmtNode := curr^.p1;
            while stmtNode <> nil do
            begin
              l := eval_node(vm, stmtNode);
              if (v.t = T_STR) or (l.t = T_STR) then
              begin
                if StrComp(value_to_str(vm, v), value_to_str(vm, l)) = 0 then done := True;
              end
              else if (v.t = T_INT) and (l.t = T_INT) then
              begin
                if v.i = l.i then done := True;
              end
              else
              begin
                if to_num(v) = to_num(l) then done := True;
              end;
              if done then Break;
              stmtNode := stmtNode^.next;
            end;
          end;

          if done then
          begin
            stmtNode := curr^.p2;
            while (stmtNode <> nil) and (vm.running <> 0) and not vm.break_requested do
            begin
              exec_node(vm, stmtNode);
              stmtNode := stmtNode^.next;
            end;
            Break;
          end;
          curr := curr^.next;
        end;
      end;

    N_PRINT:
      begin
        bufStr := ''; curr := n^.p1;
        while curr <> nil do begin v := eval_node(vm, curr^.p1); bufStr := bufStr + string(value_to_str(vm, v)); curr := curr^.next; end;
        if Assigned(vm.on_print) then vm.on_print(bufStr, not n^.flag) else begin Write(bufStr); if not n^.flag then WriteLn; end;
      end;
    N_SLEEP: begin v := eval_node(vm, n^.p1); if to_int(v) > 0 then SysUtils.Sleep(UInt32(to_int(v))); end;
    N_CALL_STMT: call_builtin(vm, UpperCase(string(n^.str)), n^.p1);
    
    N_OPEN:
      begin
        ch := to_int(eval_node(vm, n^.p2));
        if Assigned(vm.vfs_open) then
        begin
          if not vm.vfs_open(@vm, ch, string(value_to_str(vm, eval_node(vm, n^.p1))), n^.str[0]) then begin WriteLn(ErrOutput, 'Runtime Error: VFS Open Denied'); vm.running := 0; end;
        end else WriteLn(ErrOutput, 'Runtime Error: Sandbox stricte. I/O Fichiers desactives.');
      end;
    N_CLOSE:
      begin
        if n^.p1 = nil then begin for i := 1 to 8 do if Assigned(vm.vfs_close) then vm.vfs_close(@vm, i); end
        else if Assigned(vm.vfs_close) then vm.vfs_close(@vm, to_int(eval_node(vm, n^.p1)));
      end;
    N_PRINT_HASH:
      begin
        ch := to_int(eval_node(vm, n^.p1)); bufStr := ''; curr := n^.p2;
        while curr <> nil do begin v := eval_node(vm, curr^.p1); bufStr := bufStr + string(value_to_str(vm, v)); curr := curr^.next; end;
        if Assigned(vm.vfs_print) then vm.vfs_print(@vm, ch, bufStr, not n^.flag);
      end;
    N_INPUT_HASH:
      begin
        if Assigned(vm.vfs_input) and vm.vfs_input(@vm, to_int(eval_node(vm, n^.p1)), bufStr) then
        begin
          varNameStr := string(n^.str);
          if (Length(varNameStr) > 0) and (varNameStr[Length(varNameStr)] = '$') then sym_set(vm.sym, n^.str, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))))
          else begin Val(bufStr, inputInt, code); if code = 0 then sym_set(vm.sym, n^.str, MakeInt(inputInt)) else begin Val(bufStr, inputNum, code); if code = 0 then sym_set(vm.sym, n^.str, MakeNum(inputNum)) else sym_set(vm.sym, n^.str, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr)))); end; end;
        end;
      end;

    N_DIM:
      begin
        p := sym_get(vm.sym, n^.str); if (p <> nil) and (p^.t = T_ARR) then begin WriteLn(ErrOutput, 'Runtime Error: Tableau deja dimensionne'); vm.running := 0; Exit; end;
        curr := n^.p1; numDims := 0; while curr <> nil do begin Inc(numDims); curr := curr^.next; end;
        if (numDims < 1) or (numDims > 3) then begin WriteLn(ErrOutput, 'Runtime Error: Dimensions 1..3 supportees'); vm.running := 0; Exit; end;
        curr := n^.p1; i1 := to_int(eval_node(vm, curr)); i2 := 0; i3 := 0;
        if numDims >= 2 then begin curr := curr^.next; i2 := to_int(eval_node(vm, curr)); end; if numDims = 3 then begin curr := curr^.next; i3 := to_int(eval_node(vm, curr)); end;
        newArr := arena_alloc(vm.sym^.a, sizeof(TArrayData)); if newArr = nil then begin vm.running := 0; Exit; end;
        newArr^.dims := numDims; newArr^.dim1 := i1; newArr^.dim2 := i2; newArr^.dim3 := i3;
        case numDims of 1: totalSlots := i1 + 1; 2: totalSlots := (i1 + 1) * (i2 + 1); 3: totalSlots := (i1 + 1) * (i2 + 1) * (i3 + 1); end;
        newArr^.data := arena_alloc(vm.sym^.a, totalSlots * sizeof(Value)); if newArr^.data = nil then begin vm.running := 0; Exit; end;
        for i := 0 to totalSlots - 1 do (newArr^.data + i)^ := MakeInt(0);
        sym_set(vm.sym, n^.str, MakeArr(newArr));
      end;
    N_ARRAY_SET:
      begin
        p := sym_get(vm.sym, n^.str); if (p = nil) or (p^.t <> T_ARR) or (p^.arr = nil) then begin WriteLn(ErrOutput, 'Runtime Error: Tableau inconnu'); vm.running := 0; Exit; end;
        i1 := to_int(eval_node(vm, n^.p1));
        if p^.arr^.dims = 1 then offset := i1
        else if p^.arr^.dims = 2 then begin i2 := to_int(eval_node(vm, n^.p1^.next)); offset := i1 * (p^.arr^.dim2 + 1) + i2; end
        else begin i2 := to_int(eval_node(vm, n^.p1^.next)); i3 := to_int(eval_node(vm, n^.p1^.next^.next)); offset := (i1 * (p^.arr^.dim2 + 1) + i2) * (p^.arr^.dim3 + 1) + i3; end;
        (p^.arr^.data + offset)^ := eval_node(vm, n^.p2);
      end;
    N_LET: begin v := eval_node(vm, n^.p1); sym_set(vm.sym, n^.str, v); end;
    N_IF_SINGLE: begin v := eval_node(vm, n^.p1); if to_bool(v) then exec_node(vm, n^.p2) else if n^.p3 <> nil then exec_node(vm, n^.p3); end;
    N_IF_BLOCK:
      begin
        curr := n^.p1;
        while curr <> nil do
        begin
          if (curr^.p1 = nil) or to_bool(eval_node(vm, curr^.p1)) then
          begin
            stmtNode := curr^.p2;
            while (stmtNode <> nil) and (vm.running <> 0) and not vm.break_requested do 
            begin 
              exec_node(vm, stmtNode); 
              stmtNode := stmtNode^.next; 
            end;
            Break;
          end;
          curr := curr^.next;
        end;
      end;
    N_WHILE:
      begin
        while (vm.running <> 0) and to_bool(eval_node(vm, n^.p1)) do
        begin
          Dec(vm.instructions_left); if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Boucle infinie'); vm.running := 0; Exit; end;
          stmtNode := n^.p2; 
          while (stmtNode <> nil) and (vm.running <> 0) and not vm.break_requested do 
          begin 
            exec_node(vm, stmtNode); 
            stmtNode := stmtNode^.next; 
          end;
          if vm.break_requested then begin vm.break_requested := False; Break; end;
        end;
      end;
    N_REPEAT:
      begin
        while vm.running <> 0 do
        begin
          Dec(vm.instructions_left); if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Boucle infinie'); vm.running := 0; Exit; end;
          stmtNode := n^.p2; 
          while (stmtNode <> nil) and (vm.running <> 0) and not vm.break_requested do 
          begin 
            exec_node(vm, stmtNode); 
            stmtNode := stmtNode^.next; 
          end;
          if vm.break_requested then begin vm.break_requested := False; Break; end;
          if (n^.p1 <> nil) and to_bool(eval_node(vm, n^.p1)) then Break;
        end;
      end;
    N_BREAK: vm.break_requested := True;
    N_GOTO:
      begin
        if n^.int_val >= 0 then targetIdx := label_find_num(vm.labels^, n^.int_val) else targetIdx := label_find_text(vm.labels^, n^.str);
        if targetIdx < 0 then begin WriteLn(ErrOutput, 'Runtime Error: Cible de saut introuvable'); vm.running := 0; end else vm.pc := targetIdx - 1;
      end;
    N_GOSUB:
      begin
        if vm.callsp >= High(vm.callstack) then begin WriteLn(ErrOutput, 'Runtime Error: Callstack Overflow'); vm.running := 0; Exit; end;
        if n^.int_val >= 0 then targetIdx := label_find_num(vm.labels^, n^.int_val) else targetIdx := label_find_text(vm.labels^, n^.str);
        if targetIdx < 0 then begin WriteLn(ErrOutput, 'Runtime Error: Cible GOSUB introuvable'); vm.running := 0; end
        else begin vm.callstack[vm.callsp] := vm.pc + 1; Inc(vm.callsp); vm.pc := targetIdx - 1; end;
      end;
    N_RETURN:
      begin
        if vm.callsp <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: RETURN sans GOSUB'); vm.running := 0; Exit; end;
        Dec(vm.callsp); vm.pc := vm.callstack[vm.callsp] - 1;
      end;
    N_FOR:
      begin
        v := eval_node(vm, n^.p1); sym_set(vm.sym, n^.str, v);
        if vm.forsp >= High(vm.forstk) then begin WriteLn(ErrOutput, 'Runtime Error: FOR Stack Overflow'); vm.running := 0; Exit; end;
        fr := @vm.forstk[vm.forsp]; fr^.var_name := n^.str; fr^.return_stmt_idx := vm.pc + 1;
        fr^.to_val := eval_node(vm, n^.p2); fr^.step_val := eval_node(vm, n^.p3); Inc(vm.forsp);
      end;
    N_NEXT:
      begin
        if vm.forsp <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: NEXT sans FOR'); vm.running := 0; Exit; end;
        if vm.break_requested then begin vm.break_requested := False; Dec(vm.forsp); Exit; end;
        fr := @vm.forstk[vm.forsp - 1]; p := sym_get(vm.sym, fr^.var_name);
        if p = nil then begin WriteLn(ErrOutput, 'Runtime Error: Variable FOR introuvable'); vm.running := 0; Exit; end;
        if (p^.t = T_INT) and (fr^.step_val.t = T_INT) and (fr^.to_val.t = T_INT) then
        begin
          p^.i := p^.i + fr^.step_val.i;
          if fr^.step_val.i >= 0 then done := (p^.i > fr^.to_val.i) else done := (p^.i < fr^.to_val.i);
        end else
        begin
          p^ := MakeNum(to_num(p^) + to_num(fr^.step_val));
          if to_num(fr^.step_val) >= 0.0 then done := (p^.n > to_num(fr^.to_val)) else done := (p^.n < to_num(fr^.to_val));
        end;
        if not done then vm.pc := fr^.return_stmt_idx - 1 else Dec(vm.forsp);
      end;
    N_INPUT:
      begin
        bufStr := ''; if n^.str <> nil then bufStr := string(n^.str) else bufStr := '? ';
        if Assigned(vm.on_input) then vm.on_input(bufStr, varNameStr) else begin Write(bufStr); ReadLn(varNameStr); end;
        bufStr := varNameStr; varNameStr := string(n^.p1^.str);
        if (Length(varNameStr) > 0) and (varNameStr[Length(varNameStr)] = '$') then sym_set(vm.sym, n^.p1^.str, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))))
        else begin Val(bufStr, inputInt, code); if code = 0 then sym_set(vm.sym, n^.p1^.str, MakeInt(inputInt)) else begin Val(bufStr, inputNum, code); if code = 0 then sym_set(vm.sym, n^.p1^.str, MakeNum(inputNum)) else sym_set(vm.sym, n^.p1^.str, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr)))); end; end;
      end;
    N_END: vm.running := 0;
  end;
end;

function vm_run(var vm: TVM): Integer;
begin
  while (vm.pc >= 0) and (vm.pc < Length(vm.stmts)) and (vm.running <> 0) do
  begin
    Dec(vm.instructions_left);
    if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Limite Instructions Depassee'); vm.running := 0; Break; end;

    exec_node(vm, vm.stmts[vm.pc]);

    if vm.break_requested then
    begin
      vm.break_requested := False;
      if vm.forsp > 0 then begin while (vm.pc < Length(vm.stmts)) and (vm.stmts[vm.pc]^.k <> N_NEXT) do Inc(vm.pc); Dec(vm.forsp); end;
    end;
    Inc(vm.pc);
  end;
  Result := 0;
end;

end.