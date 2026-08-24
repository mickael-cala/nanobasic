program NanoBasic;

{$mode objfpc}{$H+}

uses
  SysUtils, NanoTypes, NanoLexer, NanoParser, NanoVM;

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

  parser_init(P, @arena, src);
  parse_program(@P);

  if P.error <> 0 then
  begin
    WriteLn(ErrOutput, P.errmsg);
    arena_free_all(@arena);
    SetLength(P.stmts, 0);
    SetLength(P.labels.entries, 0);
    Exit(1);
  end;

  vm_init(vm, @sym, P.stmts, @P.labels);
  vm_run(vm);

  arena_free_all(@arena);
  SetLength(P.stmts, 0);
  SetLength(P.labels.entries, 0);
  SetLength(vm.stmts, 0);
  Result := 0;
end;

procedure run_repl;
var
  line, fullSrc: string;
  arena: TArena;
  sym: TSymTab;
  P: TParserr;
  vm: TVM;
begin
  WriteLn('NanoBasic v1.2 (Interactive REPL & GOSUB/RETURN Engine)');
  WriteLn('Tapez "EXIT" ou "QUIT" pour quitter.');
  WriteLn('----------------------------------------------------');

  FillChar(arena, sizeof(arena), 0);
  FillChar(sym, sizeof(sym), 0);
  sym.a := @arena;

  while True do
  begin
    Write('>>> ');
    ReadLn(line);
    line := Trim(line);
    if (UpperCase(line) = 'EXIT') or (UpperCase(line) = 'QUIT') then
      Break;
    if line = '' then
      Continue;

    fullSrc := line + LineEnding;

    parser_init(P, @arena, PChar(fullSrc));
    parse_program(@P);

    if P.error <> 0 then
      WriteLn(ErrOutput, P.errmsg)
    else
    begin
      vm_init(vm, @sym, P.stmts, @P.labels);
      vm_run(vm);
    end;

    SetLength(P.stmts, 0);
    SetLength(P.labels.entries, 0);
    SetLength(vm.stmts, 0);
  end;

  arena_free_all(@arena);
end;

var
  f: TextFile;
  srcBuf, lineBuf: string;
begin
  // Sans argument : mode REPL interactif
  if ParamCount < 1 then
  begin
    run_repl;
    Halt(0);
  end;

  // Avec argument : mode script fichier
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