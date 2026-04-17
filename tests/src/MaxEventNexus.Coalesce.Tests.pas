unit MaxEventNexus.Coalesce.Tests;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils,
  DUnitX.TestFramework,
  MaxEventNexus.Testing,
  maxLogic.EventNexus.Core, maxLogic.EventNexus.Threading.Adapter;

type
  TCoalesceEvent = record
    Key: string;
    Value: Integer;
  end;

  ICoalesceGuidEvent = interface
    ['{C66EB4CD-6392-4934-B9AB-CDEDC30A2FB8}']
    function GetValue: Integer;
  end;

  TCoalesceGuidEvent = class(TInterfacedObject, ICoalesceGuidEvent)
  private
    fValue: Integer;
  public
    constructor Create(aValue: Integer);
    function GetValue: Integer;
  end;

  TZeroDelayInlineScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fDelayedQueue: TList<TmaxProc>;
    fLastDelayUs: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function DelayedCount: Integer;
    procedure DrainDelayed;
    function LastDelayUs: Integer;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  {$M+}
  [TestFixture]
  TTestZeroWindowCoalesce = class(TmaxTestCase)
  private
    class function MakeEvent(const aKey: string; aValue: Integer): TCoalesceEvent; static;
  published
    procedure TypedZeroWindowStaysDeferredAndKeepsLatest;
    procedure NamedZeroWindowStaysDeferredAndKeepsLatest;
    procedure GuidZeroWindowStaysDeferredAndKeepsLatest;
  end;
  {$M-}

implementation

constructor TCoalesceGuidEvent.Create(aValue: Integer);
begin
  inherited Create;
  fValue := aValue;
end;

function TCoalesceGuidEvent.GetValue: Integer;
begin
  Result := fValue;
end;

constructor TZeroDelayInlineScheduler.Create;
begin
  inherited Create;
  fDelayedQueue := TList<TmaxProc>.Create;
  fLastDelayUs := -1;
end;

destructor TZeroDelayInlineScheduler.Destroy;
begin
  fDelayedQueue.Free;
  inherited Destroy;
end;

function TZeroDelayInlineScheduler.DelayedCount: Integer;
begin
  Result := fDelayedQueue.Count;
end;

procedure TZeroDelayInlineScheduler.DrainDelayed;
var
  lProc: TmaxProc;
begin
  while fDelayedQueue.Count > 0 do
  begin
    lProc := fDelayedQueue[0];
    fDelayedQueue.Delete(0);
    if ProcAssigned(lProc) then
      lProc();
  end;
end;

function TZeroDelayInlineScheduler.LastDelayUs: Integer;
begin
  Result := fLastDelayUs;
end;

procedure TZeroDelayInlineScheduler.RunAsync(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TZeroDelayInlineScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TZeroDelayInlineScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  fLastDelayUs := aDelayUs;
  if not ProcAssigned(aProc) then
    Exit;
  if aDelayUs <= 0 then
  begin
    aProc();
    Exit;
  end;
  fDelayedQueue.Add(aProc);
end;

function TZeroDelayInlineScheduler.IsMainThread: Boolean;
begin
  Result := True;
end;

class function TTestZeroWindowCoalesce.MakeEvent(const aKey: string; aValue: Integer): TCoalesceEvent;
begin
  Result.Key := aKey;
  Result.Value := aValue;
end;

procedure TTestZeroWindowCoalesce.TypedZeroWindowStaysDeferredAndKeepsLatest;
var
  lBus: ImaxBus;
  lScheduler: TZeroDelayInlineScheduler;
  lValues: TList<Integer>;
begin
  lScheduler := TZeroDelayInlineScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lValues := TList<Integer>.Create;
  try
    maxBusObj(lBus).EnableCoalesceOf<TCoalesceEvent>(
      function(const aValue: TCoalesceEvent): TmaxString
      begin
        Result := aValue.Key;
      end,
      0);
    maxBusObj(lBus).Subscribe<TCoalesceEvent>(
      procedure(const aValue: TCoalesceEvent)
      begin
        lValues.Add(aValue.Value);
      end);

    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 1));
    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 2));

    CheckEquals(1, lScheduler.DelayedCount, 'Zero-window typed coalesce should stay deferred');
    Check(lScheduler.LastDelayUs > 0, 'Zero-window typed coalesce should request a positive scheduler delay');
    CheckEquals(0, lValues.Count, 'Zero-window typed coalesce should not flush inline');

    lScheduler.DrainDelayed;

    CheckEquals(1, lValues.Count);
    CheckEquals(2, lValues[0]);
  finally
    maxBusObj(lBus).EnableCoalesceOf<TCoalesceEvent>(nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.NamedZeroWindowStaysDeferredAndKeepsLatest;
const
  cName = 'zero.window.named';
var
  lBus: ImaxBus;
  lScheduler: TZeroDelayInlineScheduler;
  lValues: TList<Integer>;
begin
  lScheduler := TZeroDelayInlineScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lValues := TList<Integer>.Create;
  try
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cName,
      function(const aValue: Integer): TmaxString
      begin
        Result := 'same';
      end,
      0);
    maxBusObj(lBus).SubscribeNamedOf<Integer>(cName,
      procedure(const aValue: Integer)
      begin
        lValues.Add(aValue);
      end);

    maxBusObj(lBus).PostNamedOf<Integer>(cName, 1);
    maxBusObj(lBus).PostNamedOf<Integer>(cName, 2);

    CheckEquals(1, lScheduler.DelayedCount, 'Zero-window named coalesce should stay deferred');
    Check(lScheduler.LastDelayUs > 0, 'Zero-window named coalesce should request a positive scheduler delay');
    CheckEquals(0, lValues.Count, 'Zero-window named coalesce should not flush inline');

    lScheduler.DrainDelayed;

    CheckEquals(1, lValues.Count);
    CheckEquals(2, lValues[0]);
  finally
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cName, nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.GuidZeroWindowStaysDeferredAndKeepsLatest;
var
  lBus: ImaxBus;
  lScheduler: TZeroDelayInlineScheduler;
  lValues: TList<Integer>;
begin
  lScheduler := TZeroDelayInlineScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lValues := TList<Integer>.Create;
  try
    maxBusObj(lBus).EnableCoalesceGuidOf<ICoalesceGuidEvent>(
      function(const aValue: ICoalesceGuidEvent): TmaxString
      begin
        Result := 'same';
      end,
      0);
    maxBusObj(lBus).SubscribeGuidOf<ICoalesceGuidEvent>(
      procedure(const aValue: ICoalesceGuidEvent)
      begin
        lValues.Add(aValue.GetValue);
      end);

    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(1));
    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(2));

    CheckEquals(1, lScheduler.DelayedCount, 'Zero-window GUID coalesce should stay deferred');
    Check(lScheduler.LastDelayUs > 0, 'Zero-window GUID coalesce should request a positive scheduler delay');
    CheckEquals(0, lValues.Count, 'Zero-window GUID coalesce should not flush inline');

    lScheduler.DrainDelayed;

    CheckEquals(1, lValues.Count);
    CheckEquals(2, lValues[0]);
  finally
    maxBusObj(lBus).EnableCoalesceGuidOf<ICoalesceGuidEvent>(nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZeroWindowCoalesce);

end.
