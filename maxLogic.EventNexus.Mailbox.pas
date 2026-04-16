unit maxLogic.EventNexus.Mailbox;

interface

uses
  Classes, SysUtils,
  System.Diagnostics, System.Generics.Collections, System.Generics.Defaults,
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

  TmaxMailboxQueueEntry = class
  private
    fCoalesceIdentity: string;
    fWorkItem: ImaxMailboxWorkItem;
  public
    constructor Create(const aWorkItem: ImaxMailboxWorkItem; const aCoalesceIdentity: string);
    function HasCoalesceIdentity: Boolean;
    function Invoke: Boolean;
    function ShouldPurge(const aOwner: TObject; aGeneration: Int64): Boolean;
    property CoalesceIdentity: string read fCoalesceIdentity;
    property WorkItem: ImaxMailboxWorkItem read fWorkItem write fWorkItem;
  end;
  ImaxBusMailbox = interface
    ['{4A7C7E41-86A3-4B4D-91F1-BA6B7E19C451}']
    function GetObject: TObject;
    function TryPostItem(const aItem: ImaxMailboxWorkItem): Boolean;
    function TryPostCoalescedItem(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
    procedure PurgeOwner(const aOwner: TObject; aGeneration: Int64);
  end;
  TmaxMailbox = class(TInterfacedObject, ImaxMailbox, ImaxBusMailbox)
  private
    fClosed: Boolean;
    fCoalesceIndex: TDictionary<string, TmaxMailboxQueueEntry>;
    fLock: TObject;
    fOwnerThreadId: TThreadID;
    fQueue: TQueue<TmaxMailboxQueueEntry>;
    procedure ClearPendingEntries;
    procedure EnsureCurrentThread;
    procedure RemoveCoalesceIdentityForEntry(const aEntry: TmaxMailboxQueueEntry);
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
    function TryPostCoalescedItem(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
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

constructor TmaxMailboxQueueEntry.Create(const aWorkItem: ImaxMailboxWorkItem; const aCoalesceIdentity: string);
begin
  inherited Create;
  fCoalesceIdentity := aCoalesceIdentity;
  fWorkItem := aWorkItem;
end;

function TmaxMailboxQueueEntry.HasCoalesceIdentity: Boolean;
begin
  Result := fCoalesceIdentity <> '';
end;

function TmaxMailboxQueueEntry.Invoke: Boolean;
begin
  Result := (fWorkItem <> nil) and fWorkItem.Invoke;
end;

function TmaxMailboxQueueEntry.ShouldPurge(const aOwner: TObject; aGeneration: Int64): Boolean;
begin
  Result := (fWorkItem = nil) or fWorkItem.ShouldPurge(aOwner, aGeneration);
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
  fCoalesceIndex := TDictionary<string, TmaxMailboxQueueEntry>.Create(TStringComparer.Ordinal);
  fLock := TObject.Create;
  fOwnerThreadId := TThread.CurrentThread.ThreadID;
  fQueue := TQueue<TmaxMailboxQueueEntry>.Create;
end;

destructor TmaxMailbox.Destroy;
begin
  ClearPendingEntries;
  fQueue.Free;
  fCoalesceIndex.Free;
  fLock.Free;
  inherited Destroy;
end;

procedure TmaxMailbox.Close(aDiscardPending: Boolean = True);
begin
  TMonitor.Enter(fLock);
  try
    fClosed := True;
    if aDiscardPending then
      ClearPendingEntries;
    TMonitor.PulseAll(fLock);
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxMailbox.ClearPendingEntries;
var
  lEntry: TmaxMailboxQueueEntry;
begin
  while fQueue.Count > 0 do
  begin
    lEntry := fQueue.Dequeue;
    lEntry.Free;
  end;
  fCoalesceIndex.Clear;
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
  lEntry: TmaxMailboxQueueEntry;
begin
  Result := 0;
  EnsureCurrentThread;
  if aMaxItems <= 0 then
    Exit;

  while Result < aMaxItems do
  begin
    TMonitor.Enter(fLock);
    try
      if fQueue.Count = 0 then
        Exit;
      lEntry := fQueue.Dequeue;
      RemoveCoalesceIdentityForEntry(lEntry);
    finally
      TMonitor.Exit(fLock);
    end;
    try
      if (lEntry <> nil) and lEntry.Invoke then
        Inc(Result);
    finally
      lEntry.Free;
    end;
  end;
end;

function TmaxMailbox.PumpOne(aTimeoutMs: Cardinal): Boolean;
var
  lEntry: TmaxMailboxQueueEntry;
  lRemainingMs: Int64;
  lStarted: TStopwatch;
begin
  EnsureCurrentThread;
  lStarted := TStopwatch.StartNew;

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

    lEntry := fQueue.Dequeue;
    RemoveCoalesceIdentityForEntry(lEntry);
  finally
    TMonitor.Exit(fLock);
  end;

  Result := False;
  try
    if lEntry <> nil then
      Result := lEntry.Invoke;
  finally
    lEntry.Free;
  end;
end;

procedure TmaxMailbox.PurgeOwner(const aOwner: TObject; aGeneration: Int64);
var
  lEntry: TmaxMailboxQueueEntry;
  lRetained: TQueue<TmaxMailboxQueueEntry>;
  lRetainedIndex: TDictionary<string, TmaxMailboxQueueEntry>;
begin
  TMonitor.Enter(fLock);
  try
    if fQueue.Count = 0 then
      Exit;

    lRetained := TQueue<TmaxMailboxQueueEntry>.Create;
    lRetainedIndex := TDictionary<string, TmaxMailboxQueueEntry>.Create(TStringComparer.Ordinal);
    try
      while fQueue.Count > 0 do
      begin
        lEntry := fQueue.Dequeue;
        if (lEntry = nil) or lEntry.ShouldPurge(aOwner, aGeneration) then
        begin
          lEntry.Free;
          Continue;
        end;
        lRetained.Enqueue(lEntry);
        if lEntry.HasCoalesceIdentity then
          lRetainedIndex.AddOrSetValue(lEntry.CoalesceIdentity, lEntry);
      end;

      FreeAndNil(fQueue);
      FreeAndNil(fCoalesceIndex);
      fQueue := lRetained;
      fCoalesceIndex := lRetainedIndex;
      lRetained := nil;
      lRetainedIndex := nil;
      TMonitor.PulseAll(fLock);
    finally
      lRetained.Free;
      lRetainedIndex.Free;
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
  Result := TryPostCoalescedItem('', aItem);
end;

function TmaxMailbox.TryPostCoalescedItem(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
var
  lEntry: TmaxMailboxQueueEntry;
begin
  Result := False;
  if aItem = nil then
    Exit;

  TMonitor.Enter(fLock);
  try
    if fClosed then
      Exit(False);
    if (aCoalesceIdentity <> '') and fCoalesceIndex.TryGetValue(aCoalesceIdentity, lEntry) then
    begin
      lEntry.WorkItem := aItem;
      Exit(True);
    end;

    lEntry := TmaxMailboxQueueEntry.Create(aItem, aCoalesceIdentity);
    fQueue.Enqueue(lEntry);
    if aCoalesceIdentity <> '' then
      fCoalesceIndex.AddOrSetValue(aCoalesceIdentity, lEntry);
    TMonitor.Pulse(fLock);
    Result := True;
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxMailbox.RemoveCoalesceIdentityForEntry(const aEntry: TmaxMailboxQueueEntry);
var
  lMappedEntry: TmaxMailboxQueueEntry;
begin
  if (aEntry = nil) or not aEntry.HasCoalesceIdentity then
    Exit;

  if fCoalesceIndex.TryGetValue(aEntry.CoalesceIdentity, lMappedEntry) and (lMappedEntry = aEntry) then
    fCoalesceIndex.Remove(aEntry.CoalesceIdentity);
end;

end.
