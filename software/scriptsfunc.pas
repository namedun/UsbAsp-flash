unit scriptsfunc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Variants, PasCalc, Dialogs, graphics,
  usbasp25, msgstr;

procedure SetScriptFunctions(PC : TPasCalc);
procedure SetScriptVars();
procedure RunScript(ScriptText: TStrings);
function RunScriptFromFile(ScriptFile: string; Section: string): boolean;
function ParseScriptText(Script: TStrings; SectionName: string; var ScriptText: TStrings ): Boolean;

implementation

uses main, scriptedit;

function ParseScriptText(Script: TStrings; SectionName: string; var ScriptText: TStrings ): Boolean;
var
  st: string;
  i: integer;
  s: boolean;
begin
  Result := false;
  s:= false;

  for i:=0 to Script.Count-1 do
  begin
    st:= Script.Strings[i];

    if s then
    begin
      if Trim(Copy(st, 1, 2)) = '{$' then break;
      ScriptText.Append(st);
    end
    else
    begin
      st:= StringReplace(st, ' ', '', [rfReplaceAll]);
      if Upcase(st) = '{$' + Upcase(SectionName) + '}' then
      begin
        s := true;
        Result := true;
      end;
    end;

  end;
end;

procedure RunScript(ScriptText: TStrings);
var
  TimeCounter: TDateTime;
begin
  LogPrint(TimeToStr(Time()));
  TimeCounter := Time();
  MainForm.Log.Append(STR_USING_SCRIPT + CurrentICParam.Script);

  RomF.Clear;

  //Предопределяем переменные
  ScriptEngine.ClearVars;
  SyncUI_ICParam();
  SetScriptVars();

  MainForm.StatusBar.Panels.Items[2].Text := CurrentICParam.Name;
  ScriptEngine.Execute(ScriptText.Text);

  if ScriptEngine.ErrCode<>0 then
  begin
    if not ScriptEditForm.Visible then
    begin
      LogPrint(ScriptEngine.ErrMsg, clRed);
      LogPrint(ScriptEngine.ErrLine, clRed);
    end
    else
    begin
      ScriptLogPrint(ScriptEngine.ErrMsg, clRed);
      ScriptLogPrint(ScriptEngine.ErrLine, clRed);
    end;
  end;

  LogPrint(STR_TIME + TimeToStr(Time() - TimeCounter));
end;

function RunScriptFromFile(ScriptFile: string; Section: string): boolean;
var
  ScriptText, ParsedScriptText: TStrings;
begin
  if not FileExists(ScriptsPath+ScriptFile) then Exit(false);
  try
    ScriptText:= TStringList.Create;
    ParsedScriptText:= TStringList.Create;

    ScriptText.LoadFromFile(ScriptsPath+ScriptFile);
    if not ParseScriptText(ScriptText, Section, ParsedScriptText) then Exit(false);
    RunScript(ParsedScriptText);
    Result := true;
  finally
    ScriptText.Free;
    ParsedScriptText.Free;
  end;
end;

function VarIsString(V : TVar) : boolean;
var t: integer;
begin
  t := VarType(V.Value);
  Result := (t=varString) or (t=varOleStr);
end;


//------------------------------------------------------------------------------
function Script_ShowMessage(Sender:TObject; var A:TVarList) : boolean;
var s: string;
begin
  if A.Count < 1 then Exit(false);

  s := TPVar(A.Items[0])^.Value;
  ShowMessage(s);
  Result := true;
end;

function Script_LogPrint(Sender:TObject; var A:TVarList) : boolean;
var
  s: string;
  color: TColor;
begin
  if A.Count < 1 then Exit(false);

  color := 0;
  if A.Count > 1 then color := TPVar(A.Items[1])^.Value;

  s := TPVar(A.Items[0])^.Value;
  LogPrint('Script: ' + s, color);
  Result := true;
end;

function Script_IntToHex(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
begin
  if A.Count < 2 then Exit(false);

  R.Value:= IntToHex(Int64(TPVar(A.Items[0])^.Value), TPVar(A.Items[1])^.Value);
  Result := true;
end;

function Script_SetSPISpeed(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
var speed: byte;
begin
  if A.Count < 1 then Exit(false);

  speed := TPVar(A.Items[0])^.Value;
  if UsbAsp_SetISPSpeed(hUSBDev, speed) <> 0 then
    R.Value := False
  else
    R.Value := True;
  Result := true;
end;

function Script_EnterProgModeSPI(Sender:TObject; var A:TVarList) : boolean;
begin
  EnterProgMode25(hUSBdev);
  Result := true;
end;

function Script_ExitProgModeSPI(Sender:TObject; var A:TVarList) : boolean;
begin
  ExitProgMode25(hUSBdev);
  Result := true;
end;

//inc, (max, pos)
function Script_ProgressBar(Sender:TObject; var A:TVarList) : boolean;
begin

  if A.Count < 1 then Exit(false);

  MainForm.ProgressBar.Position := MainForm.ProgressBar.Position + TPVar(A.Items[0])^.Value;

  if A.Count > 1 then
    MainForm.ProgressBar.Max := TPVar(A.Items[1])^.Value;
  if A.Count > 2 then
    MainForm.ProgressBar.Position := TPVar(A.Items[2])^.Value;

  Result := true;
end;

//cs, size, buffer..
function Script_SPIRead(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  i: integer;
  DataArr: array of byte;
begin

  if A.Count < 3 then Exit(false);

  SetLength(DataArr, A.Count);

  R.Value := SPIRead(hUSBdev, TPVar(A.Items[0])^.Value, TPVar(A.Items[1])^.Value, DataArr[0]);

  for i := 0 to A.Count-3 do
  begin
    TPVar(A.Items[i+2])^.Value := DataArr[i];
  end;

  Result := true;
end;

//cs, size, buffer..
function Script_SPIWrite(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  i, BufferLen: integer;
  DataArr: array of byte;
begin

  if A.Count < 3 then Exit(false);

  BufferLen := TPVar(A.Items[1])^.Value;
  SetLength(DataArr, BufferLen);

  for i := 0 to BufferLen-1 do
  begin
    DataArr[i] := TPVar(A.Items[i+2])^.Value;
  end;

  R.Value := SPIWrite(hUSBdev, TPVar(A.Items[0])^.Value, BufferLen, DataArr);
  Result := true;
end;

//cs, size
function Script_SPIReadToEditor(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  DataArr: array of byte;
  BufferLen: integer;
begin

  if A.Count < 2 then Exit(false);

  BufferLen := TPVar(A.Items[1])^.Value;
  SetLength(DataArr, BufferLen);

  R.Value := SPIRead(hUSBdev, TPVar(A.Items[0])^.Value, BufferLen, DataArr[0]);

  RomF.WriteBuffer(DataArr[0], BufferLen);
  RomF.Position := 0;
  MainForm.KHexEditor.LoadFromStream(RomF);

  Result := true;
end;

//cs, size, position
function Script_SPIWriteFromEditor(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  DataArr: array of byte;
  BufferLen: integer;
begin

  if A.Count < 3 then Exit(false);

  BufferLen := TPVar(A.Items[1])^.Value;
  SetLength(DataArr, BufferLen);

  RomF.Clear;
  MainForm.KHexEditor.SaveToStream(RomF);
  RomF.Position := TPVar(A.Items[2])^.Value;
  RomF.ReadBuffer(DataArr[0], BufferLen);

  R.Value := SPIWrite(hUSBdev, TPVar(A.Items[0])^.Value, BufferLen, DataArr);

  Result := true;
end;

//------------------------------------------------------------------------------
procedure SetScriptFunctions(PC : TPasCalc);
begin
  PC.SetFunction('ShowMessage', @Script_ShowMessage);
  PC.SetFunction('LogPrint', @Script_LogPrint);
  PC.SetFunction('ProgressBar', @Script_ProgressBar);

  PC.SetFunction('SetSPISpeed', @Script_SetSPISpeed);
  PC.SetFunction('EnterProgModeSPI', @Script_EnterProgModeSPI);
  PC.SetFunction('ExitProgModeSPI', @Script_ExitProgModeSPI);
  PC.SetFunction('SPIRead', @Script_SPIRead);
  PC.SetFunction('SPIWrite', @Script_SPIWrite);
  PC.SetFunction('SPIReadToEditor', @Script_SPIReadToEditor);
  PC.SetFunction('SPIWriteFromEditor', @Script_SPIWriteFromEditor);
  PC.SetFunction('IntToHex', @Script_IntToHex);
end;

procedure SetScriptVars();
begin
  ScriptEngine.SetValue('IC_Name', CurrentICParam.Name);
  ScriptEngine.SetValue('IC_Size', CurrentICParam.Size);
  ScriptEngine.SetValue('IC_Page', CurrentICParam.Page);
  ScriptEngine.SetValue('IC_SpiCmd', CurrentICParam.SpiCmd);
  ScriptEngine.SetValue('IC_MWAddrLen', CurrentICParam.MWAddLen);
  ScriptEngine.SetValue('IC_I2CAddrType', CurrentICParam.I2CAddrType);
end;

end.
