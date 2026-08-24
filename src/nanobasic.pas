program NanoBasic;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, NanoTypes, NanoLexer, NanoParser, NanoVM;

const
  NANOBASIC_VERSION = '1.0.0-alpha';

type
  TProgramLine = record
    lineno: Integer;
    text: string;
  end;

  TProgramBuffer = record
    lines: array of TProgramLine;
    filename: string;
  end;

var
  G_Arena: TArena;
  G_Sym: TSymTab;
  G_EnvInitialized: Boolean = False;

procedure InitGlobalEnv;
begin
  if not G_EnvInitialized then
  begin
    FillChar(G_Arena, sizeof(G_Arena), 0);
    FillChar(G_Sym, sizeof(G_Sym), 0);
    G_Sym.a := @G_Arena;
    G_EnvInitialized := True;
  end;
end;

procedure ResetGlobalEnv;
begin
  if G_EnvInitialized then
  begin
    arena_free_all(@G_Arena);
    FillChar(G_Arena, sizeof(G_Arena), 0);
    FillChar(G_Sym, sizeof(G_Sym), 0);
    G_Sym.a := @G_Arena;
  end;
end;

function RunCodeBuffer(const src: PChar; keepEnv: Boolean): Integer;
var
  localArena: TArena;
  localSym: TSymTab;
  targetArena: PArena;
  targetSym: PSymTab;
  P: TParserr;
  vm: TVM;
begin
  if (src = nil) or (src^ = #0) then Exit(0);

  if keepEnv then
  begin
    InitGlobalEnv;
    targetArena := @G_Arena;
    targetSym := @G_Sym;
  end
  else
  begin
    FillChar(localArena, sizeof(localArena), 0);
    FillChar(localSym, sizeof(localSym), 0);
    localSym.a := @localArena;
    targetArena := @localArena;
    targetSym := @localSym;
  end;

  parser_init(P, targetArena, src);
  parse_program(@P);

  if P.error <> 0 then
  begin
    WriteLn(ErrOutput, P.errmsg);
    if not keepEnv then
      arena_free_all(targetArena);
    SetLength(P.stmts, 0);
    SetLength(P.labels.entries, 0);
    Exit(1);
  end;

  vm_init(vm, targetSym, P.stmts, @P.labels);
  vm_run(vm);

  if not keepEnv then
    arena_free_all(targetArena);

  SetLength(P.stmts, 0);
  SetLength(P.labels.entries, 0);
  SetLength(vm.stmts, 0);
  Result := 0;
end;

(* ============================================================
   GESTION DU BUFFER PROGRAMME EN MEMOIRE
   ============================================================ *)
procedure BufInsertOrUpdate(var buf: TProgramBuffer; lineno: Integer; const codeText: string);
var
  i, count, insertIdx: Integer;
begin
  count := Length(buf.lines);
  insertIdx := -1;

  for i := 0 to count - 1 do
  begin
    if buf.lines[i].lineno = lineno then
    begin
      if codeText = '' then
      begin
        for insertIdx := i to count - 2 do
          buf.lines[insertIdx] := buf.lines[insertIdx + 1];
        SetLength(buf.lines, count - 1);
        Exit;
      end
      else
      begin
        buf.lines[i].text := codeText;
        Exit;
      end;
    end
    else if (buf.lines[i].lineno > lineno) and (insertIdx = -1) then
      insertIdx := i;
  end;

  if codeText = '' then Exit;

  SetLength(buf.lines, count + 1);
  if insertIdx = -1 then
    insertIdx := count
  else
  begin
    for i := count downto insertIdx + 1 do
      buf.lines[i] := buf.lines[i - 1];
  end;

  buf.lines[insertIdx].lineno := lineno;
  buf.lines[insertIdx].text := codeText;
end;

procedure BufList(const buf: TProgramBuffer);
var
  i: Integer;
begin
  if Length(buf.lines) = 0 then
  begin
    WriteLn('(Aucun programme en memoire)');
    Exit;
  end;
  for i := 0 to High(buf.lines) do
    WriteLn(buf.lines[i].lineno, ' ', buf.lines[i].text);
end;

procedure BufClear(var buf: TProgramBuffer);
begin
  SetLength(buf.lines, 0);
  buf.filename := '';
end;

function BufToSource(const buf: TProgramBuffer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(buf.lines) do
    Result := Result + IntToStr(buf.lines[i].lineno) + ' ' + buf.lines[i].text + LineEnding;
end;

procedure CmdDir;
var
  info: TSearchRec;
  count: Integer;
begin
  count := 0;
  WriteLn('Fichiers .bas dans le repertoire courant :');
  if FindFirst('*.bas', faAnyFile, info) = 0 then
  begin
    repeat
      if (info.Attr and faDirectory) = 0 then
      begin
        WriteLn('  ', info.Name, ' (', info.Size, ' octets)');
        Inc(count);
      end;
    until FindNext(info) <> 0;
    FindClose(info);
  end;
  if count = 0 then
    WriteLn('  (Aucun fichier .bas trouve)');
end;

procedure CmdLoad(var buf: TProgramBuffer; const arg: string);
var
  fn, lineStr, trimLine: string;
  f: TextFile;
  spacePos, lineno, code: Integer;
begin
  fn := Trim(arg);
  if fn = '' then
  begin
    WriteLn(ErrOutput, 'Erreur: nom de fichier requis (ex: LOAD test.bas)');
    Exit;
  end;
  if ExtractFileExt(fn) = '' then fn := fn + '.bas';

  if not FileExists(fn) then
  begin
    WriteLn(ErrOutput, 'Fichier introuvable: ', fn);
    Exit;
  end;

  AssignFile(f, fn);
  {$I-}
  Reset(f);
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn(ErrOutput, 'Impossible d''ouvrir le fichier: ', fn);
    Exit;
  end;

  BufClear(buf);
  buf.filename := fn;

  while not EOF(f) do
  begin
    ReadLn(f, lineStr);
    trimLine := Trim(lineStr);
    if trimLine = '' then Continue;

    spacePos := Pos(' ', trimLine);
    if spacePos > 1 then
    begin
      Val(Copy(trimLine, 1, spacePos - 1), lineno, code);
      if code = 0 then
        BufInsertOrUpdate(buf, lineno, Trim(Copy(trimLine, spacePos + 1, Length(trimLine))))
      else
        BufInsertOrUpdate(buf, (Length(buf.lines) + 1) * 10, trimLine);
    end
    else
    begin
      Val(trimLine, lineno, code);
      if code = 0 then
        BufInsertOrUpdate(buf, lineno, '')
      else
        BufInsertOrUpdate(buf, (Length(buf.lines) + 1) * 10, trimLine);
    end;
  end;
  CloseFile(f);
  WriteLn('Charge : ', fn, ' (', Length(buf.lines), ' lignes)');
end;

procedure CmdSave(var buf: TProgramBuffer; const arg: string);
var
  fn: string;
  f: TextFile;
  i: Integer;
begin
  if Length(buf.lines) = 0 then
  begin
    WriteLn(ErrOutput, 'Erreur: rien a sauvegarder (programme vide)');
    Exit;
  end;

  fn := Trim(arg);
  if fn = '' then
  begin
    if buf.filename <> '' then fn := buf.filename
    else fn := 'untitled.bas';
  end;
  if ExtractFileExt(fn) = '' then fn := fn + '.bas';

  AssignFile(f, fn);
  {$I-}
  Rewrite(f);
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn(ErrOutput, 'Impossible d''ecrire dans le fichier: ', fn);
    Exit;
  end;

  for i := 0 to High(buf.lines) do
    WriteLn(f, buf.lines[i].lineno, ' ', buf.lines[i].text);

  CloseFile(f);
  buf.filename := fn;
  WriteLn('Sauvegarde reussie dans : ', fn);
end;

procedure CmdHelp;
begin
  WriteLn('=== NanoBasic v', NANOBASIC_VERSION, ' ===');
  WriteLn('Commandes REPL disponibles :');
  WriteLn('  DIR                : Liste les scripts .bas du dossier');
  WriteLn('  LOAD <fichier>     : Charge un script .bas en memoire');
  WriteLn('  SAVE [fichier]     : Sauvegarde le buffer (defaut: nom actuel ou untitled.bas)');
  WriteLn('  LIST               : Affiche le code en memoire');
  WriteLn('  RUN                : Execute le programme stocke en memoire');
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

procedure CmdCls;
begin
  {$IFDEF WINDOWS}
  // Code ANSI supporté par les consoles Windows modernes ou fallback
  Write(#27'[2J'#27'[H');
  {$ELSE}
  Write(#27'[2J'#27'[H');
  {$ENDIF}
end;

(* ============================================================
   BOUCLE PRINCIPALE DU REPL
   ============================================================ *)
procedure run_repl;
var
  inputLine, cmd, arg, src: string;
  progBuf: TProgramBuffer;
  spacePos, lineno, code: Integer;
begin
  BufClear(progBuf);
  InitGlobalEnv;

  WriteLn('NanoBasic v', NANOBASIC_VERSION, ' - Terminal Interactif');
  WriteLn('Tapez HELP pour la liste des commandes ou EXIT pour quitter.');
  WriteLn('------------------------------------------------------------');

  while True do
  begin
    Write('>>> ');
    ReadLn(inputLine);
    inputLine := Trim(inputLine);
    if inputLine = '' then Continue;

    spacePos := Pos(' ', inputLine);
    if spacePos > 0 then
    begin
      cmd := UpperCase(Copy(inputLine, 1, spacePos - 1));
      arg := Copy(inputLine, spacePos + 1, Length(inputLine));
    end
    else
    begin
      cmd := UpperCase(inputLine);
      arg := '';
    end;

    if (cmd = 'EXIT') or (cmd = 'QUIT') then
      Break
    else if cmd = 'HELP' then
      CmdHelp
    else if cmd = 'DIR' then
      CmdDir
    else if cmd = 'LOAD' then
      CmdLoad(progBuf, arg)
    else if cmd = 'SAVE' then
      CmdSave(progBuf, arg)
    else if cmd = 'LIST' then
      BufList(progBuf)
    else if cmd = 'NEW' then
    begin
      BufClear(progBuf);
      ResetGlobalEnv;
      WriteLn('(Memoire et variables effacees)');
    end
    else if cmd = 'CLEAR' then
    begin
      ResetGlobalEnv;
      WriteLn('(Variables reinitialisees)');
    end
    else if cmd = 'CLS' then
      CmdCls
    else if cmd = 'RUN' then
    begin
      if Length(progBuf.lines) = 0 then
        WriteLn(ErrOutput, 'Erreur: Aucun programme en memoire (utilisez LOAD ou entrez des lignes)')
      else
      begin
        src := BufToSource(progBuf);
        RunCodeBuffer(PChar(src), False);
      end;
    end
    else
    begin
      Val(cmd, lineno, code);
      if code = 0 then
        BufInsertOrUpdate(progBuf, lineno, arg)
      else
      begin
        src := inputLine + LineEnding;
        RunCodeBuffer(PChar(src), True);
      end;
    end;
  end;

  ResetGlobalEnv;
  BufClear(progBuf);
end;

var
  f: TextFile;
  srcBuf, lineBuf: string;
begin
  if ParamCount < 1 then
  begin
    run_repl;
    Halt(0);
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

  Halt(RunCodeBuffer(PChar(srcBuf), False));
end.