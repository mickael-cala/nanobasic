program TestFFI;

{$mode objfpc}{$H+}

uses
  SysUtils, NanoTypes, NanoLexer, NanoParser, NanoVM;

// --- 1. La fonction externe ecrite en Pascal (Pilote materiel) ---
function HardwareRelayControl(vm: PVM; const args: array of Value): Value;
var
  relayId: Integer;
  state: Boolean;
begin
  if Length(args) >= 2 then
  begin
    relayId := to_int(args[0]);
    state := to_bool(args[1]);
    
    if state then
      WriteLn('[PASCAL] > CLAC! Relais ', relayId, ' FERME')
    else
      WriteLn('[PASCAL] > CLIC! Relais ', relayId, ' OUVERT');
  end;
  Result := MakeInt(1); // Retourne un statut de succes
end;

var
  arena: TArena;
  symTab: TSymTab;
  P: TParserr;
  vm: TVM;
  code_basic: string;
begin
  // --- 2. Le script d'automate (Clignotant) ---
  code_basic := 
    'PRINT "=== Demarrage cycle de test ==="' + #10 +
    'LET DEBUT = TIMER()' + #10 +
    'FOR I = 1 TO 3' + #10 +
    '  PRINT "Cycle "; I' + #10 +
    '  CALL SET_RELAY(1, TRUE)' + #10 +
    '  SLEEP 500' + #10 +
    '  CALL SET_RELAY(1, FALSE)' + #10 +
    '  SLEEP 500' + #10 +
    'NEXT' + #10 +
    'LET FIN = TIMER()' + #10 +
    'PRINT "Temps ecoule (ms) : "; FIN - DEBUT' + #10 +
    'PRINT "=== Cycle termine ==="';

  WriteLn('Compilateur NanoBasic : Analyse AST...');
  FillChar(arena, sizeof(arena), 0);
  FillChar(symTab, sizeof(symTab), 0);
  symTab.a := @arena;

  parser_init(P, @arena, PChar(code_basic));
  parse_program(@P);

  if P.error = 0 then
  begin
    vm_init(vm, @symTab, P.stmts, @P.labels);

    // --- 3. Enregistrement Magique de la FFI ---
    vm_register_ffi(vm, 'SET_RELAY', @HardwareRelayControl);

    WriteLn('Execution...');
    vm_run(vm);
  end
  else
    format_error_context(@P);

  arena_free_all(@arena);
end.