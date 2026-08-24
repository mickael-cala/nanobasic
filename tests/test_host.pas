program TestHost;

{$mode objfpc}{$H+}

uses
  SysUtils, NanoTypes, NanoLexer, NanoParser, NanoVM;

// 1. Notre fonction personnalisée pour l'IDE qui intercepte PRINT
procedure MonIdePrint(const s: string; newline: Boolean);
begin
  if newline then
    WriteLn('[IDE-CONSOLE] ', s)
  else
    Write('[IDE-CONSOLE] ', s);
end;

// 2. Notre fonction personnalisée pour intercepter INPUT
procedure MonIdeInput(const prompt: string; out resultStr: string);
begin
  Write('[IDE-POPUP] ', prompt);
  // Ici dans un vrai IDE, on ouvrirait une boîte de dialogue InputBox()
  ReadLn(resultStr);
end;

var
  arena: TArena;
  symTab: TSymTab;
  P: TParserr;
  vm: TVM;
  code_basic: string;
begin
  // Script Basic ecrit par l'utilisateur
  code_basic := 'PRINT "Demarrage du traitement..."' + #10 +
                'PRINT "Temperature actuelle = "; SENSOR_TEMP' + #10 +
                'IF SENSOR_TEMP > 30 THEN' + #10 +
                '  PRINT "Alerte Surchauffe declenchee !"' + #10 +
                '  ALARM_STATE$ = "ACTIVE"' + #10 +
                'ELSE' + #10 +
                '  ALARM_STATE$ = "NORMALE"' + #10 +
                'END IF' + #10 +
                'INPUT "Saisissez un rapport d''intervention : ", RAPPORT$';

  WriteLn('--- PREPARATION DE LA VM NANOBASIC ---');
  FillChar(arena, sizeof(arena), 0);
  FillChar(symTab, sizeof(symTab), 0);
  symTab.a := @arena;

  parser_init(P, @arena, PChar(code_basic));
  parse_program(@P);

  if P.error = 0 then
  begin
    vm_init(vm, @symTab, P.stmts, @P.labels);

    // --- MAGIE DE L'ETAPE 10 ---
    // A. Branchement des Callbacks
    vm.on_print := @MonIdePrint;
    vm.on_input := @MonIdeInput;

    // B. Injection de variables DEPUIS le programme Pascal (Capteur matériel)
    vm_set_num(vm, 'SENSOR_TEMP', 35.5);

    WriteLn('--- LANCEMENT DU SCRIPT ---');
    vm_run(vm);
    WriteLn('--- SCRIPT TERMINE ---');

    // C. Lecture des variables de la VM DEPUIS le programme Pascal
    WriteLn;
    WriteLn('--- RESULTATS RECUPERES PAR LE PASCAL ---');
    WriteLn('Etat de l''alarme : ', vm_get_str(vm, 'ALARM_STATE$'));
    WriteLn('Rapport de l''op : ', vm_get_str(vm, 'RAPPORT$'));
  end
  else
    format_error_context(@P);

  arena_free_all(@arena);
end.