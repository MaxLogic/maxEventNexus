program ConsoleSample;

{$I ..\..\MaxLogicFoundation\fpc_delphimode.inc}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Threading.RawThread,
  {$IFDEF max_DELPHI}
  maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.TTask,
  {$ENDIF}
  maxLogic.EventNexus.Threading.Adapter;

type
  ITextMsg = interface
    ['{E4D4C2A1-89D4-4F8C-8A25-5FA3086C35F0}']
    function Text: string;
  end;

  TTextMsg = class(TInterfacedObject, ITextMsg)
  private
    fText: string;
  public
    constructor Create(const aText: string);
    function Text: string;
  end;

constructor TTextMsg.Create(const aText: string);
begin
  inherited Create;
  fText := aText;
end;

function TTextMsg.Text: string;
begin
  Result := fText;
end;

  var
    lBus: ImaxBus;
    lPolicy: TmaxQueuePolicy;
    lSub: ImaxSubscription;
    schedulerArg: string;

procedure OnInt(const aValue: Integer);
begin
  Writeln('typed: ', aValue);
end;

procedure OnNamed;
begin
  Writeln('named');
end;

procedure OnGuid(const aValue: ITextMsg);
begin
  Writeln('guid: ', aValue.Text);
end;

procedure OnAsync(const aValue: string);
begin
  Writeln('async: ', aValue);
end;

function KeyOfInt(const aValue: Integer): TmaxString;
begin
  Result := IntToStr(aValue mod 10);
end;

procedure ConfigureScheduler;
begin
  if ParamCount = 0 then
  begin
    Writeln('Scheduler: default raw-thread');
    Exit;
  end;
  schedulerArg := LowerCase(ParamStr(1));
  if schedulerArg = 'raw' then
  begin
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    Writeln('Scheduler: raw-thread');
  end
  else if schedulerArg = 'maxasync' then
  begin
  {$IFDEF max_DELPHI}
    maxSetAsyncScheduler(CreateMaxAsyncScheduler);
    Writeln('Scheduler: maxAsync');
  {$ELSE}
    Writeln('maxAsync scheduler unavailable on this compiler; using default raw-thread.');
  {$ENDIF}
  end
  else if schedulerArg = 'ttask' then
  begin
  {$IFDEF max_DELPHI}
    maxSetAsyncScheduler(CreateTTaskScheduler);
    Writeln('Scheduler: TTask');
  {$ELSE}
    Writeln('TTask scheduler unavailable on this compiler; using default raw-thread.');
  {$ENDIF}
  end
  else
    Writeln('Unknown scheduler "', schedulerArg,
      '". Options: raw | maxasync | ttask. Using default raw-thread.');
end;

  begin
    ConfigureScheduler;
    lBus := maxBus;

  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
    (lBus as ImaxBusQueues).SetPolicyFor<Integer>(lPolicy);
    (lBus as ImaxBusAdvanced).EnableSticky<Integer>(True);
{$IFDEF FPC}
    (lBus as ImaxBusAdvanced).EnableCoalesceOf<Integer>(@KeyOfInt);
    lSub := lBus.Subscribe<Integer>(@OnInt);
    lBus.SubscribeNamed('tick', @OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(@OnGuid);
    lBus.Subscribe<string>(@OnAsync, TmaxDelivery.Async);
{$ELSE}
    (lBus as ImaxBusAdvanced).EnableCoalesceOf<Integer>(KeyOfInt);
    lSub := lBus.Subscribe<Integer>(OnInt);
    lBus.SubscribeNamed('tick', OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(OnGuid);
    lBus.Subscribe<string>(OnAsync, TmaxDelivery.Async);
{$ENDIF}

  lBus.Post<Integer>(1);
  lBus.Post<Integer>(2);
  lBus.Post<Integer>(12);
  Sleep(50);

  lBus.PostNamed('tick');
  lBus.PostGuidOf<ITextMsg>(TTextMsg.Create('hello'));
  lBus.Post<string>('world');
  Sleep(50);
  lSub.Unsubscribe;
end.
