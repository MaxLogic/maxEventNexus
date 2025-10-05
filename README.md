# EventNexus

EventNexus is a type‑safe, high‑performance event bus for Delphi 12+ and FPC 3.2.2. It decouples publishers and subscribers across typed, GUID, and string‑named topics while remaining thread‑safe and allocation‑light.

## Quick start

```pascal
uses maxLogic.EventNexus;

type
  TOrderPlaced = record
    Id: Integer;
  end;

var
  Sub: IMLSubscription;
begin
  Sub := MLBus.Subscribe<TOrderPlaced>(
    procedure(const E: TOrderPlaced)
    begin
      // handle event
    end,
    Posting);

  MLBus.Post<TOrderPlaced>(Default(TOrderPlaced));
end;
```

On Delphi, you can tag methods with `MLSubscribe` and register them automatically:

```pascal
{$IFDEF ML_DELPHI}
{$RTTI EXPLICIT METHODS([vcPublic, vcProtected])}
type
  TWorker = class
  public
    [MLSubscribe]
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
  MLBus.Post<Integer>(42);
  AutoUnsubscribe(LWorker);
  LWorker.Free;
end;
{$ENDIF}
```

See `samples/AutoSubscribeSample.pas` for a full program.

Manual registration offers identical behavior on all compilers:

```pascal
var
  lSub: IMLSubscription;
begin
  lSub := MLBus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Writeln('ping ', aValue);
    end);
  MLBus.Post<Integer>(42);
  lSub.Unsubscribe;
end;
```

See `samples/ManualSubscribeSample.pas` for a parity demonstration.

## Documentation

* [Bus specification](spec-bus.md)
* [Additional docs](docs/)
