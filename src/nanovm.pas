unit NanoVM;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, NanoTypes;

type
  PVM = ^TVM;
  TForeignFunction = function(vm: PVM; const args: array of Value): Value;

  TFFIRecord = record
    name: string;
    func: TForeignFunction;
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

    file_channels: array[1..8] of TextFile;
    file_open: array[1..8] of Boolean;
    file_mode: array[1..8] of Char;

    on_print: TPrintCallback;
    on_input: TInputCallback;

    ffi_funcs: array of TFFIRecord;
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

implementation

procedure vm_set_int(var vm: TVM; const name: string; val: Int64); begin sym_set(vm.sym^, PChar(name), MakeInt(val)); end;
procedure vm_set_num(var vm: TVM; const name: string; val: Double); begin sym_set(vm.sym^, PChar(name), MakeNum(val)); end;
procedure vm_set_str(var vm: TVM; const name: string; const val: string); begin sym_set(vm.sym^, PChar(name), MakeStr(arena_strdup(vm.sym^.a, PChar(val)))); end;

function vm_get_int(var vm: TVM; const name: string; defVal: Int64 = 0): Int64;
var p: PValue; begin p := sym_get(vm.sym^, PChar(name)); if p <> nil then Result := to_int(p^) else Result := defVal; end;
function vm_get_num(var vm: TVM; const name: string; defVal: Double = 0.0): Double;
var p: PValue; begin p := sym_get(vm.sym^, PChar(name)); if p <> nil then Result := to_num(p^) else Result := defVal; end;

function value_to_str(var vm: TVM; const v: Value): PChar; forward;
function vm_get_str(var vm: TVM; const name: string; const defVal: string = ''): string;
var p: PValue; begin p := sym_get(vm.sym^, PChar(name)); if p <> nil then Result := string(value_to_str(vm, p^)) else Result := defVal; end;

procedure vm_register_ffi(var vm: TVM; const name: string; func: TForeignFunction);
var i: Integer;
begin
  i := Length(vm.ffi_funcs);
  SetLength(vm.ffi_funcs, i + 1);
  vm.ffi_funcs[i].name := UpperCase(name);
  vm.ffi_funcs[i].func := func;
end;

procedure vm_init(var vm: TVM; sym: PSymTab; const stmts: array of PNode; labels: PLabelMap);
var i: Integer;
begin
  FillChar(vm, sizeof(vm), 0);
  vm.sym := sym; vm.labels := labels; vm.running := 1; vm.pc := 0; vm.break_requested := False;
  vm.instructions_left := DEFAULT_MAX_INSTRUCTIONS;
  SetLength(vm.stmts, Length(stmts));
  for i := 0 to High(stmts) do vm.stmts[i] := stmts[i];
  for i := 1 to 8 do vm.file_open[i] := False;
  vm.on_print := nil; vm.on_input := nil;
  SetLength(vm.ffi_funcs, 0);
  Randomize;
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

function call_builtin(var vm: TVM; const fnName: string; const args: array of Value): Value;
var
  argCount, strLenVal, startPos, subLen, ch, i: Integer;
  valS, subStr: string; charBuf: array[0..1] of Char;
  code: Integer; intVal: Int64; floatVal: Double;
begin
  for i := 0 to High(vm.ffi_funcs) do
  begin
    if vm.ffi_funcs[i].name = UpperCase(fnName) then
      Exit(vm.ffi_funcs[i].func(@vm, args));
  end;

  argCount := Length(args);

  if fnName = 'ABS' then
  begin
    if argCount < 1 then Exit(MakeInt(0));
    if args[0].t = T_INT then Exit(MakeInt(Abs(args[0].i))) else Exit(MakeNum(Abs(to_num(args[0]))));
  end
  else if fnName = 'INT' then begin if argCount < 1 then Exit(MakeInt(0)); Exit(MakeInt(to_int(args[0]))); end
  else if fnName = 'TIMER' then Exit(MakeInt(GetTickCount64))
  else if fnName = 'SQR' then
  begin
    if argCount < 1 then Exit(MakeNum(0.0));
    if to_num(args[0]) < 0.0 then begin WriteLn(ErrOutput, 'Runtime Warning: SQR negatif'); Exit(MakeNum(0.0)); end;
    Exit(MakeNum(Sqrt(to_num(args[0]))));
  end
  else if fnName = 'RND' then
  begin
    if argCount = 0 then Exit(MakeNum(Random))
    else begin intVal := to_int(args[0]); if intVal <= 0 then Exit(MakeNum(Random)) else Exit(MakeInt(Random(intVal))); end;
  end
  else if fnName = 'SIN' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Sin(to_num(args[0])))); end
  else if fnName = 'COS' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Cos(to_num(args[0])))); end
  else if fnName = 'TAN' then begin if argCount < 1 then Exit(MakeNum(0.0)); Exit(MakeNum(Tan(to_num(args[0])))); end
  else if fnName = 'LEN' then
  begin
    if argCount < 1 then Exit(MakeInt(0));
    if args[0].t = T_STR then begin if args[0].s = nil then Exit(MakeInt(0)) else Exit(MakeInt(StrLen(args[0].s))); end
    else Exit(MakeInt(Length(string(value_to_str(vm, args[0])))));
  end
  else if fnName = 'LEFT$' then
  begin
    if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, '')));
    valS := string(value_to_str(vm, args[0])); subLen := to_int(args[1]);
    if subLen <= 0 then subStr := '' else subStr := Copy(valS, 1, subLen);
    Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr))));
  end
  else if fnName = 'RIGHT$' then
  begin
    if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, '')));
    valS := string(value_to_str(vm, args[0])); subLen := to_int(args[1]); strLenVal := Length(valS);
    if subLen <= 0 then subStr := '' else if subLen >= strLenVal then subStr := valS else subStr := Copy(valS, strLenVal - subLen + 1, subLen);
    Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr))));
  end
  else if fnName = 'MID$' then
  begin
    if argCount < 2 then Exit(MakeStr(arena_strdup(vm.sym^.a, '')));
    valS := string(value_to_str(vm, args[0])); startPos := to_int(args[1]);
    if argCount >= 3 then subLen := to_int(args[2]) else subLen := Length(valS);
    if (startPos < 1) or (startPos > Length(valS)) or (subLen <= 0) then subStr := '' else subStr := Copy(valS, startPos, subLen);
    Exit(MakeStr(arena_strdup(vm.sym^.a, PChar(subStr))));
  end
  else if fnName = 'CHR$' then
  begin
    if argCount < 1 then Exit(MakeStr(arena_strdup(vm.sym^.a, '')));
    intVal := to_int(args[0]) and 255; charBuf[0] := Chr(intVal); charBuf[1] := #0;
    Exit(MakeStr(arena_strdup(vm.sym^.a, charBuf)));
  end
  else if fnName = 'ASC' then
  begin
    if argCount < 1 then Exit(MakeInt(0)); valS := string(value_to_str(vm, args[0]));
    if Length(valS) = 0 then Exit(MakeInt(0)) else Exit(MakeInt(Ord(valS[1])));
  end
  else if fnName = 'STR$' then
  begin
    if argCount < 1 then Exit(MakeStr(arena_strdup(vm.sym^.a, '')));
    Exit(MakeStr(value_to_str(vm, args[0])));
  end
  else if fnName = 'VAL' then
  begin
    if argCount < 1 then Exit(MakeInt(0)); valS := Trim(string(value_to_str(vm, args[0])));
    Val(valS, intVal, code); if code = 0 then Exit(MakeInt(intVal));
    Val(valS, floatVal, code); if code = 0 then Exit(MakeNum(floatVal)) else Exit(MakeInt(0));
  end
  else if fnName = 'EOF' then
  begin
    if argCount < 1 then Exit(MakeBool(True));
    ch := to_int(args[0]);
    if (ch >= 1) and (ch <= 8) and vm.file_open[ch] then Exit(MakeBool(EOF(vm.file_channels[ch]))) else Exit(MakeBool(True));
  end;

  WriteLn(ErrOutput, 'Runtime Error: Fonction ou Tableau inconnu: ', fnName);
  vm.running := 0;
  Result := MakeNil;
end;

function eval_node(var vm: TVM; n: PNode): Value;
var
  l, r: Value; sL, sR, concatBuf: PChar; lenL, lenR: SizeInt;
  c, i, numIndices, i1, i2, i3, offset: Integer; p: PValue; evalArgs: array of Value; arrData: PArrayData;
begin
  if (n = nil) or (vm.running = 0) then Exit(MakeNil);

  Inc(vm.call_depth);
  if vm.call_depth > 512 then begin WriteLn(ErrOutput, 'Runtime Error: Stack Overflow'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;

  case n^.k of
    N_INT:  Result := MakeInt(n^.int_val);
    N_NUM:  Result := MakeNum(n^.num);
    N_BOOL: Result := MakeBool(n^.bool_val);
    N_STR:  Result := MakeStr(n^.str);
    N_VAR:
      begin
        p := sym_get(vm.sym^, n^.name);
        if p <> nil then Result := p^ else Result := MakeInt(0);
      end;
    N_ARRAY_GET:
      begin
        p := sym_get(vm.sym^, n^.arr_get_name);
        if (p = nil) or (p^.t <> T_ARR) or (p^.arr = nil) then
        begin
          SetLength(evalArgs, Length(n^.arr_get_indices));
          for i := 0 to High(n^.arr_get_indices) do evalArgs[i] := eval_node(vm, n^.arr_get_indices[i]);
          Result := call_builtin(vm, UpperCase(string(n^.arr_get_name)), evalArgs);
          Dec(vm.call_depth); Exit;
        end;
        arrData := p^.arr; numIndices := Length(n^.arr_get_indices);
        if numIndices <> arrData^.dims then begin WriteLn(ErrOutput, 'Runtime Error: Indices invalides'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;
        i1 := to_int(eval_node(vm, n^.arr_get_indices[0]));
        if (i1 < 0) or (i1 > arrData^.dim1) then begin WriteLn(ErrOutput, 'Runtime Error: Indice hors limites'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;

        if arrData^.dims = 1 then offset := i1
        else if arrData^.dims = 2 then
        begin
          i2 := to_int(eval_node(vm, n^.arr_get_indices[1]));
          if (i2 < 0) or (i2 > arrData^.dim2) then begin WriteLn(ErrOutput, 'Runtime Error: Indice hors limites'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;
          offset := i1 * (arrData^.dim2 + 1) + i2;
        end
        else
        begin
          i2 := to_int(eval_node(vm, n^.arr_get_indices[1])); i3 := to_int(eval_node(vm, n^.arr_get_indices[2]));
          if (i2 < 0) or (i2 > arrData^.dim2) or (i3 < 0) or (i3 > arrData^.dim3) then begin WriteLn(ErrOutput, 'Runtime Error: Indices hors limites'); vm.running := 0; Dec(vm.call_depth); Exit(MakeNil); end;
          offset := (i1 * (arrData^.dim2 + 1) + i2) * (arrData^.dim3 + 1) + i3;
        end;
        Result := (arrData^.data + offset)^;
      end;
    N_CALL:
      begin
        SetLength(evalArgs, Length(n^.call_args));
        for i := 0 to High(n^.call_args) do evalArgs[i] := eval_node(vm, n^.call_args[i]);
        Result := call_builtin(vm, UpperCase(string(n^.call_name)), evalArgs);
      end;
    N_UNOP:
      begin
        l := eval_node(vm, n^.un_child);
        if n^.un_tok = T_NOT then
        begin
          if l.t = T_BOOL then Result := MakeBool(not l.b)
          else if l.t = T_INT then Result := MakeInt(not l.i)
          else Result := MakeBool(not to_bool(l));
        end
        else if n^.un_op = '-' then
        begin
          if l.t = T_INT then Result := MakeInt(-l.i) else Result := MakeNum(-to_num(l));
        end else Result := MakeNil;
      end;
    N_BINOP:
      begin
        l := eval_node(vm, n^.bin_l); r := eval_node(vm, n^.bin_r);
        if n^.bin_op in [T_AND, T_OR, T_XOR] then
        begin
          if (l.t = T_BOOL) and (r.t = T_BOOL) then
          begin
            case n^.bin_op of T_AND: Result := MakeBool(l.b and r.b); T_OR: Result := MakeBool(l.b or r.b); T_XOR: Result := MakeBool(l.b xor r.b); end;
          end
          else if (l.t = T_INT) and (r.t = T_INT) then
          begin
            case n^.bin_op of T_AND: Result := MakeInt(l.i and r.i); T_OR: Result := MakeInt(l.i or r.i); T_XOR: Result := MakeInt(l.i xor r.i); end;
          end
          else
          begin
            case n^.bin_op of T_AND: Result := MakeBool(to_bool(l) and to_bool(r)); T_OR: Result := MakeBool(to_bool(l) or to_bool(r)); T_XOR: Result := MakeBool(to_bool(l) xor to_bool(r)); end;
          end;
        end
        else if (l.t = T_STR) or (r.t = T_STR) then
        begin
          sL := value_to_str(vm, l); sR := value_to_str(vm, r);
          if n^.bin_op = T_PLUS then
          begin
            lenL := StrLen(sL); lenR := StrLen(sR); concatBuf := arena_alloc(vm.sym^.a, lenL + lenR + 1);
            if concatBuf <> nil then begin if lenL > 0 then Move(sL^, concatBuf^, lenL); if lenR > 0 then Move(sR^, (concatBuf + lenL)^, lenR); concatBuf[lenL + lenR] := #0; Result := MakeStr(concatBuf); end else Result := MakeNil;
          end
          else
          begin
            c := StrComp(sL, sR);
            case n^.bin_op of T_EQ: Result := MakeBool(c = 0); T_NEQ: Result := MakeBool(c <> 0); T_LT: Result := MakeBool(c < 0); T_GT: Result := MakeBool(c > 0); T_LTE: Result := MakeBool(c <= 0); T_GTE: Result := MakeBool(c >= 0); else Result := MakeNil; end;
          end;
        end
        else if (l.t = T_INT) and (r.t = T_INT) and (n^.bin_op in [T_PLUS, T_MINUS, T_STAR, T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE]) then
        begin
          case n^.bin_op of T_PLUS: Result := MakeInt(l.i + r.i); T_MINUS: Result := MakeInt(l.i - r.i); T_STAR: Result := MakeInt(l.i * r.i); T_EQ: Result := MakeBool(l.i = r.i); T_NEQ: Result := MakeBool(l.i <> r.i); T_LT: Result := MakeBool(l.i < r.i); T_GT: Result := MakeBool(l.i > r.i); T_LTE: Result := MakeBool(l.i <= r.i); T_GTE: Result := MakeBool(l.i >= r.i); else Result := MakeNil; end;
        end
        else
        begin
          case n^.bin_op of
            T_PLUS: Result := MakeNum(to_num(l) + to_num(r)); T_MINUS: Result := MakeNum(to_num(l) - to_num(r)); T_STAR: Result := MakeNum(to_num(l) * to_num(r));
            T_SLASH: if to_num(r) = 0.0 then begin WriteLn(ErrOutput, 'Runtime Warning: Div 0'); Result := MakeNum(0.0); end else Result := MakeNum(to_num(l) / to_num(r));
            T_CARET: Result := MakeNum(Power(to_num(l), to_num(r))); T_EQ: Result := MakeBool(to_num(l) = to_num(r)); T_NEQ: Result := MakeBool(to_num(l) <> to_num(r)); T_LT: Result := MakeBool(to_num(l) < to_num(r)); T_GT: Result := MakeBool(to_num(l) > to_num(r)); T_LTE: Result := MakeBool(to_num(l) <= to_num(r)); T_GTE: Result := MakeBool(to_num(l) >= to_num(r));
          else Result := MakeNil; end;
        end;
      end;
  else Result := MakeNil;
  end;
  Dec(vm.call_depth);
end;

procedure exec_node(var vm: TVM; n: PNode);
var
  v: Value; targetIdx, retPc, i, j, numDims, totalSlots, i1, i2, i3, offset, ch: Integer;
  d1, d2, d3: Integer;
  p: PValue; fr: ^TForFrame; done: Boolean; sleepMs: Int64; evalArgs: array of Value;
  bufStr, varNameStr, filename: string; code: Integer; inputInt: Int64; inputNum: Double;
  newArr: PArrayData; arrData: PArrayData;
begin
  if (n = nil) or (vm.running = 0) then Exit;
  case n^.k of
    N_PRINT:
      begin
        bufStr := '';
        for i := 0 to High(n^.print_args) do
        begin
          v := eval_node(vm, n^.print_args[i].expr);
          bufStr := bufStr + string(value_to_str(vm, v));
        end;
        if Assigned(vm.on_print) then vm.on_print(bufStr, not n^.print_trailing_sep)
        else begin Write(bufStr); if not n^.print_trailing_sep then WriteLn; end;
      end;

    N_SLEEP:
      begin
        v := eval_node(vm, n^.sleep_expr);
        sleepMs := to_int(v);
        if sleepMs > 0 then SysUtils.Sleep(UInt32(sleepMs));
      end;

    N_CALL_STMT:
      begin
        SetLength(evalArgs, Length(n^.call_stmt_args));
        for i := 0 to High(n^.call_stmt_args) do evalArgs[i] := eval_node(vm, n^.call_stmt_args[i]);
        call_builtin(vm, UpperCase(string(n^.call_stmt_name)), evalArgs);
      end;

    N_OPEN:
      begin
        filename := string(value_to_str(vm, eval_node(vm, n^.open_file_expr)));
        ch := to_int(eval_node(vm, n^.open_channel));
        if (ch < 1) or (ch > 8) then begin WriteLn(ErrOutput, 'Runtime Error: Canal fichier invalide (1..8): ', ch); vm.running := 0; Exit; end;
        if vm.file_open[ch] then begin CloseFile(vm.file_channels[ch]); vm.file_open[ch] := False; end;
        AssignFile(vm.file_channels[ch], filename);
        {$I-}
        if n^.open_mode = 'O' then Rewrite(vm.file_channels[ch])
        else if n^.open_mode = 'A' then Append(vm.file_channels[ch])
        else Reset(vm.file_channels[ch]);
        {$I+}
        if IOResult <> 0 then begin WriteLn(ErrOutput, 'Runtime Error: Impossible d''ouvrir le fichier ', filename); vm.running := 0; Exit; end;
        vm.file_open[ch] := True; vm.file_mode[ch] := n^.open_mode;
      end;

    N_CLOSE:
      begin
        if n^.close_channel = nil then
        begin
          for i := 1 to 8 do if vm.file_open[i] then begin CloseFile(vm.file_channels[i]); vm.file_open[i] := False; end;
        end
        else
        begin
          ch := to_int(eval_node(vm, n^.close_channel));
          if (ch >= 1) and (ch <= 8) and vm.file_open[ch] then begin CloseFile(vm.file_channels[ch]); vm.file_open[ch] := False; end;
        end;
      end;

    N_PRINT_HASH:
      begin
        ch := to_int(eval_node(vm, n^.print_hash_channel));
        if (ch >= 1) and (ch <= 8) and vm.file_open[ch] and (vm.file_mode[ch] <> 'I') then
        begin
          for i := 0 to High(n^.print_args) do
          begin
            v := eval_node(vm, n^.print_args[i].expr);
            case v.t of
              T_STR:  if v.s <> nil then Write(vm.file_channels[ch], v.s);
              T_INT:  Write(vm.file_channels[ch], v.i);
              T_BOOL: if v.b then Write(vm.file_channels[ch], 'TRUE') else Write(vm.file_channels[ch], 'FALSE');
              T_NUM:  Write(vm.file_channels[ch], v.n:0:4);
              T_ARR:  Write(vm.file_channels[ch], '<ARRAY>');
            end;
          end;
          if not n^.print_trailing_sep then WriteLn(vm.file_channels[ch]);
        end
        else begin WriteLn(ErrOutput, 'Runtime Error: Canal ecriture invalide: ', ch); vm.running := 0; Exit; end;
      end;

    N_INPUT_HASH:
      begin
        ch := to_int(eval_node(vm, n^.input_hash_channel));
        if (ch >= 1) and (ch <= 8) and vm.file_open[ch] and (vm.file_mode[ch] = 'I') then
        begin
          if not EOF(vm.file_channels[ch]) then
          begin
            ReadLn(vm.file_channels[ch], bufStr);
            varNameStr := string(n^.input_name);
            if (Length(varNameStr) > 0) and (varNameStr[Length(varNameStr)] = '$') then sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))))
            else
            begin
              Val(bufStr, inputInt, code);
              if code = 0 then sym_set(vm.sym^, n^.input_name, MakeInt(inputInt))
              else
              begin
                Val(bufStr, inputNum, code);
                if code = 0 then sym_set(vm.sym^, n^.input_name, MakeNum(inputNum)) else sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))));
              end;
            end;
          end;
        end
        else begin WriteLn(ErrOutput, 'Runtime Error: Canal lecture invalide: ', ch); vm.running := 0; Exit; end;
      end;

    N_DIM:
      begin
        p := sym_get(vm.sym^, n^.dim_name);
        if (p <> nil) and (p^.t = T_ARR) then begin WriteLn(ErrOutput, 'Runtime Error: Tableau deja dimensionne'); vm.running := 0; Exit; end;
        numDims := Length(n^.dim_indices);
        if (numDims < 1) or (numDims > 3) then begin WriteLn(ErrOutput, 'Runtime Error: Dimensions 1..3 supportees'); vm.running := 0; Exit; end;
        d1 := to_int(eval_node(vm, n^.dim_indices[0])); d2 := 0; d3 := 0;
        if numDims >= 2 then d2 := to_int(eval_node(vm, n^.dim_indices[1])); if numDims = 3 then d3 := to_int(eval_node(vm, n^.dim_indices[2]));
        if (d1 < 0) or (d2 < 0) or (d3 < 0) then begin WriteLn(ErrOutput, 'Runtime Error: Dimension negative'); vm.running := 0; Exit; end;
        newArr := arena_alloc(vm.sym^.a, sizeof(TArrayData)); if newArr = nil then begin vm.running := 0; Exit; end;
        newArr^.dims := numDims; newArr^.dim1 := d1; newArr^.dim2 := d2; newArr^.dim3 := d3;
        case numDims of 1: totalSlots := d1 + 1; 2: totalSlots := (d1 + 1) * (d2 + 1); 3: totalSlots := (d1 + 1) * (d2 + 1) * (d3 + 1); end;
        newArr^.data := arena_alloc(vm.sym^.a, totalSlots * sizeof(Value)); if newArr^.data = nil then begin vm.running := 0; Exit; end;
        for i := 0 to totalSlots - 1 do (newArr^.data + i)^ := MakeInt(0);
        sym_set(vm.sym^, n^.dim_name, MakeArr(newArr));
      end;

    N_ARRAY_SET:
      begin
        p := sym_get(vm.sym^, n^.arr_set_name);
        if (p = nil) or (p^.t <> T_ARR) or (p^.arr = nil) then begin WriteLn(ErrOutput, 'Runtime Error: Tableau inconnu'); vm.running := 0; Exit; end;
        arrData := p^.arr; numDims := Length(n^.arr_set_indices);
        if numDims <> arrData^.dims then begin WriteLn(ErrOutput, 'Runtime Error: Indices incorrects'); vm.running := 0; Exit; end;
        i1 := to_int(eval_node(vm, n^.arr_set_indices[0])); if (i1 < 0) or (i1 > arrData^.dim1) then begin WriteLn(ErrOutput, 'Runtime Error: Indice 1 hors limites'); vm.running := 0; Exit; end;
        if arrData^.dims = 1 then offset := i1
        else if arrData^.dims = 2 then begin i2 := to_int(eval_node(vm, n^.arr_set_indices[1])); if (i2 < 0) or (i2 > arrData^.dim2) then begin WriteLn(ErrOutput, 'Runtime Error: Indice 2 hors limites'); vm.running := 0; Exit; end; offset := i1 * (arrData^.dim2 + 1) + i2; end
        else begin i2 := to_int(eval_node(vm, n^.arr_set_indices[1])); i3 := to_int(eval_node(vm, n^.arr_set_indices[2])); if (i2 < 0) or (i2 > arrData^.dim2) or (i3 < 0) or (i3 > arrData^.dim3) then begin WriteLn(ErrOutput, 'Runtime Error: Indices hors limites'); vm.running := 0; Exit; end; offset := (i1 * (arrData^.dim2 + 1) + i2) * (arrData^.dim3 + 1) + i3; end;
        (arrData^.data + offset)^ := eval_node(vm, n^.arr_set_expr);
      end;

    N_LET: begin v := eval_node(vm, n^.let_expr); sym_set(vm.sym^, n^.let_name, v); end;

    N_IF_SINGLE: begin v := eval_node(vm, n^.if_cond); if to_bool(v) then exec_node(vm, n^.if_thenb) else if n^.if_elseb <> nil then exec_node(vm, n^.if_elseb); end;

    N_IF_BLOCK:
      begin
        for i := 0 to High(n^.if_branches) do
        begin
          if (n^.if_branches[i].cond = nil) or to_bool(eval_node(vm, n^.if_branches[i].cond)) then
          begin
            for j := 0 to High(n^.if_branches[i].body) do begin exec_node(vm, n^.if_branches[i].body[j]); if (vm.running = 0) or vm.break_requested then Break; end;
            Break;
          end;
        end;
      end;

    N_WHILE:
      begin
        while (vm.running <> 0) and to_bool(eval_node(vm, n^.while_cond)) do
        begin
          Dec(vm.instructions_left); if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Boucle infinie'); vm.running := 0; Exit; end;
          for i := 0 to High(n^.while_body) do begin exec_node(vm, n^.while_body[i]); if (vm.running = 0) or vm.break_requested then Break; end;
          if vm.break_requested then begin vm.break_requested := False; Break; end;
        end;
      end;

    N_REPEAT:
      begin
        while vm.running <> 0 do
        begin
          Dec(vm.instructions_left); if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Boucle infinie'); vm.running := 0; Exit; end;
          for i := 0 to High(n^.repeat_body) do begin exec_node(vm, n^.repeat_body[i]); if (vm.running = 0) or vm.break_requested then Break; end;
          if vm.break_requested then begin vm.break_requested := False; Break; end;
          if (n^.repeat_cond <> nil) and to_bool(eval_node(vm, n^.repeat_cond)) then Break;
        end;
      end;

    N_BREAK: vm.break_requested := True;

    N_GOTO:
      begin
        if n^.goto_target_num >= 0 then targetIdx := label_find_num(vm.labels^, n^.goto_target_num) else targetIdx := label_find_text(vm.labels^, n^.goto_target_lbl);
        if targetIdx < 0 then begin WriteLn(ErrOutput, 'Runtime Error: Cible de saut introuvable'); vm.running := 0; end else vm.pc := targetIdx - 1;
      end;

    N_GOSUB:
      begin
        if vm.callsp >= High(vm.callstack) then begin WriteLn(ErrOutput, 'Runtime Error: Callstack Overflow'); vm.running := 0; Exit; end;
        if n^.goto_target_num >= 0 then targetIdx := label_find_num(vm.labels^, n^.goto_target_num) else targetIdx := label_find_text(vm.labels^, n^.goto_target_lbl);
        if targetIdx < 0 then begin WriteLn(ErrOutput, 'Runtime Error: Cible GOSUB introuvable'); vm.running := 0; end
        else begin vm.callstack[vm.callsp] := vm.pc + 1; Inc(vm.callsp); vm.pc := targetIdx - 1; end;
      end;

    N_RETURN:
      begin
        if vm.callsp <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: RETURN sans GOSUB'); vm.running := 0; Exit; end;
        Dec(vm.callsp); retPc := vm.callstack[vm.callsp]; vm.pc := retPc - 1;
      end;

    N_FOR:
      begin
        v := eval_node(vm, n^.for_from); sym_set(vm.sym^, n^.for_var, v);
        if vm.forsp >= High(vm.forstk) then begin WriteLn(ErrOutput, 'Runtime Error: FOR Stack Overflow'); vm.running := 0; Exit; end;
        fr := @vm.forstk[vm.forsp]; fr^.var_name := n^.for_var; fr^.return_stmt_idx := vm.pc + 1;
        fr^.to_val := eval_node(vm, n^.for_to); fr^.step_val := eval_node(vm, n^.for_step); Inc(vm.forsp);
      end;

    N_NEXT:
      begin
        if vm.forsp <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: NEXT sans FOR'); vm.running := 0; Exit; end;
        if vm.break_requested then begin vm.break_requested := False; Dec(vm.forsp); Exit; end;
        fr := @vm.forstk[vm.forsp - 1]; p := sym_get(vm.sym^, fr^.var_name);
        if p = nil then begin WriteLn(ErrOutput, 'Runtime Error: Variable FOR introuvable'); vm.running := 0; Exit; end;
        if (p^.t = T_INT) and (fr^.step_val.t = T_INT) and (fr^.to_val.t = T_INT) then
        begin
          p^.i := p^.i + fr^.step_val.i;
          if fr^.step_val.i >= 0 then done := (p^.i > fr^.to_val.i) else done := (p^.i < fr^.to_val.i);
        end
        else
        begin
          p^ := MakeNum(to_num(p^) + to_num(fr^.step_val));
          if to_num(fr^.step_val) >= 0.0 then done := (p^.n > to_num(fr^.to_val)) else done := (p^.n < to_num(fr^.to_val));
        end;
        if not done then vm.pc := fr^.return_stmt_idx - 1 else Dec(vm.forsp);
      end;

    N_INPUT:
      begin
        bufStr := '';
        if n^.input_prompt <> nil then bufStr := string(n^.input_prompt) else bufStr := '? ';
        
        if Assigned(vm.on_input) then vm.on_input(bufStr, varNameStr)
        else begin Write(bufStr); ReadLn(varNameStr); end;

        bufStr := varNameStr;
        varNameStr := string(n^.input_name);
        
        if (Length(varNameStr) > 0) and (varNameStr[Length(varNameStr)] = '$') then sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))))
        else
        begin
          Val(bufStr, inputInt, code); if code = 0 then sym_set(vm.sym^, n^.input_name, MakeInt(inputInt))
          else begin Val(bufStr, inputNum, code); if code = 0 then sym_set(vm.sym^, n^.input_name, MakeNum(inputNum)) else sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr)))); end;
        end;
      end;

    N_END: vm.running := 0;
  end;
end;

function vm_run(var vm: TVM): Integer;
var i: Integer;
begin
  while (vm.pc >= 0) and (vm.pc < Length(vm.stmts)) and (vm.running <> 0) do
  begin
    Dec(vm.instructions_left);
    if vm.instructions_left <= 0 then begin WriteLn(ErrOutput, 'Runtime Error: Instruction budget exceeded'); vm.running := 0; Break; end;

    exec_node(vm, vm.stmts[vm.pc]);

    if vm.break_requested then
    begin
      vm.break_requested := False;
      if vm.forsp > 0 then
      begin
        while (vm.pc < Length(vm.stmts)) and (vm.stmts[vm.pc]^.k <> N_NEXT) do Inc(vm.pc);
        Dec(vm.forsp);
      end;
    end;
    Inc(vm.pc);
  end;
  
  for i := 1 to 8 do
    if vm.file_open[i] then
    begin
      CloseFile(vm.file_channels[i]);
      vm.file_open[i] := False;
    end;

  Result := 0;
end;

end.