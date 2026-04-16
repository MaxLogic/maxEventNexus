unit maxLogic.EventNexus.Mailbox;

interface

uses
  Classes, SysUtils, TypInfo,
  System.Diagnostics, System.Generics.Collections, System.Generics.Defaults,
  maxLogic.EventNexus.Threading.Adapter;

const
  cMaxWaitInfinite = High(Cardinal);

type
  EmaxMailboxWrongThread = class(Exception);

  TmaxMailboxOverflow = (MailboxDropNewest, MailboxDropOldest, MailboxBlock, MailboxDeadline);

  TmaxMailboxPolicy = record
    MaxDepth: Integer;
    Overflow: TmaxMailboxOverflow;
    DeadlineUs: Int64;
  end;

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
    fHasCoalesceIdentity: Boolean;
    fWorkItem: ImaxMailboxWorkItem;
  public
    constructor Create(const aWorkItem: ImaxMailboxWorkItem; const aCoalesceIdentity: string;
      aHasCoalesceIdentity: Boolean);
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
    fPolicy: TmaxMailboxPolicy;
    fQueue: TQueue<TmaxMailboxQueueEntry>;
    procedure ClearPendingEntries;
    class function DeadlineMsFromPolicy(const aPolicy: TmaxMailboxPolicy): Cardinal; static;
    procedure DropOldestLocked;
    procedure EnsureCurrentThread;
    procedure EnqueueLocked(const aEntry: TmaxMailboxQueueEntry);
    function HasPendingCapacityLocked: Boolean;
    class function NormalizePolicy(const aPolicy: TmaxMailboxPolicy): TmaxMailboxPolicy; static;
    procedure RemoveCoalesceIdentityForEntry(const aEntry: TmaxMailboxQueueEntry);
    function TryReplacePendingLocked(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
    function TryPostWorkItem(const aItem: ImaxMailboxWorkItem; aHasCoalesceIdentity: Boolean;
      const aCoalesceIdentity: string): Boolean;
    function TryWaitForCapacityLocked(const aStarted: TStopwatch; aDeadlineMs: Cardinal): Boolean;
  public
    constructor Create; overload;
    constructor Create(const aPolicy: TmaxMailboxPolicy); overload;
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

constructor TmaxMailboxQueueEntry.Create(const aWorkItem: ImaxMailboxWorkItem; const aCoalesceIdentity: string;
  aHasCoalesceIdentity: Boolean);
begin
  inherited Create;
  fCoalesceIdentity := aCoalesceIdentity;
  fHasCoalesceIdentity := aHasCoalesceIdentity;
  fWorkItem := aWorkItem;
end;

function TmaxMailboxQueueEntry.HasCoalesceIdentity: Boolean;
begin
  Result := fHasCoalesceIdentity;
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
  fPolicy := NormalizePolicy(Default(TmaxMailboxPolicy));
  fQueue := TQueue<TmaxMailboxQueueEntry>.Create;
end;

constructor TmaxMailbox.Create(const aPolicy: TmaxMailboxPolicy);
begin
  inherited Create;
  fClosed := False;
  fCoalesceIndex := TDictionary<string, TmaxMailboxQueueEntry>.Create(TStringComparer.Ordinal);
  fLock := TObject.Create;
  fOwnerThreadId := TThread.CurrentThread.ThreadID;
  fPolicy := NormalizePolicy(aPolicy);
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

class function TmaxMailbox.DeadlineMsFromPolicy(const aPolicy: TmaxMailboxPolicy): Cardinal;
begin
  Result := 0;
  if aPolicy.DeadlineUs > 0 then
  begin
    Result := Cardinal((aPolicy.DeadlineUs + 999) div 1000);
    if Result = 0 then
      Result := 1;
  end;
end;

procedure TmaxMailbox.DropOldestLocked;
var
  lOldest: TmaxMailboxQueueEntry;
begin
  lOldest := fQueue.Dequeue;
  RemoveCoalesceIdentityForEntry(lOldest);
  lOldest.Free;
end;

procedure TmaxMailbox.EnqueueLocked(const aEntry: TmaxMailboxQueueEntry);
begin
  fQueue.Enqueue(aEntry);
  if aEntry.HasCoalesceIdentity then
    fCoalesceIndex.AddOrSetValue(aEntry.CoalesceIdentity, aEntry);
  TMonitor.PulseAll(fLock);
end;

function TmaxMailbox.HasPendingCapacityLocked: Boolean;
begin
  Result := (fPolicy.MaxDepth <= 0) or (fQueue.Count < fPolicy.MaxDepth);
end;

function TmaxMailbox.Describe: string;
var
  lClosed: Boolean;
  lMaxDepth: Integer;
  lOverflow: string;
  lPending: Integer;
begin
  TMonitor.Enter(fLock);
  try
    lClosed := fClosed;
    lMaxDepth := fPolicy.MaxDepth;
    lOverflow := GetEnumName(TypeInfo(TmaxMailboxOverflow), Ord(fPolicy.Overflow));
    lPending := fQueue.Count;
  finally
    TMonitor.Exit(fLock);
  end;
  Result := Format('TmaxMailbox(ownerTid=%d, pending=%d, maxDepth=%d, overflow=%s, closed=%s)',
    [fOwnerThreadId, lPending, lMaxDepth, lOverflow, BoolToStr(lClosed, True)]);
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
      TMonitor.PulseAll(fLock);
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
    TMonitor.PulseAll(fLock);
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
  Result := TryPostWorkItem(aItem, False, '');
end;

function TmaxMailbox.TryPostCoalescedItem(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
begin
  Result := TryPostWorkItem(aItem, True, aCoalesceIdentity);
end;

function TmaxMailbox.TryPostWorkItem(const aItem: ImaxMailboxWorkItem; aHasCoalesceIdentity: Boolean;
  const aCoalesceIdentity: string): Boolean;
var
  lDeadlineMs: Cardinal;
  lStarted: TStopwatch;
begin
  Result := False;
  if aItem = nil then
    Exit;

  lStarted := TStopwatch.StartNew;
  lDeadlineMs := DeadlineMsFromPolicy(fPolicy);

  TMonitor.Enter(fLock);
  try
    while True do
    begin
      if fClosed then
        Exit(False);

      if aHasCoalesceIdentity and TryReplacePendingLocked(aCoalesceIdentity, aItem) then
        Exit(True);

      if HasPendingCapacityLocked then
      begin
        EnqueueLocked(TmaxMailboxQueueEntry.Create(aItem, aCoalesceIdentity, aHasCoalesceIdentity));
        Exit(True);
      end;

      case fPolicy.Overflow of
        MailboxDropNewest:
          Exit(False);
        MailboxDropOldest:
          begin
            DropOldestLocked;
            EnqueueLocked(TmaxMailboxQueueEntry.Create(aItem, aCoalesceIdentity, aHasCoalesceIdentity));
            Exit(True);
          end;
      else
        if not TryWaitForCapacityLocked(lStarted, lDeadlineMs) then
          Exit(False);
      end;
    end;
  finally
    TMonitor.Exit(fLock);
  end;
end;

class function TmaxMailbox.NormalizePolicy(const aPolicy: TmaxMailboxPolicy): TmaxMailboxPolicy;
begin
  Result := aPolicy;
  if Result.MaxDepth < 0 then
    Result.MaxDepth := 0;
  if Result.DeadlineUs < 0 then
    Result.DeadlineUs := 0;
end;

function TmaxMailbox.TryReplacePendingLocked(const aCoalesceIdentity: string; const aItem: ImaxMailboxWorkItem): Boolean;
var
  lEntry: TmaxMailboxQueueEntry;
begin
  Result := fCoalesceIndex.TryGetValue(aCoalesceIdentity, lEntry);
  if Result then
    lEntry.WorkItem := aItem;
end;

function TmaxMailbox.TryWaitForCapacityLocked(const aStarted: TStopwatch; aDeadlineMs: Cardinal): Boolean;
var
  lElapsedMs: Int64;
  lRemainingMs: Int64;
begin
  case fPolicy.Overflow of
    MailboxBlock:
      begin
        TMonitor.Wait(fLock, cMaxWaitInfinite);
        Exit(True);
      end;
    MailboxDeadline:
      begin
        if aDeadlineMs = 0 then
          Exit(False);
        lElapsedMs := aStarted.ElapsedMilliseconds;
        lRemainingMs := Int64(aDeadlineMs) - lElapsedMs;
        if lRemainingMs <= 0 then
          Exit(False);
        Result := TMonitor.Wait(fLock, Cardinal(lRemainingMs));
      end;
  else
    Result := False;
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
