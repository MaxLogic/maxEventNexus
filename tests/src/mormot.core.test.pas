unit mormot.core.Test;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
{$DEFINE max_FPC}
{$ELSE}
{$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes,
  {$IFDEF max_DELPHI} System.Generics.Collections, System.Rtti {$ELSE} Generics.Collections {$ENDIF};

type
  TSynTestCase = class
  protected
    procedure Check(Condition: boolean; const msg: string = ''); overload;
    procedure CheckEquals(Expected, Actual: integer; const msg: string = ''); overload;
    procedure CheckEquals(Expected: integer; Actual: uInt64; const msg: string = ''); overload;
    procedure CheckEquals(Expected: uInt64; Actual: integer; const msg: string = ''); overload;
    procedure CheckEquals(Expected, Actual: uInt64; const msg: string = ''); overload;
    procedure CheckEquals(const Expected, Actual: string; const msg: string = ''); overload;
  end;

  TSynTestCaseClass = class of TSynTestCase;

  TSynTests = class
  private
    FName: string;
    fCases: TList<TSynTestCaseClass>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure AddCase(TestClass: TSynTestCaseClass);
    procedure Run;
  end;

implementation

uses
  TypInfo;

procedure TSynTestCase.Check(Condition: boolean; const msg: string);
begin
  if not Condition then
    if msg <> '' then
      raise Exception.Create(msg)
    else
      raise Exception.Create('Check failed');
end;

procedure TSynTestCase.CheckEquals(Expected, Actual: integer; const msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if msg <> '' then
      Detail := ' ' + msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected %d but got %d.%s', [Expected, Actual, Detail]);
  end;
end;

procedure TSynTestCase.CheckEquals(Expected: integer; Actual: uInt64; const msg: string);
begin
  CheckEquals(uInt64(Expected), Actual, msg);
end;

procedure TSynTestCase.CheckEquals(Expected: uInt64; Actual: integer; const msg: string);
begin
  CheckEquals(Expected, uInt64(Actual), msg);
end;

procedure TSynTestCase.CheckEquals(Expected, Actual: uInt64; const msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if msg <> '' then
      Detail := ' ' + msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected %s but got %s.%s', [UIntToStr(Expected), UIntToStr(Actual), Detail]);
  end;
end;

procedure TSynTestCase.CheckEquals(const Expected, Actual: string; const msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if msg <> '' then
      Detail := ' ' + msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected "%s" but got "%s".%s', [Expected, Actual, Detail]);
  end;
end;

constructor TSynTests.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  fCases := TList<TSynTestCaseClass>.Create;
end;

destructor TSynTests.Destroy;
begin
  fCases.Free;
  inherited Destroy;
end;

procedure TSynTests.AddCase(TestClass: TSynTestCaseClass);
begin
  fCases.Add(TestClass);
end;

procedure TSynTests.Run;
{$IFDEF max_DELPHI}
var
  Ctx: TRttiContext;
  TestClass: TSynTestCaseClass;
  TestObj: TSynTestCase;
  Typ: TRttiType;
  Meth: TRttiMethod;
  Params: TArray<TRttiParameter>;
  Passed, Failed: integer;
begin
  Passed := 0;
  Failed := 0;
  Ctx := TRttiContext.Create;
  try
    for TestClass in fCases do
    begin
      TestObj := TestClass.Create;
      try
        Typ := Ctx.GetType(TestClass);
        for Meth in Typ.GetMethods do
          if Meth.Visibility = mvPublished then
          begin
            Params := Meth.GetParameters;
            if length(Params) = 0 then
            begin
              Write('[', TestClass.classname, '.', Meth.Name, '] ');
              try
                Meth.Invoke(TestObj, []);
                writeln('OK');
                Inc(Passed);
              except
                on e: Exception do
                begin
                  writeln('FAIL - ', e.classname, ': ', e.Message);
                  Inc(Failed);
                end;
              end;
            end;
          end;
      finally
        TestObj.Free;
      end;
    end;
  finally
    Ctx.Free;
  end;
  if Failed > 0 then
  begin
    writeln(Format('%s FAILED (%d passed, %d failed)', [FName, Passed, Failed]));
    Halt(1);
  end
  else
    writeln(Format('%s SUCCESS (%d passed)', [FName, Passed]));
end;
{$ELSE}
begin
  writeln('TSynTests.Run is not implemented for this compiler.');
  Halt(1);
end;
{$ENDIF}

end.

