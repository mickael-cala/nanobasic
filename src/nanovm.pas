unit NanoVM;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, NanoTypes;

type
  TForFrame = record
    var_name: PChar;
    return_stmt_idx: Integer;
    to_val, step_val: Double;
  end;

  TVM = record
    sym: PSymTab;
    stmts: array of PNode;
    labels: PLabelMap;
    pc: Integer;
    running: Integer;
    forstk: array[0..63] of TForFrame;
    forsp: Integer;
    callstack: array[0..255] of Integer; // Pile d'appels GOSUB / RETURN
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
  targetIdx, retPc: Integer;
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
          WriteLn(ErrOutput, 'Runtime Error: Debordement de la pile d''appels (Callstack Overflow)');
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
          vm.callstack[vm.callsp] := vm.pc + 1; // Adresse de retour après l'appel
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
          WriteLn(ErrOutput, 'Runtime Error: Variable de boucle FOR introuvable');
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
          vm.pc := fr^.return_stmt_idx - 1;
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