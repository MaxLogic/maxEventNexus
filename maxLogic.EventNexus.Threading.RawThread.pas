unit maxLogic.EventNexus.Threading.RawThread;

interface

uses
  Classes, SysUtils, System.Threading,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxRawThreadScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

implementation

type
  TmaxProcThread = class(TThread)
  private
    fProc: TmaxProc;
    fDelayUs: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const aProc: TmaxProc; aDelayUs: Integer);
    class procedure Start(const aProc: TmaxProc; aDelayUs: Integer = 0); static;
  end;

{ TmaxProcThread }

constructor TmaxProcThread.Create(const aProc: TmaxProc; aDelayUs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  fProc := aProc;
  if aDelayUs > 0 then
    fDelayUs := aDelayUs
  else
    fDelayUs := 0;
end;

procedure TmaxProcThread.Execute;
var
  lProc: TmaxProc;
  lDelayMs: Integer;
begin
  lProc := fProc;
  fProc := nil;
  if fDelayUs > 0 then
  begin
    lDelayMs := fDelayUs div 1000;
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
  end;
  if ProcAssigned(lProc) then
    lProc();
end;

class procedure TmaxProcThread.Start(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelayMs: Integer;
begin
  if not ProcAssigned(aProc) then
    Exit;
  if aDelayUs > 0 then
    lDelayMs := (aDelayUs + 999) div 1000
  else
    lDelayMs := 0;
  TTask.Run(
    procedure
    begin
      if lDelayMs > 0 then
        TThread.Sleep(lDelayMs);
      aProc();
    end);
end;

{ TmaxRawThreadScheduler }

procedure TmaxRawThreadScheduler.RunAsync(const aProc: TmaxProc);
begin
  TmaxProcThread.Start(aProc);
end;

procedure TmaxRawThreadScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if not ProcAssigned(aProc) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      aProc();
    end);
end;

procedure TmaxRawThreadScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelay: Integer;
begin
  if aDelayUs < 0 then
    lDelay := 0
  else
    lDelay := aDelayUs;
  TmaxProcThread.Start(aProc, lDelay);
end;

function TmaxRawThreadScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

end.
