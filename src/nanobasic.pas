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

program nanobasic;

{$mode objfpc}{$H+}

uses
  SysUtils, NanoTypes, NanoLexer, NanoParser, NanoVM;

const
  NANOBASIC_VERSION = '1.0.0-beta2';

type
  TReplBuffer = record
    lines: array of string;
    linenos: array of Integer;
    count: Integer;
    current_filename: string;
  end;

var
  G_Repl: TReplBuffer;

procedure repl_init;
begin
  G_Repl.count := 0;
  SetLength(G_Repl.lines, 0);
  SetLength(G_Repl.linenos, 0);
  G_Repl.current_filename := '';
end;

procedure repl_clear_program;
begin
  G_Repl.count := 0;
  SetLength(G_Repl.lines, 0);
  SetLength(G_Repl.linenos, 0);
end;

procedure repl_insert_line(lineno: Integer; const code: string);
var i, idx: Integer;
begin
  idx := -1;
  for i := 0 to G_Repl.count - 1 do
  begin
    if G_Repl.linenos[i] = lineno then begin idx := i; Break; end
    else if G_Repl.linenos[i] > lineno then begin idx := i; Break; end;
  end;

  if (idx >= 0) and (G_Repl.linenos[idx] = lineno) then
  begin
    if Trim(code) = '' then
    begin
      for i := idx to G_Repl.count - 2 do
      begin
        G_Repl.linenos[i] := G_Repl.linenos[i + 1];
        G_Repl.lines[i] := G_Repl.lines[i + 1];
      end;
      Dec(G_Repl.count);
      SetLength(G_Repl.linenos, G_Repl.count);
      SetLength(G_Repl.lines, G_Repl.count);
    end
    else
      G_Repl.lines[idx] := code;
  end
  else
  begin
    if Trim(code) = '' then Exit;
    Inc(G_Repl.count);
    SetLength(G_Repl.linenos, G_Repl.count);
    SetLength(G_Repl.lines, G_Repl.count);
    if idx = -1 then idx := G_Repl.count - 1
    else
    begin
      for i := G_Repl.count - 1 downto idx + 1 do
      begin
        G_Repl.linenos[i] := G_Repl.linenos[i - 1];
        G_Repl.lines[i] := G_Repl.lines[i - 1];
      end;
    end;
    G_Repl.linenos[idx] := lineno;
    G_Repl.lines[idx] := code;
  end;
end;

function repl_get_full_source: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to G_Repl.count - 1 do
  begin
    if G_Repl.linenos[i] > 0 then
      Result := Result + IntToStr(G_Repl.linenos[i]) + ' ' + G_Repl.lines[i] + #10
    else
      Result := Result + G_Repl.lines[i] + #10;
  end;
end;

procedure repl_list;
var i: Integer;
begin
  if G_Repl.count = 0 then begin WriteLn('Buffer vide.'); Exit; end;
  for i := 0 to G_Repl.count - 1 do
  begin
    if G_Repl.linenos[i] > 0 then
      WriteLn(Format('%5d %s', [G_Repl.linenos[i], G_Repl.lines[i]]))
    else
      WriteLn(G_Repl.lines[i]);
  end;
end;

// ============================================================================
// EXECUTION CENTRALE (Le pont entre le CLI et la VM)
// ============================================================================
function run_source(const src: string; checkOnly: Boolean; out numStmts: Integer): Integer;
var
  arena: TArena;
  symTab: TSymTab;
  P: TParserr;
  vm: TVM;
  srcP: PChar;
begin
  numStmts := 0;
  FillChar(arena, sizeof(arena), 0);
  FillChar(symTab, sizeof(symTab), 0);
  symTab.a := @arena;

  srcP := PChar(src);
  parser_init(P, @arena, srcP);
  parse_program(@P);

  if P.error <> 0 then
  begin
    format_error_context(@P);
    arena_free_all(@arena);
    Exit(1);
  end;

  numStmts := Length(P.stmts);
  if not checkOnly then
  begin
    vm_init(vm, @symTab, P.stmts, @P.labels);
    
    // --- AUTORISATION VFS STANDARD ---
    // Cette ligne autorise l'interpreteur CLI a toucher aux vrais fichiers Windows/Linux
    vm_enable_standard_vfs(vm);
    
    vm_run(vm);
  end;

  arena_free_all(@arena);
  Result := 0;
end;

function run_file(const filename: string; checkOnly: Boolean): Integer;
var
  f: TextFile;
  lineStr, fullSrc: string;
  count: Integer;
begin
  if not FileExists(filename) then
  begin
    WriteLn(ErrOutput, 'Erreur : Fichier introuvable : ', filename);
    Exit(1);
  end;

  AssignFile(f, filename);
  Reset(f);
  fullSrc := '';
  while not EOF(f) do
  begin
    ReadLn(f, lineStr);
    fullSrc := fullSrc + lineStr + #10;
  end;
  CloseFile(f);

  Result := run_source(fullSrc, checkOnly, count);
  if (Result = 0) and checkOnly then
    WriteLn('Syntaxe valide (', count, ' instructions statiques).');
end;

procedure repl_cmd_dir;
var
  info: TSearchRec;
  found: Boolean;
begin
  WriteLn('Fichiers .bas dans le repertoire courant :');
  found := (FindFirst('*.bas', faAnyFile, info) = 0);
  if not found then WriteLn('  (Aucun fichier .bas trouve)');
  while found do
  begin
    WriteLn('  ', info.Name, ' (', info.Size, ' octets)');
    found := (FindNext(info) = 0);
  end;
  FindClose(info);
end;

procedure repl_cmd_load(const param: string);
var
  f: TextFile;
  fn, lineStr, codePart: string;
  code, num, p: Integer;
begin
  fn := Trim(param);
  if fn = '' then begin WriteLn('Usage : LOAD <fichier.bas>'); Exit; end;
  if not FileExists(fn) then begin WriteLn('Erreur : Fichier introuvable : ', fn); Exit; end;

  repl_clear_program;
  G_Repl.current_filename := fn;

  AssignFile(f, fn);
  Reset(f);
  while not EOF(f) do
  begin
    ReadLn(f, lineStr);
    p := 1;
    while (p <= Length(lineStr)) and (lineStr[p] in ['0'..'9']) do Inc(p);
    if p > 1 then
    begin
      Val(Copy(lineStr, 1, p - 1), num, code);
      codePart := Trim(Copy(lineStr, p, Length(lineStr)));
      repl_insert_line(num, codePart);
    end
    else
      repl_insert_line(-1, lineStr);
  end;
  CloseFile(f);
  WriteLn('Charge : ', fn, ' (', G_Repl.count, ' lignes)');
end;

procedure repl_cmd_save(const param: string);
var
  f: TextFile;
  fn: string;
  i: Integer;
begin
  fn := Trim(param);
  if fn = '' then fn := G_Repl.current_filename;
  if fn = '' then begin WriteLn('Usage : SAVE <fichier.bas>'); Exit; end;

  AssignFile(f, fn);
  Rewrite(f);
  for i := 0 to G_Repl.count - 1 do
  begin
    if G_Repl.linenos[i] > 0 then
      WriteLn(f, G_Repl.linenos[i], ' ', G_Repl.lines[i])
    else
      WriteLn(f, G_Repl.lines[i]);
  end;
  CloseFile(f);
  G_Repl.current_filename := fn;
  WriteLn('Sauvegarde dans : ', fn);
end;

procedure repl_print_help;
begin
  WriteLn('=== NanoBasic v', NANOBASIC_VERSION, ' ===');
  WriteLn('Commandes REPL disponibles :');
  WriteLn('  DIR                : Liste les scripts .bas du dossier');
  WriteLn('  LOAD <fichier>     : Charge un script .bas en memoire');
  WriteLn('  SAVE [fichier]     : Sauvegarde le buffer');
  WriteLn('  LIST               : Affiche le code en memoire');
  WriteLn('  RUN                : Execute le programme stocke en memoire');
  WriteLn('  CHECK              : Valide la syntaxe du buffer sans execution');
  WriteLn('  NEW                : Efface le programme en memoire');
  WriteLn('  CLEAR              : Reinitialise toutes les variables');
  WriteLn('  CLS                : Efface l''ecran console');
  WriteLn('  HELP               : Affiche cette aide');
  WriteLn('  EXIT ou QUIT       : Quitte l''interpreteur');
  WriteLn('Edition directe :');
  WriteLn('  <num> <instruction>: Insere/remplace une ligne (ex: 10 PRINT "OK")');
  WriteLn('  <num>              : Supprime la ligne specifiee (ex: 10)');
  WriteLn('  <instruction>      : Execution immediate (ex: PRINT 40 + 2)');
end;

procedure repl_main_loop;
var
  inputLine, cmd, param, upperLine, codePart: string;
  p, num, code, dummy: Integer;
begin
  repl_init;
  WriteLn('NanoBasic v', NANOBASIC_VERSION, ' - Terminal Interactif');
  WriteLn('Tapez HELP pour la liste des commandes ou EXIT pour quitter.');
  WriteLn('------------------------------------------------------------');

  while True do
  begin
    Write('>>> ');
    ReadLn(inputLine);
    inputLine := Trim(inputLine);
    if inputLine = '' then Continue;

    upperLine := UpperCase(inputLine);
    if (upperLine = 'EXIT') or (upperLine = 'QUIT') then Break;

    if upperLine = 'HELP' then begin repl_print_help; Continue; end;
    if upperLine = 'CLS' then begin
      {$IFDEF WINDOWS}
      ExecuteProcess('cmd.exe', '/c cls');
      {$ELSE}
      Write(#27'[2J'#27'[H');
      {$ENDIF}
      Continue;
    end;
    if upperLine = 'DIR' then begin repl_cmd_dir; Continue; end;
    if upperLine = 'LIST' then begin repl_list; Continue; end;
    if upperLine = 'NEW' then begin repl_clear_program; WriteLn('Programme efface.'); Continue; end;
    if upperLine = 'RUN' then begin
      if G_Repl.count = 0 then WriteLn('Aucun programme en memoire.')
      else run_source(repl_get_full_source, False, dummy);
      Continue;
    end;
    if upperLine = 'CHECK' then begin
      if G_Repl.count = 0 then WriteLn('Buffer vide.')
      else run_source(repl_get_full_source, True, dummy);
      Continue;
    end;

    p := Pos(' ', inputLine);
    if p > 0 then
    begin
      cmd := UpperCase(Copy(inputLine, 1, p - 1));
      param := Trim(Copy(inputLine, p + 1, Length(inputLine)));
      if cmd = 'LOAD' then begin repl_cmd_load(param); Continue; end;
      if cmd = 'SAVE' then begin repl_cmd_save(param); Continue; end;
    end
    else
    begin
      if upperLine = 'SAVE' then begin repl_cmd_save(''); Continue; end;
    end;

    p := 1;
    while (p <= Length(inputLine)) and (inputLine[p] in ['0'..'9']) do Inc(p);
    if p > 1 then
    begin
      Val(Copy(inputLine, 1, p - 1), num, code);
      codePart := Trim(Copy(inputLine, p, Length(inputLine)));
      repl_insert_line(num, codePart);
      Continue;
    end;

    // Execution immediate
    run_source(inputLine, False, dummy);
  end;
end;

var
  i: Integer;
  filename: string;
  checkOnly: Boolean;
begin
  if ParamCount = 0 then
  begin
    repl_main_loop;
    Exit;
  end;

  checkOnly := False;
  filename := '';

  for i := 1 to ParamCount do
  begin
    if (ParamStr(i) = '--help') or (ParamStr(i) = '-h') then
    begin
      WriteLn('Usage: nanobasic [options] [fichier.bas]');
      WriteLn('Options:');
      WriteLn('  --check, -c    Verifie la syntaxe statique sans executer');
      WriteLn('  --version, -v  Affiche la version');
      WriteLn('  --help, -h     Affiche cette aide');
      Halt(0);
    end
    else if (ParamStr(i) = '--version') or (ParamStr(i) = '-v') then
    begin
      WriteLn('NanoBasic v', NANOBASIC_VERSION);
      Halt(0);
    end
    else if (ParamStr(i) = '--check') or (ParamStr(i) = '-c') then
      checkOnly := True
    else
      filename := ParamStr(i);
  end;

  if filename <> '' then
    Halt(run_file(filename, checkOnly))
  else
    repl_main_loop;
end.