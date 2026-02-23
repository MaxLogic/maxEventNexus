unit MaxEventNexus.Testing;

interface

uses
  SysUtils, System.Rtti, System.TypInfo, DUnitX.TestFramework;

type
  TmaxTestCase = class
  protected
    procedure Check(aCondition: Boolean; const aMsg: string = '');
    procedure CheckEquals(aExpected, aActual: Integer; const aMsg: string = ''); overload;
    procedure CheckEquals(aExpected: Integer; aActual: UInt64; const aMsg: string = ''); overload;
    procedure CheckEquals(aExpected: UInt64; aActual: Integer; const aMsg: string = ''); overload;
    procedure CheckEquals(aExpected, aActual: UInt64; const aMsg: string = ''); overload;
    procedure CheckEquals(const aExpected, aActual: string; const aMsg: string = ''); overload;
  end;

  TmaxTestCaseClass = class of TmaxTestCase;

procedure RunPublishedTests(const aSuiteName: string; const aCases: array of TmaxTestCaseClass);

implementation

procedure TmaxTestCase.Check(aCondition: Boolean; const aMsg: string);
begin
  Assert.IsTrue(aCondition, aMsg);
end;

procedure TmaxTestCase.CheckEquals(aExpected, aActual: Integer; const aMsg: string);
begin
  Assert.AreEqual<Integer>(aExpected, aActual, aMsg);
end;

procedure TmaxTestCase.CheckEquals(aExpected: Integer; aActual: UInt64; const aMsg: string);
begin
  CheckEquals(UInt64(aExpected), aActual, aMsg);
end;

procedure TmaxTestCase.CheckEquals(aExpected: UInt64; aActual: Integer; const aMsg: string);
begin
  CheckEquals(aExpected, UInt64(aActual), aMsg);
end;

procedure TmaxTestCase.CheckEquals(aExpected, aActual: UInt64; const aMsg: string);
begin
  Assert.AreEqual<UInt64>(aExpected, aActual, aMsg);
end;

procedure TmaxTestCase.CheckEquals(const aExpected, aActual: string; const aMsg: string);
begin
  Assert.AreEqual<string>(aExpected, aActual, aMsg);
end;

procedure RunPublishedTests(const aSuiteName: string; const aCases: array of TmaxTestCaseClass);
var
  lCaseClass: TmaxTestCaseClass;
  lCaseName: string;
  lCaseObj: TmaxTestCase;
  lContext: TRttiContext;
  lMethod: TRttiMethod;
  lMethodName: string;
  lParams: TArray<TRttiParameter>;
  lType: TRttiType;
begin
  lContext := TRttiContext.Create;
  try
    for lCaseClass in aCases do
    begin
      lCaseObj := lCaseClass.Create;
      try
        lCaseName := lCaseClass.ClassName;
        lType := lContext.GetType(lCaseClass);
        for lMethod in lType.GetMethods do
        begin
          if lMethod.Visibility <> mvPublished then
            Continue;
          lParams := lMethod.GetParameters;
          if Length(lParams) <> 0 then
            Continue;
          lMethodName := lMethod.Name;
          try
            lMethod.Invoke(lCaseObj, []);
          except
            on lException: Exception do
              raise Exception.CreateFmt('%s.%s.%s failed: %s: %s',
                [aSuiteName, lCaseName, lMethodName, lException.ClassName, lException.Message]);
          end;
        end;
      finally
        lCaseObj.Free;
      end;
    end;
  finally
    lContext.Free;
  end;
end;

end.
