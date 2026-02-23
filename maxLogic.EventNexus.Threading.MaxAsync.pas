unit maxLogic.EventNexus.Threading.MaxAsync;

interface

uses
  Classes, SysUtils,
  maxAsync,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxAsyncScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    procedure ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function CreateMaxAsyncScheduler: IEventNexusScheduler;

implementation

procedure TmaxAsyncScheduler.ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelayMs: Integer;
  lHandle: iAsync;
  lProc: TmaxProc;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lProc := aProc;
  if aDelayUs > 0 then
    lDelayMs := aDelayUs div 1000
  else
    lDelayMs := 0;
  try
    lHandle := SimpleAsyncCall(
      procedure
      begin
        if lDelayMs > 0 then
          TThread.Sleep(lDelayMs);
        lProc();
      end,
      '',
      procedure
      begin
        lHandle := nil;
      end);
  except
    // If async backend submission fails, degrade to inline execution so callers keep progressing.
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
    lProc();
  end;
end;

procedure TmaxAsyncScheduler.RunAsync(const aProc: TmaxProc);
begin
  ScheduleAsync(aProc, 0);
end;

procedure TmaxAsyncScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  ScheduleAsync(aProc, aDelayUs);
end;

procedure TmaxAsyncScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if not ProcAssigned(aProc) then
    Exit;
  if IsMainThread() then
    aProc()
  else
    TThread.Queue(nil,
      procedure
      begin
        aProc();
      end);
end;

function TmaxAsyncScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

function CreateMaxAsyncScheduler: IEventNexusScheduler;
begin
  Result := TmaxAsyncScheduler.Create;
end;

end.
