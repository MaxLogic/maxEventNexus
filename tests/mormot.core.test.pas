unit mormot.core.test;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections
  {$IFDEF max_DELPHI}, System.Rtti{$ENDIF};

type
  TSynTestCase = class
  protected
    procedure Check(Condition: Boolean; const Msg: string = ''); overload;
    procedure CheckEquals(Expected, Actual: Integer; const Msg: string = ''); overload;
    procedure CheckEquals(Expected: Integer; Actual: UInt64; const Msg: string = ''); overload;
    procedure CheckEquals(Expected: UInt64; Actual: Integer; const Msg: string = ''); overload;
    procedure CheckEquals(Expected, Actual: UInt64; const Msg: string = ''); overload;
    procedure CheckEquals(const Expected, Actual: string; const Msg: string = ''); overload;
  end;

  TSynTestCaseClass = class of TSynTestCase;

  TSynTests = class
  private
    fName: string;
    fCases: TList<TSynTestCaseClass>;
  public
    constructor Create(const aName: string);
    destructor Destroy; override;
    procedure AddCase(TestClass: TSynTestCaseClass);
    procedure Run;
  end;

implementation

uses
  TypInfo;

procedure TSynTestCase.Check(Condition: Boolean; const Msg: string);
begin
  if not Condition then
    if Msg <> '' then
      raise Exception.Create(Msg)
    else
      raise Exception.Create('Check failed');
end;

procedure TSynTestCase.CheckEquals(Expected, Actual: Integer; const Msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Detail := ' ' + Msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected %d but got %d.%s', [Expected, Actual, Detail]);
  end;
end;

procedure TSynTestCase.CheckEquals(Expected: Integer; Actual: UInt64; const Msg: string);
begin
  CheckEquals(UInt64(Expected), Actual, Msg);
end;

procedure TSynTestCase.CheckEquals(Expected: UInt64; Actual: Integer; const Msg: string);
begin
  CheckEquals(Expected, UInt64(Actual), Msg);
end;

procedure TSynTestCase.CheckEquals(Expected, Actual: UInt64; const Msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Detail := ' ' + Msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected %s but got %s.%s', [UIntToStr(Expected), UIntToStr(Actual), Detail]);
  end;
end;

procedure TSynTestCase.CheckEquals(const Expected, Actual: string; const Msg: string);
var
  Detail: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Detail := ' ' + Msg
    else
      Detail := '';
    raise Exception.CreateFmt('Expected "%s" but got "%s".%s', [Expected, Actual, Detail]);
  end;
end;

constructor TSynTests.Create(const aName: string);
begin
  inherited Create;
  fName := aName;
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
  Passed, Failed: Integer;
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
            if Length(Params) = 0 then
            begin
              Write('[', TestClass.ClassName, '.', Meth.Name, '] ');
              try
                Meth.Invoke(TestObj, []);
                Writeln('OK');
                Inc(Passed);
              except
                on E: Exception do
                begin
                  Writeln('FAIL - ', E.ClassName, ': ', E.Message);
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
    Writeln(Format('%s FAILED (%d passed, %d failed)', [fName, Passed, Failed]));
    Halt(1);
  end
  else
    Writeln(Format('%s SUCCESS (%d passed)', [fName, Passed]));
end;
{$ELSE}
begin
  Writeln('TSynTests.Run is not implemented for this compiler.');
  Halt(1);
end;
{$ENDIF}

end.
