unit maxLogic.EventNexus.Mailbox;

interface

uses
  Classes, SysUtils,
  System.Diagnostics, System.Generics.Collections,
  maxLogic.EventNexus.Threading.Adapter;

const
  cMaxWaitInfinite = High(Cardinal);

type
  EmaxMailboxWrongThread = class(Exception);

  ImaxMailbox = interface
    ['{07D0EC28-2E2E-486A-8C33-9DF264E4D50D}']
    function IsCurrent: Boolean;
    function Describe: string;
    function TryPost(const aProc: TmaxProc): Boolean;
    function PumpOne(aTimeoutMs: Cardinal = cMaxWaitInfinite): Boolean;
    function PumpAll(aMaxItems: Integer = MaxInt): Integer;
    function PendingCount: Integer;
    procedure Close(aDiscardPending: Boolean = True);
    function IsClosed: Boolean;
  end;

  ImaxMailboxWorkItem = interface
    ['{B5A0E61B-2218-49D9-AF8D-7D4E49A54A3A}']
    function ShouldPurge(const aOwner: TObject; aGeneration: Int64): Boolean;
    function Invoke: Boolean;
  end;

  ImaxBusMailbox = interface
    ['{4A7C7E41-86A3-4B4D-91F1-BA6B7E19C451}']
    function GetObject: TObject;
    function TryPostItem(const aItem: ImaxMailboxWorkItem): Boolean;
    procedure PurgeOwner(const aOwner: TObject; aGeneration: Int64);
  end;

  TmaxMailbox = class(TInterfacedObject, ImaxMailbox, ImaxBusMailbox)
  private
    fClosed: Boolean;
    fLock: TObject;
    fOwnerThreadId: TThreadID;
    fQueue: TQueue<ImaxMailboxWorkItem>;
    procedure EnsureCurrentThread;
  public
    constructor Create;
    destructor Destroy; override;
    function IsCurrent: Boolean;
    function Describe: string;
    function TryPost(const aProc: TmaxProc): Boolean;
    function PumpOne(aTimeoutMs: Cardinal = cMaxWaitInfinite): Boolean;
    function PumpAll(aMaxItems: Integer = MaxInt): Integer;
    function PendingCount: Integer;
    procedure Close(aDiscardPending: Boolean = True);
    function IsClosed: Boolean;

    function GetObject: TObject;
    function TryPostItem(const aItem: ImaxMailboxWorkItem): Boolean;
    procedure PurgeOwner(const aOwner: TObject; aGeneration: Int64);
  end;

implementation

type
  TmaxMailboxProcItem = class(TInterfacedObject, ImaxMailboxWorkItem)
  private
    fProc: TmaxProc;
  public
    constructor Create(const aProc: TmaxProc);
    function ShouldPurge(const aOwner: TObject; aGeneration: Int64): Boolean;
    function Invoke: Boolean;
  end;

constructor TmaxMailboxProcItem.Create(const aProc: TmaxProc);
begin
  inherited Create;
  fProc := aProc;
end;

function TmaxMailboxProcItem.ShouldPurge(const aOwner: TObject; aGeneration: Int64): Boolean;
begin
  Result := False;
end;

function TmaxMailboxProcItem.Invoke: Boolean;
begin
  Result := ProcAssigned(fProc);
  if Result then
    fProc();
end;

constructor TmaxMailbox.Create;
begin
  inherited Create;
  fClosed := False;
  fLock := TObject.Create;
  fOwnerThreadId := TThread.CurrentThread.ThreadID;
  fQueue := TQueue<ImaxMailboxWorkItem>.Create;
end;

destructor TmaxMailbox.Destroy;
begin
  fQueue.Free;
  fLock.Free;
  inherited Destroy;
end;

procedure TmaxMailbox.Close(aDiscardPending: Boolean = True);
begin
  TMonitor.Enter(fLock);
  try
    fClosed := True;
    if aDiscardPending then
      fQueue.Clear;
    TMonitor.PulseAll(fLock);
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxMailbox.Describe: string;
var
  lClosed: Boolean;
  lPending: Integer;
begin
  TMonitor.Enter(fLock);
  try
    lClosed := fClosed;
    lPending := fQueue.Count;
  finally
    TMonitor.Exit(fLock);
  end;
  Result := Format('TmaxMailbox(ownerTid=%d, pending=%d, closed=%s)',
    [fOwnerThreadId, lPending, BoolToStr(lClosed, True)]);
end;

procedure TmaxMailbox.EnsureCurrentThread;
begin
  if not IsCurrent then
    raise EmaxMailboxWrongThread.CreateFmt(
      'Mailbox owner thread mismatch (owner=%d, current=%d)',
      [fOwnerThreadId, TThread.CurrentThread.ThreadID]);
end;

function TmaxMailbox.GetObject: TObject;
begin
  Result := Self;
end;

function TmaxMailbox.IsClosed: Boolean;
begin
  TMonitor.Enter(fLock);
  try
    Result := fClosed;
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxMailbox.IsCurrent: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = fOwnerThreadId;
end;

function TmaxMailbox.PendingCount: Integer;
begin
  TMonitor.Enter(fLock);
  try
    Result := fQueue.Count;
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxMailbox.PumpAll(aMaxItems: Integer): Integer;
var
  lItem: ImaxMailboxWorkItem;
begin
  Result := 0;
  EnsureCurrentThread;
  if aMaxItems <= 0 then
    Exit;

  while Result < aMaxItems do
  begin
    lItem := nil;
    TMonitor.Enter(fLock);
    try
      if fQueue.Count = 0 then
        Exit;
      lItem := fQueue.Dequeue;
    finally
      TMonitor.Exit(fLock);
    end;
    if (lItem <> nil) and lItem.Invoke then
      Inc(Result);
  end;
end;

function TmaxMailbox.PumpOne(aTimeoutMs: Cardinal): Boolean;
var
  lItem: ImaxMailboxWorkItem;
  lRemainingMs: Int64;
  lStarted: TStopwatch;
begin
  EnsureCurrentThread;
  lStarted := TStopwatch.StartNew;
  lItem := nil;

  TMonitor.Enter(fLock);
  try
    while (fQueue.Count = 0) and (not fClosed) do
    begin
      if aTimeoutMs = cMaxWaitInfinite then
        TMonitor.Wait(fLock, cMaxWaitInfinite)
      else
      begin
        lRemainingMs := Int64(aTimeoutMs) - lStarted.ElapsedMilliseconds;
        if lRemainingMs <= 0 then
          Exit(False);
        if not TMonitor.Wait(fLock, Cardinal(lRemainingMs)) then
          Exit(False);
      end;
    end;

    if fQueue.Count = 0 then
      Exit(False);

    lItem := fQueue.Dequeue;
  finally
    TMonitor.Exit(fLock);
  end;

  Result := False;
  if lItem <> nil then
    Result := lItem.Invoke;
end;

procedure TmaxMailbox.PurgeOwner(const aOwner: TObject; aGeneration: Int64);
var
  lItem: ImaxMailboxWorkItem;
  lRetained: TQueue<ImaxMailboxWorkItem>;
begin
  TMonitor.Enter(fLock);
  try
    if fQueue.Count = 0 then
      Exit;

    lRetained := TQueue<ImaxMailboxWorkItem>.Create;
    try
      while fQueue.Count > 0 do
      begin
        lItem := fQueue.Dequeue;
        if (lItem = nil) or lItem.ShouldPurge(aOwner, aGeneration) then
          Continue;
        lRetained.Enqueue(lItem);
      end;

      FreeAndNil(fQueue);
      fQueue := lRetained;
      lRetained := nil;
      TMonitor.PulseAll(fLock);
    finally
      lRetained.Free;
    end;
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxMailbox.TryPost(const aProc: TmaxProc): Boolean;
begin
  if not ProcAssigned(aProc) then
    Exit(False);
  Result := TryPostItem(TmaxMailboxProcItem.Create(aProc));
end;

function TmaxMailbox.TryPostItem(const aItem: ImaxMailboxWorkItem): Boolean;
begin
  Result := False;
  if aItem = nil then
    Exit;

  TMonitor.Enter(fLock);
  try
    if fClosed then
      Exit(False);
    fQueue.Enqueue(aItem);
    TMonitor.Pulse(fLock);
    Result := True;
  finally
    TMonitor.Exit(fLock);
  end;
end;

end.
