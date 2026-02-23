unit maxLogic.EventNexus.Threading.Adapter;

interface

uses
  SysUtils;

type
  TmaxProc = reference to procedure;
  TmaxProcOf<T> = reference to procedure(const aValue: T);

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
begin
  Result := Assigned(aProc);
end;

end.
