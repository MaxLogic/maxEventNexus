# EventNexus


## What's New (2025-12-15)

* **Subscription tokens** — `Subscribe*` returns an `ImaxSubscription` token. Releasing the last reference auto‑unsubscribes (idempotent).
* **Weak‑target liveness guard** — For object‑method handlers we store `{CodePtr, WeakTarget}` and rehydrate at dispatch:
  * **Delphi 12+ / FPC 3.2.2**: lightweight `(Ptr → Generation)` registry; invoke only if generation matches (Delphi uses a `FreeInstance` hook; no AV probing).
* **Queued‑before‑cancel safety** — Enqueued work prior to cancel uses the liveness check; dead targets are skipped and subscriptions are pruned lazily.
* **Main delivery policy** — `maxSetMainThreadPolicy(...)` controls how `Main` delivery degrades in console contexts when a UI main thread is unavailable. (T-1003)
* **GUID advanced controls** — GUID topics now support coalescing, queue policies, `TryPostGuidOf`, and GUID stats retrieval. (T-1035)
* **Metric sampling throttling** — `maxSetMetricSampleInterval(...)` limits metric callback frequency for high-rate topics. (T-1004)
* **Lock-free metrics snapshots** — `GetTotals` / `GetStats*` read without taking bus locks; per-topic counters are atomic. (T-1036)
* **Queue policy presets** — apply spec defaults via `maxSetQueuePreset*` when we haven't set an explicit policy. (T-1029)
* **No global bus lock** — posts no longer serialize across unrelated topics; registries and per-topic state use fine-grained synchronization. (T-1040)
* **Post hot-path allocations reduced** — Posting-mode Post/TryPost avoids per-subscriber heap allocations in the steady state. (T-1031)
* **Design & Spec updated** — See [`DESIGN.md`](DESIGN.md) and [`spec.md`](spec.md) for full details (tokens, pruning, dispatch path, executors).
* **Delphi vs FPC generics** — FPC supports generic methods on interfaces; on Delphi we use the concrete `TmaxBus` (via `maxAsBus(...)`) for generic calls.


EventNexus is a type‑safe, high‑performance event bus for Delphi 12+ and FPC 3.2.2. It decouples publishers and subscribers across typed, GUID, and string‑named topics while remaining thread‑safe and allocation‑light.

## Quick start

Delphi 12+:

```pascal
uses maxLogic.EventNexus, maxLogic.EventNexus.Core;

type
  TOrderPlaced = record
    Id: Integer;
  end;

var
  Bus: TmaxBus;
  Sub: ImaxSubscription;
begin
  Bus := TmaxBus(maxAsBus(maxBus));
  Sub := Bus.Subscribe<TOrderPlaced>(
    procedure(const E: TOrderPlaced)
    begin
      // handle event
    end,
    TmaxDelivery.Posting);

  Bus.Post<TOrderPlaced>(Default(TOrderPlaced));
end;
```

FPC 3.2.2:

```pascal
uses maxLogic_EventNexus_Core;

type
  TOrderPlaced = record
    Id: Integer;
  end;

var
  Sub: ImaxSubscription;

procedure HandleOrderPlaced(const E: TOrderPlaced);
begin
  // handle event
end;

begin
  Sub := maxBus.Subscribe<TOrderPlaced>(@HandleOrderPlaced, TmaxDelivery.Posting);
  maxBus.Post<TOrderPlaced>(Default(TOrderPlaced));
end.
```

On Delphi, you can tag methods with `maxSubscribe` and register them automatically:

```pascal
{$IFNDEF FPC}
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
  TmaxBus(maxAsBus(maxBus)).Post<Integer>(42);
  AutoUnsubscribe(LWorker);
  LWorker.Free;
end;
{$ENDIF}
```

See `samples/AutoSubscribeSample.pas` for a full program.

Manual registration offers identical behavior on all compilers (named topics are always available on `ImaxBus`):

```pascal
{$IFDEF FPC}
procedure HandlePing;
begin
  Writeln('ping');
end;
{$ENDIF}

var
  lSub: ImaxSubscription;
begin
  {$IFDEF FPC}
  lSub := maxBus.SubscribeNamed('ping', @HandlePing, TmaxDelivery.Posting);
  {$ELSE}
  lSub := maxBus.SubscribeNamed('ping',
    procedure
    begin
      Writeln('ping');
    end,
    TmaxDelivery.Posting);
  {$ENDIF}
  maxBus.PostNamed('ping');
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

## Advanced usage

Enable sticky delivery (late subscribers get the latest cached value):

```pascal
var
  Adv: ImaxBusAdvanced;
begin
  Adv := maxBus as ImaxBusAdvanced;
  {$IFDEF FPC}
  Adv.EnableSticky<TOrderPlaced>(True);
  {$ELSE}
  TmaxBus(maxAsBus(Adv)).EnableSticky<TOrderPlaced>(True);
  {$ENDIF}
end;
```

Enable coalescing (only deliver the latest per key within a window):

```pascal
var
  Adv: ImaxBusAdvanced;
begin
  Adv := maxBus as ImaxBusAdvanced;
  {$IFDEF FPC}
  Adv.EnableCoalesceOf<TKeyed>(
    function(const aValue: TKeyed): TmaxString
    begin
      Result := aValue.Key;
    end,
    10000 {us});
  {$ELSE}
  TmaxBus(maxAsBus(Adv)).EnableCoalesceOf<TKeyed>(
    function(const aValue: TKeyed): TmaxString
    begin
      Result := aValue.Key;
    end,
    10000 {us});
  {$ENDIF}
end;
```

Queue policy configuration (bounded queues + overflow behavior):

```pascal
var
  Q: ImaxBusQueues;
  P: TmaxQueuePolicy;
begin
  Q := maxBus as ImaxBusQueues;
  P.MaxDepth := 256;
  P.Overflow := TmaxOverflow.DropOldest;
  P.DeadlineUs := 0;
  Q.SetPolicyNamed('orders.state', P);
end;
```

Queue policy presets (spec defaults) for topics where we haven't set an explicit policy:

```pascal
maxSetQueuePresetNamed('orders.state', TmaxQueuePreset.State);
maxSetQueuePresetForType(TypeInfo(TOrderPlaced), TmaxQueuePreset.Action);
maxSetQueuePresetGuid(StringToGUID('{00000000-0000-0000-0000-000000000000}'), TmaxQueuePreset.ControlPlane);
```

Metrics sampling (install a callback + throttle interval):

```pascal
maxSetMetricSampleInterval(250);
maxSetMetricCallback(
  procedure(const aName: string; const aStats: TmaxTopicStats)
  begin
    // aName is the metric topic name; aStats is a cheap snapshot
  end);
```

## Performance

* Target performance envelopes and constraints are defined in `spec.md` (§7).
* See `bench/` for the benchmark harness and methodology.

## Documentation

* [Bus specification](spec.md)
* [Architecture](DESIGN.md)
