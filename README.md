# EventNexus


## What's New (2025-10-06)

* **Subscription tokens** — `Subscribe*` returns an `ISubscription` token. Releasing the last reference auto‑unsubscribes (idempotent).
* **Weak‑target liveness guard** — For object‑method handlers we store `{CodePtr, WeakTarget}` and rehydrate at dispatch:
  * **Delphi 12+**: `System.WeakReference.TWeakReference<TObject>`; invoke only if `TryGetTarget` succeeds.
  * **FPC 3.2.2**: lightweight `(Ptr → Generation)` registry; invoke only if generation matches.
* **Queued‑before‑cancel safety** — Enqueued work prior to cancel uses the liveness check; dead targets are skipped and subscriptions are pruned lazily.
* **Design & Spec updated** — See [`DESIGN.md`](DESIGN.md) and [`spec.md`](spec.md) for full details (tokens, pruning, dispatch path, executors).
* **Generic API on interfaces** — All generic methods (`Subscribe<T>`, `Post<T>`, `TryPost<T>`, and advanced/queue/metrics generics) are now directly available on the core interfaces (`ImaxBus`, `ImaxBusAdvanced`, `ImaxBusQueues`, `ImaxBusMetrics`) on all supported compilers. (T-1028)


EventNexus is a type‑safe, high‑performance event bus for Delphi 12+ and FPC 3.2.2. It decouples publishers and subscribers across typed, GUID, and string‑named topics while remaining thread‑safe and allocation‑light.

## Quick start

```pascal
uses maxLogic.EventNexus;

type
  TOrderPlaced = record
    Id: Integer;
  end;

var
  Sub: ImaxSubscription;
begin
  Sub := maxBus.Subscribe<TOrderPlaced>(
    procedure(const E: TOrderPlaced)
    begin
      // handle event
    end,
    Posting);

  maxBus.Post<TOrderPlaced>(Default(TOrderPlaced));
end;
```

On Delphi, you can tag methods with `maxSubscribe` and register them automatically:

```pascal
{$IFDEF max_DELPHI}
{$RTTI EXPLICIT METHODS([vcPublic, vcProtected])}
type
  TWorker = class
  public
    [maxSubscribe]
    procedure OnPing(const aValue: Integer);
  end;

procedure TWorker.OnPing(const aValue: Integer);
begin
  Writeln('ping ', aValue);
end;

var LWorker: TWorker;
begin
  LWorker := TWorker.Create;
  AutoSubscribe(LWorker);
  maxBus.Post<Integer>(42);
  AutoUnsubscribe(LWorker);
  LWorker.Free;
end;
{$ENDIF}
```

See `samples/AutoSubscribeSample.pas` for a full program.

Manual registration offers identical behavior on all compilers:

```pascal
var
  lSub: ImaxSubscription;
begin
  lSub := maxBus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Writeln('ping ', aValue);
    end);
  maxBus.Post<Integer>(42);
  lSub.Unsubscribe;
end;
```

See `samples/ManualSubscribeSample.pas` for a parity demonstration.

## Async Schedulers

EventNexus ships multiple scheduler adapters implementing `IEventNexusScheduler`:

* `maxLogic.EventNexus.Threading.RawThread` (default fallback) spins lightweight threads per task.
* `maxLogic.EventNexus.Threading.MaxAsync` uses `maxAsync.pas` from MaxLogicFoundation.
* `maxLogic.EventNexus.Threading.TTask` integrates Delphi's `System.Threading.TTask`.

Inject the adapter you want:

```pascal
uses maxLogic.EventNexus, maxLogic.EventNexus.Threading.MaxAsync;

begin
  maxSetAsyncScheduler(CreateMaxAsyncScheduler);
end;
```

Swap adapters at runtime to match your threading framework.

## Documentation

* [Bus specification](spec-bus.md)
* [Additional docs](docs/)
