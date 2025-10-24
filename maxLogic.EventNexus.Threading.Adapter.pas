unit maxLogic.EventNexus.Threading.Adapter;

{$I fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  SysUtils;

type
{$IFDEF max_FPC}
  TmaxProc = TProc;
  TmaxProcOf<T> = TProc1<T>;
{$ELSE}
  TmaxProc = reference to procedure;
  TmaxProcOf<T> = reference to procedure(const aValue: T);
{$ENDIF}

  IEventNexusScheduler = interface
    ['{9FD531B7-4A0E-4E17-96F1-9134FDEBA02F}']
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function ProcAssigned(const aProc: TmaxProc): Boolean; inline;

implementation

function ProcAssigned(const aProc: TmaxProc): Boolean;
{$IFDEF max_FPC}
var
  lMethod: TMethod;
{$ENDIF}
begin
{$IFDEF max_FPC}
  lMethod := TMethod(aProc);
  Result := lMethod.Code <> nil;
{$ELSE}
  Result := Assigned(aProc);
{$ENDIF}
end;

end.
