unit MaxEventNexus.Coalesce.Tests;

interface

uses
  System.Classes, System.Generics.Collections, System.SyncObjs, System.SysUtils,
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
    fScheduledCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function DelayedCount: Integer;
    function DrainNextDelayed: Boolean;
    procedure DrainDelayed;
    function LastDelayUs: Integer;
    function ScheduledCount: Integer;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  TDelayedSubmitFailsScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fDelayedAttempts: Integer;
  public
    constructor Create;
    function DelayedAttempts: Integer;
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
    procedure TypedZeroWindowFallbackStaysDeferredAndKeepsLatest;
    procedure NamedZeroWindowFallbackStaysDeferredAndKeepsLatest;
    procedure GuidZeroWindowFallbackStaysDeferredAndKeepsLatest;
    procedure TypedZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
    procedure NamedZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
    procedure GuidZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
    procedure TypedZeroWindowThreePostBurstKeepsFinalValue;
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
  fScheduledCount := 0;
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

function TZeroDelayInlineScheduler.DrainNextDelayed: Boolean;
var
  lProc: TmaxProc;
begin
  Result := fDelayedQueue.Count > 0;
  if not Result then
    Exit;

  lProc := fDelayedQueue[0];
  fDelayedQueue.Delete(0);
  if ProcAssigned(lProc) then
    lProc();
end;

procedure TZeroDelayInlineScheduler.DrainDelayed;
begin
  while DrainNextDelayed do
  begin
  end;
end;

function TZeroDelayInlineScheduler.LastDelayUs: Integer;
begin
  Result := fLastDelayUs;
end;

function TZeroDelayInlineScheduler.ScheduledCount: Integer;
begin
  Result := fScheduledCount;
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
  Inc(fScheduledCount);
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

constructor TDelayedSubmitFailsScheduler.Create;
begin
  inherited Create;
  fDelayedAttempts := 0;
end;

function TDelayedSubmitFailsScheduler.DelayedAttempts: Integer;
begin
  Result := fDelayedAttempts;
end;

procedure TDelayedSubmitFailsScheduler.RunAsync(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TDelayedSubmitFailsScheduler.RunOnMain(const aProc: TmaxProc);
begin
  RunAsync(aProc);
end;

procedure TDelayedSubmitFailsScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  Inc(fDelayedAttempts);
  raise Exception.Create('run-delayed submit failed');
end;

function TDelayedSubmitFailsScheduler.IsMainThread: Boolean;
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

procedure TTestZeroWindowCoalesce.TypedZeroWindowFallbackStaysDeferredAndKeepsLatest;
var
  lBus: ImaxBus;
  lCount: Integer;
  lDone: TEvent;
  lLock: TCriticalSection;
  lValue: Integer;
  lScheduler: TDelayedSubmitFailsScheduler;
begin
  lScheduler := TDelayedSubmitFailsScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lLock := TCriticalSection.Create;
  lDone := TEvent.Create(nil, True, False, '');
  lCount := 0;
  lValue := 0;
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
        lLock.Enter;
        try
          Inc(lCount);
          lValue := aValue.Value;
          lDone.SetEvent;
        finally
          lLock.Leave;
        end;
      end);

    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 1));
    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 2));

    CheckEquals(1, lScheduler.DelayedAttempts, 'Zero-window typed fallback should not reschedule the same burst');
    CheckEquals(Integer(wrTimeout), Integer(lDone.WaitFor(0)), 'Zero-window typed fallback should not flush inline');
    CheckEquals(Integer(wrSignaled), Integer(lDone.WaitFor(2000)), 'Zero-window typed fallback did not deliver');
    lLock.Enter;
    try
      CheckEquals(1, lCount);
      CheckEquals(2, lValue);
    finally
      lLock.Leave;
    end;
  finally
    maxBusObj(lBus).EnableCoalesceOf<TCoalesceEvent>(nil);
    lBus.Clear;
    lDone.Free;
    lLock.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.NamedZeroWindowFallbackStaysDeferredAndKeepsLatest;
const
  cName = 'zero.window.named.fallback';
var
  lBus: ImaxBus;
  lCount: Integer;
  lDone: TEvent;
  lLock: TCriticalSection;
  lValue: Integer;
  lScheduler: TDelayedSubmitFailsScheduler;
begin
  lScheduler := TDelayedSubmitFailsScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lLock := TCriticalSection.Create;
  lDone := TEvent.Create(nil, True, False, '');
  lCount := 0;
  lValue := 0;
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
        lLock.Enter;
        try
          Inc(lCount);
          lValue := aValue;
          lDone.SetEvent;
        finally
          lLock.Leave;
        end;
      end);

    maxBusObj(lBus).PostNamedOf<Integer>(cName, 1);
    maxBusObj(lBus).PostNamedOf<Integer>(cName, 2);

    CheckEquals(1, lScheduler.DelayedAttempts, 'Zero-window named fallback should not reschedule the same burst');
    CheckEquals(Integer(wrTimeout), Integer(lDone.WaitFor(0)), 'Zero-window named fallback should not flush inline');
    CheckEquals(Integer(wrSignaled), Integer(lDone.WaitFor(2000)), 'Zero-window named fallback did not deliver');
    lLock.Enter;
    try
      CheckEquals(1, lCount);
      CheckEquals(2, lValue);
    finally
      lLock.Leave;
    end;
  finally
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cName, nil);
    lBus.Clear;
    lDone.Free;
    lLock.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.GuidZeroWindowFallbackStaysDeferredAndKeepsLatest;
var
  lBus: ImaxBus;
  lCount: Integer;
  lDone: TEvent;
  lLock: TCriticalSection;
  lValue: Integer;
  lScheduler: TDelayedSubmitFailsScheduler;
begin
  lScheduler := TDelayedSubmitFailsScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lLock := TCriticalSection.Create;
  lDone := TEvent.Create(nil, True, False, '');
  lCount := 0;
  lValue := 0;
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
        lLock.Enter;
        try
          Inc(lCount);
          lValue := aValue.GetValue;
          lDone.SetEvent;
        finally
          lLock.Leave;
        end;
      end);

    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(1));
    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(2));

    CheckEquals(1, lScheduler.DelayedAttempts, 'Zero-window GUID fallback should not reschedule the same burst');
    CheckEquals(Integer(wrTimeout), Integer(lDone.WaitFor(0)), 'Zero-window GUID fallback should not flush inline');
    CheckEquals(Integer(wrSignaled), Integer(lDone.WaitFor(2000)), 'Zero-window GUID fallback did not deliver');
    lLock.Enter;
    try
      CheckEquals(1, lCount);
      CheckEquals(2, lValue);
    finally
      lLock.Leave;
    end;
  finally
    maxBusObj(lBus).EnableCoalesceGuidOf<ICoalesceGuidEvent>(nil);
    lBus.Clear;
    lDone.Free;
    lLock.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.TypedZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
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

    CheckEquals(1, lScheduler.DelayedCount, 'Zero-window clear regression should start with one deferred flush');
    CheckEquals(0, lValues.Count, 'Zero-window clear regression should not flush inline');

    lBus.Clear;

    maxBusObj(lBus).Subscribe<TCoalesceEvent>(
      procedure(const aValue: TCoalesceEvent)
      begin
        lValues.Add(aValue.Value);
      end);
    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 3));
    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 4));

    CheckEquals(2, lScheduler.ScheduledCount, 'Clear should schedule a fresh zero-window flush for the new burst');
    Check(lScheduler.LastDelayUs > 0, 'Clear should preserve a positive zero-window delay request for the fresh burst');
    CheckEquals(0, lValues.Count, 'Clear should keep any stale deferred flush inert until the fresh burst is drained');

    Check(lScheduler.DrainNextDelayed, 'Expected the stale zero-window callback to remain queued in the fake scheduler');
    CheckEquals(0, lValues.Count, 'The stale zero-window callback should stay inert after Clear');
    CheckEquals(1, lScheduler.DelayedCount, 'The fresh zero-window callback should still be pending after the stale callback drains');
    Check(lScheduler.DrainNextDelayed, 'Expected the fresh zero-window callback to remain pending');

    CheckEquals(1, lValues.Count);
    CheckEquals(4, lValues[0]);
    Check(not lScheduler.DrainNextDelayed, 'No extra zero-window callbacks should remain after the fresh burst drains');
  finally
    maxBusObj(lBus).EnableCoalesceOf<TCoalesceEvent>(nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.NamedZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
const
  cName = 'zero.window.named.clear';
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

    CheckEquals(1, lScheduler.DelayedCount, 'Named zero-window clear regression should start with one deferred flush');
    CheckEquals(0, lValues.Count, 'Named zero-window clear regression should not flush inline');

    lBus.Clear;

    maxBusObj(lBus).SubscribeNamedOf<Integer>(cName,
      procedure(const aValue: Integer)
      begin
        lValues.Add(aValue);
      end);
    maxBusObj(lBus).PostNamedOf<Integer>(cName, 3);
    maxBusObj(lBus).PostNamedOf<Integer>(cName, 4);

    CheckEquals(2, lScheduler.ScheduledCount, 'Clear should schedule a fresh named zero-window flush for the new burst');
    Check(lScheduler.LastDelayUs > 0, 'Clear should preserve a positive named zero-window delay request for the fresh burst');
    CheckEquals(0, lValues.Count, 'Clear should keep any stale named deferred flush inert until the fresh burst is drained');

    Check(lScheduler.DrainNextDelayed, 'Expected the stale named zero-window callback to remain queued in the fake scheduler');
    CheckEquals(0, lValues.Count, 'The stale named zero-window callback should stay inert after Clear');
    CheckEquals(1, lScheduler.DelayedCount, 'The fresh named zero-window callback should still be pending after the stale callback drains');
    Check(lScheduler.DrainNextDelayed, 'Expected the fresh named zero-window callback to remain pending');

    CheckEquals(1, lValues.Count);
    CheckEquals(4, lValues[0]);
    Check(not lScheduler.DrainNextDelayed, 'No extra named zero-window callbacks should remain after the fresh burst drains');
  finally
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cName, nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.GuidZeroWindowClearPurgesPendingFlushAndKeepsFreshBurst;
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

    CheckEquals(1, lScheduler.DelayedCount, 'GUID zero-window clear regression should start with one deferred flush');
    CheckEquals(0, lValues.Count, 'GUID zero-window clear regression should not flush inline');

    lBus.Clear;

    maxBusObj(lBus).SubscribeGuidOf<ICoalesceGuidEvent>(
      procedure(const aValue: ICoalesceGuidEvent)
      begin
        lValues.Add(aValue.GetValue);
      end);
    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(3));
    maxBusObj(lBus).PostGuidOf<ICoalesceGuidEvent>(TCoalesceGuidEvent.Create(4));

    CheckEquals(2, lScheduler.ScheduledCount, 'Clear should schedule a fresh GUID zero-window flush for the new burst');
    Check(lScheduler.LastDelayUs > 0, 'Clear should preserve a positive GUID zero-window delay request for the fresh burst');
    CheckEquals(0, lValues.Count, 'Clear should keep any stale GUID deferred flush inert until the fresh burst is drained');

    Check(lScheduler.DrainNextDelayed, 'Expected the stale GUID zero-window callback to remain queued in the fake scheduler');
    CheckEquals(0, lValues.Count, 'The stale GUID zero-window callback should stay inert after Clear');
    CheckEquals(1, lScheduler.DelayedCount, 'The fresh GUID zero-window callback should still be pending after the stale callback drains');
    Check(lScheduler.DrainNextDelayed, 'Expected the fresh GUID zero-window callback to remain pending');

    CheckEquals(1, lValues.Count);
    CheckEquals(4, lValues[0]);
    Check(not lScheduler.DrainNextDelayed, 'No extra GUID zero-window callbacks should remain after the fresh burst drains');
  finally
    maxBusObj(lBus).EnableCoalesceGuidOf<ICoalesceGuidEvent>(nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

procedure TTestZeroWindowCoalesce.TypedZeroWindowThreePostBurstKeepsFinalValue;
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
    maxBusObj(lBus).Post<TCoalesceEvent>(MakeEvent('A', 3));

    CheckEquals(1, lScheduler.DelayedCount, 'Zero-window three-post burst should queue one deferred flush');
    Check(lScheduler.LastDelayUs > 0, 'Zero-window three-post burst should request a positive delay');
    CheckEquals(0, lValues.Count, 'Zero-window three-post burst should not flush inline');

    lScheduler.DrainDelayed;

    CheckEquals(1, lValues.Count);
    CheckEquals(3, lValues[0]);
  finally
    maxBusObj(lBus).EnableCoalesceOf<TCoalesceEvent>(nil);
    lBus.Clear;
    lValues.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZeroWindowCoalesce);

end.
