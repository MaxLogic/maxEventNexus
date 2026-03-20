unit maxLogic.EventNexus.Threading.RawThread;

interface

uses
  Classes, SysUtils,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxRawThreadScheduler = class(TInterfacedObject, IEventNexusScheduler)
  protected
    class function DelayUsToDelayMs(aDelayUs: Integer): Integer; static;
    function ResolveDelayMs(aDelayUs: Integer): Integer; virtual;
    function CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread; virtual;
    procedure StartProcThread(const aProc: TmaxProc; aDelayUs: Integer);
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
    fDelayMs: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const aProc: TmaxProc; aDelayMs: Integer);
  end;

{ TmaxProcThread }

constructor TmaxProcThread.Create(const aProc: TmaxProc; aDelayMs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  fProc := aProc;
  if aDelayMs > 0 then
    fDelayMs := aDelayMs
  else
    fDelayMs := 0;
end;

procedure TmaxProcThread.Execute;
var
  lProc: TmaxProc;
begin
  lProc := fProc;
  fProc := nil;
  if fDelayMs > 0 then
    TThread.Sleep(fDelayMs);
  if ProcAssigned(lProc) then
    lProc();
end;

class function TmaxRawThreadScheduler.DelayUsToDelayMs(aDelayUs: Integer): Integer;
begin
  if aDelayUs <= 0 then
    Exit(0);
  Result := (aDelayUs + 999) div 1000;
end;

{ TmaxRawThreadScheduler }

function TmaxRawThreadScheduler.ResolveDelayMs(aDelayUs: Integer): Integer;
begin
  Result := DelayUsToDelayMs(aDelayUs);
end;

function TmaxRawThreadScheduler.CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread;
begin
  Result := TmaxProcThread.Create(aProc, aDelayMs);
end;

procedure TmaxRawThreadScheduler.StartProcThread(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelayMs: Integer;
  lThread: TThread;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lDelayMs := ResolveDelayMs(aDelayUs);
  lThread := CreateProcThread(aProc, lDelayMs);
  if lThread = nil then
    Exit;
  lThread.Start;
end;

procedure TmaxRawThreadScheduler.RunAsync(const aProc: TmaxProc);
begin
  StartProcThread(aProc, 0);
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
begin
  StartProcThread(aProc, aDelayUs);
end;

function TmaxRawThreadScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

end.
