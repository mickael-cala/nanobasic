unit NanoVM;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, NanoTypes;

type
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
    forstk: array[0..63] of TForFrame;
    forsp: Integer;
    callstack: array[0..255] of Integer;
    callsp: Integer;
    call_depth: Integer;
  end;

procedure vm_init(var vm: TVM; sym: PSymTab; const stmts: array of PNode; labels: PLabelMap);
function vm_run(var vm: TVM): Integer;
function eval_node(var vm: TVM; n: PNode): Value;
procedure exec_node(var vm: TVM; n: PNode);

implementation

procedure vm_init(var vm: TVM; sym: PSymTab; const stmts: array of PNode; labels: PLabelMap);
var
  i: Integer;
begin
  FillChar(vm, sizeof(vm), 0);
  vm.sym := sym;
  vm.labels := labels;
  vm.running := 1;
  vm.pc := 0;
  SetLength(vm.stmts, Length(stmts));
  for i := 0 to High(stmts) do
    vm.stmts[i] := stmts[i];
end;

function value_to_str(var vm: TVM; const v: Value): PChar;
var
  buf: string;
begin
  case v.t of
    T_STR:
      begin
        if v.s = nil then Exit(arena_strdup(vm.sym^.a, ''))
        else Exit(v.s);
      end;
    T_INT:  buf := IntToStr(v.i);
    T_NUM:  buf := FloatToStr(v.n);
    T_BOOL: if v.b then buf := 'TRUE' else buf := 'FALSE';
  else
    buf := '';
  end;
  Result := arena_strdup(vm.sym^.a, PChar(buf));
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
    N_INT:  Result := MakeInt(n^.int_val);
    N_NUM:  Result := MakeNum(n^.num);
    N_BOOL: Result := MakeBool(n^.bool_val);
    N_STR:  Result := MakeStr(n^.str);
    N_VAR:
      begin
        p := sym_get(vm.sym^, n^.name);
        if p <> nil then
          Result := p^
        else
          Result := MakeInt(0);
      end;
    N_UNOP:
      begin
        l := eval_node(vm, n^.un_child);
        if n^.un_op = '-' then
        begin
          if l.t = T_INT then Result := MakeInt(-l.i)
          else Result := MakeNum(-to_num(l));
        end
        else
          Result := MakeNil;
      end;
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
              T_EQ:  Result := MakeBool(c = 0);
              T_NEQ: Result := MakeBool(c <> 0);
              T_LT:  Result := MakeBool(c < 0);
              T_GT:  Result := MakeBool(c > 0);
              T_LTE: Result := MakeBool(c <= 0);
              T_GTE: Result := MakeBool(c >= 0);
            else
              Result := MakeNil;
            end;
          end;
        end
        else if (l.t = T_INT) and (r.t = T_INT) and (n^.bin_op in [T_PLUS, T_MINUS, T_STAR, T_EQ, T_NEQ, T_LT, T_GT, T_LTE, T_GTE]) then
        begin
          case n^.bin_op of
            T_PLUS:  Result := MakeInt(l.i + r.i);
            T_MINUS: Result := MakeInt(l.i - r.i);
            T_STAR:  Result := MakeInt(l.i * r.i);
            T_EQ:    Result := MakeBool(l.i = r.i);
            T_NEQ:   Result := MakeBool(l.i <> r.i);
            T_LT:    Result := MakeBool(l.i < r.i);
            T_GT:    Result := MakeBool(l.i > r.i);
            T_LTE:   Result := MakeBool(l.i <= r.i);
            T_GTE:   Result := MakeBool(l.i >= r.i);
          else
            Result := MakeNil;
          end;
        end
        else
        begin
          case n^.bin_op of
            T_PLUS:  Result := MakeNum(to_num(l) + to_num(r));
            T_MINUS: Result := MakeNum(to_num(l) - to_num(r));
            T_STAR:  Result := MakeNum(to_num(l) * to_num(r));
            T_SLASH:
              if to_num(r) = 0.0 then
              begin
                WriteLn(ErrOutput, 'Runtime Warning: Division par zero');
                Result := MakeNum(0.0);
              end
              else
                Result := MakeNum(to_num(l) / to_num(r));
            T_CARET: Result := MakeNum(Power(to_num(l), to_num(r)));
            T_EQ:    Result := MakeBool(to_num(l) = to_num(r));
            T_NEQ:   Result := MakeBool(to_num(l) <> to_num(r));
            T_LT:    Result := MakeBool(to_num(l) < to_num(r));
            T_GT:    Result := MakeBool(to_num(l) > to_num(r));
            T_LTE:   Result := MakeBool(to_num(l) <= to_num(r));
            T_GTE:   Result := MakeBool(to_num(l) >= to_num(r));
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

procedure print_value_direct(const v: Value);
begin
  case v.t of
    T_STR:  if v.s <> nil then Write(v.s);
    T_INT:  Write(v.i);
    T_BOOL: if v.b then Write('TRUE') else Write('FALSE');
    T_NUM:  Write(v.n:0:4);
  else
    Write('NIL');
  end;
end;

procedure exec_node(var vm: TVM; n: PNode);
var
  v: Value;
  targetIdx, retPc, i: Integer;
  p: PValue;
  fr: ^TForFrame;
  done: Boolean;
  bufStr: string;
  code: Integer;
  inputInt: Int64;
  inputNum: Double;
begin
  if (n = nil) or (vm.running = 0) then Exit;
  case n^.k of
    N_PRINT:
      begin
        for i := 0 to High(n^.print_args) do
        begin
          v := eval_node(vm, n^.print_args[i].expr);
          print_value_direct(v);
        end;
        if not n^.print_trailing_sep then
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
        if to_bool(v) then
          exec_node(vm, n^.if_thenb)
        else if n^.if_elseb <> nil then
          exec_node(vm, n^.if_elseb);
      end;

    N_GOTO:
      begin
        targetIdx := label_find(vm.labels^, n^.goto_target);
        if targetIdx < 0 then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Ligne cible ', n^.goto_target, ' introuvable');
          vm.running := 0;
        end
        else
          vm.pc := targetIdx - 1;
      end;

    N_GOSUB:
      begin
        if vm.callsp >= High(vm.callstack) then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Callstack Overflow');
          vm.running := 0;
          Exit;
        end;
        targetIdx := label_find(vm.labels^, n^.goto_target);
        if targetIdx < 0 then
        begin
          WriteLn(ErrOutput, 'Runtime Error: Ligne cible GOSUB ', n^.goto_target, ' introuvable');
          vm.running := 0;
        end
        else
        begin
          vm.callstack[vm.callsp] := vm.pc + 1;
          Inc(vm.callsp);
          vm.pc := targetIdx - 1;
        end;
      end;

    N_RETURN:
      begin
        if vm.callsp <= 0 then
        begin
          WriteLn(ErrOutput, 'Runtime Error: RETURN sans GOSUB');
          vm.running := 0;
          Exit;
        end;
        Dec(vm.callsp);
        retPc := vm.callstack[vm.callsp];
        vm.pc := retPc - 1;
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
        fr^.return_stmt_idx := vm.pc + 1;
        fr^.to_val := eval_node(vm, n^.for_to);
        fr^.step_val := eval_node(vm, n^.for_step);
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
          WriteLn(ErrOutput, 'Runtime Error: Variable de boucle FOR introuvable');
          vm.running := 0;
          Exit;
        end;

        if (p^.t = T_INT) and (fr^.step_val.t = T_INT) and (fr^.to_val.t = T_INT) then
        begin
          p^.i := p^.i + fr^.step_val.i;
          if fr^.step_val.i >= 0 then
            done := (p^.i > fr^.to_val.i)
          else
            done := (p^.i < fr^.to_val.i);
        end
        else
        begin
          p^ := MakeNum(to_num(p^) + to_num(fr^.step_val));
          if to_num(fr^.step_val) >= 0.0 then
            done := (p^.n > to_num(fr^.to_val))
          else
            done := (p^.n < to_num(fr^.to_val));
        end;

        if not done then
          vm.pc := fr^.return_stmt_idx - 1
        else
          Dec(vm.forsp);
      end;

    N_INPUT:
      begin
        if n^.input_prompt <> nil then
          Write(n^.input_prompt)
        else
          Write('? ');

        ReadLn(bufStr);
        Val(bufStr, inputInt, code);
        if code = 0 then
          sym_set(vm.sym^, n^.input_name, MakeInt(inputInt))
        else
        begin
          Val(bufStr, inputNum, code);
          if code = 0 then
            sym_set(vm.sym^, n^.input_name, MakeNum(inputNum))
          else
            sym_set(vm.sym^, n^.input_name, MakeStr(arena_strdup(vm.sym^.a, PChar(bufStr))));
        end;
      end;

    N_END:
      vm.running := 0;

    else
      // N_REM ou no-op
  end;
end;

function vm_run(var vm: TVM): Integer;
begin
  while (vm.pc >= 0) and (vm.pc < Length(vm.stmts)) and (vm.running <> 0) do
  begin
    exec_node(vm, vm.stmts[vm.pc]);
    Inc(vm.pc);
  end;
  Result := 0;
end;

end.