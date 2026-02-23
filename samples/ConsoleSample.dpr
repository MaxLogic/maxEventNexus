program ConsoleSample;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Core,
  maxLogic.EventNexus.Threading.RawThread,
  maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.TTask,
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
    lBusObj: TmaxBus;
    lPolicy: TmaxQueuePolicy;
    lSub: ImaxSubscription;
    lSchedulerArg: string;

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
  lSchedulerArg := LowerCase(ParamStr(1));
  if lSchedulerArg = 'raw' then
  begin
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    Writeln('Scheduler: raw-thread');
  end
  else if lSchedulerArg = 'maxasync' then
  begin
    maxSetAsyncScheduler(CreateMaxAsyncScheduler);
    Writeln('Scheduler: maxAsync');
  end
  else if lSchedulerArg = 'ttask' then
  begin
    maxSetAsyncScheduler(CreateTTaskScheduler);
    Writeln('Scheduler: TTask');
  end
  else
    Writeln('Unknown scheduler "', lSchedulerArg,
      '". Options: raw | maxasync | ttask. Using default raw-thread.');
end;

  begin
    ConfigureScheduler;
    lBus := maxBus;
    lBusObj := maxBusObj(lBus);

  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
    lBusObj.SetPolicyFor<Integer>(lPolicy);
    lBusObj.EnableSticky<Integer>(True);
    lBusObj.EnableCoalesceOf<Integer>(KeyOfInt);
    lSub := lBusObj.Subscribe<Integer>(OnInt);
    lBusObj.SubscribeNamed('tick', OnNamed);
    lBusObj.SubscribeGuidOf<ITextMsg>(OnGuid);
    lBusObj.Subscribe<string>(OnAsync, TmaxDelivery.Async);

  lBusObj.Post<Integer>(1);
  lBusObj.Post<Integer>(2);
  lBusObj.Post<Integer>(12);
  Sleep(50);

  lBusObj.PostNamed('tick');
  lBusObj.PostGuidOf<ITextMsg>(TTextMsg.Create('hello'));
  lBusObj.Post<string>('world');
  Sleep(50);
  lSub.Unsubscribe;
end.
