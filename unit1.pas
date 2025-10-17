unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Grids,
  ExtCtrls, Menus, Math, Types, LCLType, LCLIntf, Spin, StrUtils, Registry,
  Windows;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    CheckBox1: TCheckBox;
    edtLayerHeight: TFloatSpinEdit;
    edtResultX: TLabeledEdit;
    edtResultY: TLabeledEdit;
    Image1: TImage;
    Image2: TImage;
    Label1: TLabel;
    miSort: TMenuItem;
    miDeleteRow: TMenuItem;
    miAddRow: TMenuItem;
    Panel1: TPanel;
    PopupMenu1: TPopupMenu;
    sgDetails: TStringGrid;
    Timer1: TTimer;
    procedure Button1Click(Sender: TObject);
    procedure CheckBox1Change(Sender: TObject);
    procedure edtLayerHeightChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure miAddRowClick(Sender: TObject);
    procedure miDeleteRowClick(Sender: TObject);
    procedure miSortClick(Sender: TObject);
    procedure sgDetailsDrawCell(Sender: TObject; aCol, aRow: integer;
      aRect: TRect; aState: TGridDrawState);
    procedure sgDetailsEditingDone(Sender: TObject);
    procedure sgDetailsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure sgDetailsPrepareCanvas(Sender: TObject; aCol, aRow: integer;
      aState: TGridDrawState);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure SaveGrid;
    procedure LoadGrid;
    procedure SortGridByBrandAndModel;
    procedure AutoSizeGridColumns(Grid: TStringGrid);
    procedure ScrollToSelectedRow;
    procedure Calculate;
    function GetSelectedRow: integer;
    procedure GotoColRow(Col, Row: integer);
    procedure DrawAngle(thisCanvas: TCanvas; ImgWidth, ImgHeight: integer;
      AngleDeg: double);
    function GetFileVersionString(const AFileName, AKey: string): string;
  public

  end;

var
  Form1: TForm1;
  GotoCol, GotoRow: integer;

  // setup for saving the grid list of printers

implementation

const
  GRID_FILE = 'griddata.csv';
  DELIM = #9; // use TAB as delimiter, safer than comma

  {$R *.lfm}

  { TForm1 }


procedure TForm1.Button1Click(Sender: TObject);
begin
  Calculate;
end;

procedure TForm1.CheckBox1Change(Sender: TObject);
begin
  Calculate;
end;

procedure TForm1.edtLayerHeightChange(Sender: TObject);
var
  CurrentValue: double;
begin
  CurrentValue := edtLayerHeight.Value;
  if (CurrentValue >= edtLayerHeight.MinValue) and
    (CurrentValue <= edtLayerHeight.MaxValue) then
    Calculate;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    // Open or create your app's registry key  to save settings
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\Sla Angle Finder', True) then
    begin
      Reg.WriteFloat('LayerHeight', edtLayerHeight.Value);
      Reg.WriteBool('ShowComplimentary', CheckBox1.Checked);
    end;
  finally
    Reg.Free;
  end;
  SaveGrid;
end;

procedure TForm1.FormCreate(Sender: TObject);
var
   ProductName,FileVersion:String;
  Reg: TRegistry;
begin

  // load saved settings
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\Sla Angle Finder', False) then
    begin
      if Reg.ValueExists('LayerHeight') then
        edtLayerHeight.Value := Reg.ReadFloat('LayerHeight');
      if Reg.ValueExists('ShowComplimentary') then
        CheckBox1.Checked := Reg.ReadBool('ShowComplimentary');
    end;
  finally
    Reg.Free;
  end;
  LoadGrid;
  SortGridByBrandAndModel;   // sort  grid by name

  ScrollToSelectedRow;     // scroll to default row
  Calculate;
  Application.ShowHint := True;
  ProductName := GetFileVersionString(ParamStr(0), 'ProductName');
  FileVersion := GetFileVersionString(ParamStr(0), 'FileVersion');
   Caption := Format('%s - Version %s', [ProductName, FileVersion]) ;

end;

procedure TForm1.FormShow(Sender: TObject);
begin
  AutoSizeGridColumns(sgDetails); // Fit columns to text
end;

procedure TForm1.miAddRowClick(Sender: TObject);
begin
  // add a new row to the grid
  sgDetails.RowCount := sgDetails.RowCount + 1;
  sgDetails.Cells[0, sgDetails.RowCount - 1] := '0'; // unchecked
  sgDetails.TopRow := sgDetails.RowCount - 1;
  sgDetails.Col := 1;
  sgDetails.Row := sgDetails.RowCount - 1;
  sgDetails.EditorMode := True;

end;


// detete row
procedure TForm1.miDeleteRowClick(Sender: TObject);
begin
  if (sgDetails.Row > 0) and (sgDetails.Row < sgDetails.RowCount) then
  begin
    sgDetails.DeleteRow(sgDetails.Row);

  end;
end;

procedure TForm1.miSortClick(Sender: TObject);
begin
  SortGridByBrandAndModel;
  AutoSizeGridColumns(sgDetails);
end;


// draw the grid so that we have a radio button
procedure TForm1.sgDetailsDrawCell(Sender: TObject; aCol, aRow: integer;
  aRect: TRect; aState: TGridDrawState);
var
  r: TRect;
  Checked: boolean;
  flags: integer;
begin

  if (aCol = 0) and (aRow > 0) then
  begin
    sgDetails.Font.Style := [];
    sgDetails.Canvas.FillRect(aRect);
    Checked := sgDetails.Cells[aCol, aRow] = '1';
    r := aRect;
    InflateRect(r, -4, -4);

    // Draw as radio button in first column
    flags := DFCS_BUTTONRADIO;
    if Checked then
      flags := flags or DFCS_CHECKED;

    DrawFrameControl(sgDetails.Canvas.Handle, r, DFC_BUTTON, flags);
  end;
end;

// sanity check of grid entries
procedure TForm1.sgDetailsEditingDone(Sender: TObject);
var
  Z: double;
  s: string;
  reFocus: boolean;
  thisRow, thisCol: integer;
begin
  reFocus := False;
  if not (Sender is TStringGrid) then Exit;
  with sgDetails do
  begin
    thisRow := Row;
    thisCol := Col;
    if Col < 3 then exit;
    s := Cells[Col, Row];
    if not (TryStrToFloat(S, Z)) then
    begin
      MessageDlg('Error', 'Input is not a number!', mtError, [mbOK], 0);
      reFocus := True;
    end;
    if TryStrToFloat(S, Z) then
      if (Z < 0.001) or (Z > 0.2) then
      begin
        if MessageDlg('Sanity check!', 'The value entered is unlikely to be correct' +
          lineEnding + 'Are you sure?', mtWarning, [mbYes, mbNo], 0) <>
          mrYes then reFocus := True;

      end;

  end;
  if reFocus then
  begin
    GotoColRow(thisCol, thisRow);
  end;

end;

// select and unselect radio buttons

procedure TForm1.sgDetailsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  col, row, r: integer;
begin
  sgDetails.MouseToCell(X, Y, col, row);
  if (col = 0) and (row > 0) then
  begin
    // Uncheck all other rows
    for r := 1 to sgDetails.RowCount - 1 do
      sgDetails.Cells[0, r] := '0';

    // Check only the clicked one
    sgDetails.Cells[0, row] := '1';
    sgDetails.Invalidate;
  end;
  Calculate;
end;


// make first (fixed) row bold
procedure TForm1.sgDetailsPrepareCanvas(Sender: TObject; aCol, aRow: integer;
  aState: TGridDrawState);
var
  ts: TTextStyle;
begin
  if (aRow = 0) then
  begin
    sgDetails.Canvas.Font.Style := [fsBold];
    ts := sgDetails.Canvas.TextStyle;
    ts.Alignment := taCenter;
    sgDetails.Canvas.TextStyle := ts;
  end;
end;


procedure TForm1.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := False;
  sgDetails.Col := GotoCol;
  sgDetails.Row := GotoRow;
  sgDetails.EditorMode := True;
end;

// save the grid
procedure TForm1.SaveGrid;
var
  f: TextFile;
  r, c: integer;
  line: string;
begin
  AssignFile(f, GRID_FILE);
  Rewrite(f);
  for r := 1 to sgDetails.RowCount - 1 do
  begin
    line := '';
    for c := 0 to sgDetails.ColCount - 1 do
    begin
      if c > 0 then line += DELIM;
      line += Trim(sgDetails.Cells[c, r]);
    end;
    Writeln(f, line);
  end;
  CloseFile(f);
end;


//load the grid
procedure TForm1.LoadGrid;
var
  f: TextFile;
  line: string;
  parts: TStringList;
  r, c: integer;
begin
  if not FileExists(GRID_FILE) then Exit;

  parts := TStringList.Create;
  parts.StrictDelimiter := True;
  parts.Delimiter := DELIM;

  AssignFile(f, GRID_FILE);
  Reset(f);

  sgDetails.RowCount := 1;
  while not EOF(f) do
  begin
    ReadLn(f, line);
    parts.DelimitedText := line;

    sgDetails.RowCount := sgDetails.RowCount + 1;
    r := sgDetails.RowCount - 1;
    for c := 0 to Min(parts.Count - 1, sgDetails.ColCount - 1) do
      sgDetails.Cells[c, r] := parts[c];
  end;

  CloseFile(f);
  parts.Free;
end;


// sort the grid
procedure TForm1.SortGridByBrandAndModel;
var
  list: TStringList;
  r, oldRow, newRow, c: integer;
  key: string;
  temp: TStringGrid;
begin
  list := TStringList.Create;
  list.Sorted := False;

  // Build combined key list
  for r := 1 to sgDetails.RowCount - 1 do
  begin
    key := LowerCase(Trim(sgDetails.Cells[1, r])) + '|' +  // Brand
      LowerCase(Trim(sgDetails.Cells[2, r])) + '|' +  // Model
      IntToStr(r);                                    // Original row index
    list.Add(key);
  end;

  list.Sort;

  temp := TStringGrid.Create(nil);
  try
    temp.Assign(sgDetails);

    // Rearrange based on sorted list
    for r := 0 to list.Count - 1 do
    begin
      oldRow := StrToInt(Copy(list[r], RPos('|', list[r]) + 1, 999));
      newRow := r + 1;
      for c := 0 to sgDetails.ColCount - 1 do
        sgDetails.Cells[c, newRow] := temp.Cells[c, oldRow];
    end;
  finally
    temp.Free;
    list.Free;
  end;
end;


// resize the columns to fit contents
procedure TForm1.AutoSizeGridColumns(Grid: TStringGrid);
var
  c, r, w, maxWidth: integer;
begin
  for c := 0 to Grid.ColCount - 1 do
  begin
    maxWidth := 0;
    for r := 0 to Grid.RowCount - 1 do
    begin
      w := Grid.Canvas.TextWidth(Grid.Cells[c, r]);
      if w > maxWidth then
        maxWidth := w;
    end;
    // Add a little padding
    Grid.ColWidths[c] := maxWidth + 25;
  end;
  if Form1.Width < Grid.Width + 150 then
    Form1.Width := Grid.Width + 150;
end;


// Make the selected row visible at the top (or near top)
procedure TForm1.ScrollToSelectedRow;
var
  selRow: integer;
begin
  selRow := GetSelectedRow;
  if selRow > 0 then
  begin
    sgDetails.TopRow := selRow;
  end;
end;

function TForm1.GetSelectedRow: integer;
var
  r: integer;
begin
  Result := -1;
  for r := 1 to sgDetails.RowCount - 1 do
    if sgDetails.Cells[0, r] = '1' then
    begin
      Result := r;
      Exit;
    end;
end;


// calculate the angles based on the formula
// ArcTan( Layer height / pixel width)

procedure TForm1.Calculate;
var
  r: integer;
  xPixelWidth, yPixelWidth, LayerHeight, angleX, angleY: double;
  adjustedX, adjustedY: double;
begin
  for r := 1 to sgDetails.RowCount - 1 do
  begin
    if sgDetails.Cells[0, r] = '1' then
    begin
      xPixelWidth := StrToFloatDef(sgDetails.Cells[3, r], 0);
      yPixelWidth := StrToFloatDef(sgDetails.Cells[4, r], 0);
      LayerHeight := edtLayerHeight.Value;

      angleX := ArcTan(LayerHeight / xPixelWidth);
      angleY := ArcTan(LayerHeight / yPixelWidth);
      if Checkbox1.Checked then
      begin
        adjustedX := 90 - (angleX * 180 / Pi);
        adjustedY := 90 - (angleY * 180 / Pi);
      end
      else
      begin
        adjustedX := (angleX * 180 / Pi);
        adjustedY := (angleY * 180 / Pi);
      end;

      edtResultX.Text := FloatToStrF(adjustedX, ffFixed, 6, 2);
      edtResultY.Text := FloatToStrF(adjustedY, ffFixed, 6, 2);

      // create graphical representation of angles

      // draw the angle  for X
      Image1.Picture.Bitmap.SetSize(Image1.Width, Image1.Height);
      Image1.Canvas.Brush.Color := clbtnFace;
      Image1.Canvas.FillRect(Image1.ClientRect);

      // Draw angles

      DrawAngle(Image1.Picture.Bitmap.Canvas,
        Image1.Width,
        Image1.Height,
        adjustedX);
      Image1.Invalidate;
      //   draw the angle for Y
      Image2.Picture.Bitmap.SetSize(Image2.Width, Image2.Height);
      Image2.Canvas.Brush.Color := clbtnFace;
      Image2.Canvas.FillRect(Image2.ClientRect);

      // Draw angles
      DrawAngle(Image2.Picture.Bitmap.Canvas,
        Image2.Width,
        Image2.Height,
        adjustedY);
      Image2.Invalidate; // forces redraw on screen

      Exit; // only process the first checked row

    end;
  end;

  ShowMessage('Please check a row first.');

end;


procedure TForm1.GotoColRow(Col, Row: integer);
begin
  GotoCol := Col;
  GotoRow := Row;
  Timer1.Enabled := True;
end;


// draw the graphical representation of angle
procedure TForm1.DrawAngle(thisCanvas: TCanvas; ImgWidth, ImgHeight: integer;
  AngleDeg: double);
var
  Center: TPoint;
  Radius: integer;
  x1, y1, x2, y2: integer;
  EndAngleRad, LabelAngleRad: double;
  ArcRect: TRect;
  LabelX, LabelY: integer;
  LabelText: string;
begin
  // Start near bottom-left corner, with a small margin
  Center.X := 0;
  Center.Y := ImgHeight - 20;

  // Limit radius to fit within the image
  Radius := Min(ImgWidth - Center.X - 10, Center.Y - 10);
  if Radius < 10 then Radius := 10;

  // Clear and prepare
  thisCanvas.Pen.Width := 2;
  thisCanvas.Brush.Style := bsClear;
  thisCanvas.Pen.Color := clBlack;

  // Base line (along X-axis)
  x1 := Center.X + Radius;
  y1 := Center.Y;
  thisCanvas.MoveTo(Center.X, Center.Y);
  thisCanvas.LineTo(x1, y1);

  // Second line (at given angle, measured counter-clockwise)
  EndAngleRad := DegToRad(AngleDeg);
  x2 := Center.X + Round(Radius * Cos(EndAngleRad));
  y2 := Center.Y - Round(Radius * Sin(EndAngleRad));
  thisCanvas.MoveTo(Center.X, Center.Y);
  thisCanvas.LineTo(x2, y2);

  // Arc (half radius)
  ArcRect := Types.Rect(Center.X - Radius div 2, Center.Y - Radius div 2,
    Center.X + Radius div 2, Center.Y + Radius div 2);
  thisCanvas.Pen.Color := clRed;
  thisCanvas.Arc(ArcRect.Left, ArcRect.Top, ArcRect.Right, ArcRect.Bottom,
    Center.X + Radius div 2, Center.Y,
    Center.X + Round((Radius div 2) * Cos(EndAngleRad)),
    Center.Y - Round((Radius div 2) * Sin(EndAngleRad)));

  // Label
  LabelAngleRad := EndAngleRad / 2;
  LabelX := Center.X + Round((Radius div 2 + 35) * Cos(LabelAngleRad));
  LabelY := Center.Y - Round((Radius div 2 + 35) * Sin(LabelAngleRad));
  LabelText := Format('%.2f°', [AngleDeg]);

  thisCanvas.Font.Color := clNavy;
  thisCanvas.TextOut(LabelX - thisCanvas.TextWidth(LabelText) div 2,
    LabelY - thisCanvas.TextHeight(LabelText) div 2,
    LabelText);
end;


// extract the file version from theexecutable
function TForm1.GetFileVersionString(const AFileName, AKey: string): string;
var
  Size, TmpHandle: DWORD;
  Buffer: Pointer;
  Len: UINT;
  Value: PChar;
  Lang: array[0..3] of word;
  SubBlock: string;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(AFileName), TmpHandle);
  if Size > 0 then
  begin
    GetMem(Buffer, Size);
    try
      if GetFileVersionInfo(PChar(AFileName), TmpHandle, Size, Buffer) then
      begin
        // Get language + codepage
        if VerQueryValue(Buffer, '\VarFileInfo\Translation', Pointer(Value), Len) then
        begin
          Move(Value^, Lang, SizeOf(Lang));
          SubBlock := Format('\StringFileInfo\%0.4x%0.4x\%s',
            [Lang[0], Lang[1], AKey]);

          if VerQueryValue(Buffer, PChar(SubBlock), Pointer(Value), Len) then
            Result := Value;
        end;
      end;
    finally
      FreeMem(Buffer);
    end;
  end;
end;


end.
