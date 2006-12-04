{
  $Id$
  Vampyre Imaging Library
  by Marek Mauder
  http://imaginglib.sourceforge.net

  The contents of this file are used with permission, subject to the Mozilla
  Public License Version 1.1 (the "License"); you may not use this file except
  in compliance with the License. You may obtain a copy of the License at
  http://www.mozilla.org/MPL/MPL-1.1.html

  Software distributed under the License is distributed on an "AS IS" basis,
  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
  the specific language governing rights and limitations under the License.

  Alternatively, the contents of this file may be used under the terms of the
  GNU Lesser General Public License (the  "LGPL License"), in which case the
  provisions of the LGPL License are applicable instead of those above.
  If you wish to allow use of your version of this file only under the terms
  of the LGPL License and not to allow others to use your version of this file
  under the MPL, indicate your decision by deleting  the provisions above and
  replace  them with the notice and other provisions required by the LGPL
  License.  If you do not delete the provisions above, a recipient may use
  your version of this file under either the MPL or the LGPL License.

  For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html
}

{ This unit contains image format loader/saver for DirectDraw Surface images.}
unit ImagingDds;

{$I ImagingOptions.inc}

interface

uses
  ImagingTypes, Imaging, ImagingUtility, ImagingFormats;

type
  { Class for loading and saving Microsoft DirectDraw surfaces.
    It can load/save all D3D formats which have coresponding
    TImageFormat. It supports plain textures, cube textures and
    volume textures, all of these can have mipmaps. It can also
    load some formats which have no exact TImageFormat, but can be easily
    converted to one.
    You can get some information about last loaded DDS file by calling
    GetOption with ImagingDDSXXX options and you can set some
    saving options by calling SetOption.}
  TDDSFileFormat = class(TImageFileFormat)
  protected
    FLoadedCubeMap: LongBool;
    FLoadedVolume: LongBool;
    FLoadedMipMapCount: LongInt;
    FLoadedDepth: LongInt;
    FSaveCubeMap: LongBool;
    FSaveVolume: LongBool;
    FSaveMipMapCount: LongInt;
    FSaveDepth: LongInt;
    function GetSupportedFormats: TImageFormats; override;
    function LoadData(Handle: TImagingHandle; var Images: TDynImageDataArray;
      OnlyFirstLevel: Boolean): Boolean; override;
    function SaveData(Handle: TImagingHandle; const Images: TDynImageDataArray;
      Index: LongInt): Boolean; override;
    function MakeCompatible(const Image: TImageData; var Comp: TImageData;
      out MustBeFreed: Boolean): Boolean; override;
  public
    constructor Create; override;
    function TestFormat(Handle: TImagingHandle): Boolean; override;
  end;

const
  SDDSFormatName = 'DirectDraw Surface';
  SDDSMasks      = '*.dds';
  DDSSupportedFormats: TImageFormats = [ifR8G8B8, ifA8R8G8B8, ifA1R5G5B5,
    ifA4R4G4B4, ifX1R5G5B5, ifX4R4G4B4, ifR5G6B5, ifA16B16G16R16, ifR32F,
    ifA32B32G32R32F, ifR16F, ifA16B16G16R16F, ifR3G3B2, ifGray8, ifA8Gray8,
    ifGray16, ifDXT1, ifDXT3, ifDXT5];

implementation

const
  { Four character codes.}
  DDSMagic    = LongWord(Byte('D') or (Byte('D') shl 8) or (Byte('S') shl 16) or
    (Byte(' ') shl 24));
  FOURCC_DXT1 = LongWord(Byte('D') or (Byte('X') shl 8) or (Byte('T') shl 16) or
    (Byte('1') shl 24));
  FOURCC_DXT3 = LongWord(Byte('D') or (Byte('X') shl 8) or (Byte('T') shl 16) or
    (Byte('3') shl 24));
  FOURCC_DXT5 = LongWord(Byte('D') or (Byte('X') shl 8) or (Byte('T') shl 16) or
    (Byte('5') shl 24));

  { Some D3DFORMAT values used in DDS files as FourCC value.}
  D3DFMT_A16B16G16R16  = 36;
  D3DFMT_R32F          = 114;
  D3DFMT_A32B32G32R32F = 116;
  D3DFMT_R16F          = 111;
  D3DFMT_A16B16G16R16F = 113;

  { Constans used by TDDSurfaceDesc2.Flags.}
  DDSD_CAPS            = $00000001;
  DDSD_HEIGHT          = $00000002;
  DDSD_WIDTH           = $00000004;
  DDSD_PITCH           = $00000008;
  DDSD_PIXELFORMAT     = $00001000;
  DDSD_MIPMAPCOUNT     = $00020000;
  DDSD_LINEARSIZE      = $00080000;
  DDSD_DEPTH           = $00800000;

  { Constans used by TDDSPixelFormat.Flags.}
  DDPF_ALPHAPIXELS     = $00000001;    // used by formats which contain alpha
  DDPF_FOURCC          = $00000004;    // used by DXT and large ARGB formats
  DDPF_RGB             = $00000040;    // used by RGB formats
  DDPF_LUMINANCE       = $00020000;    // used by formats like D3DFMT_L16
  DDPF_BUMPLUMINANCE   = $00040000;    // used by mixed signed-unsigned formats
  DDPF_BUMPDUDV        = $00080000;    // used by signed formats

  { Constans used by TDDSCaps.Caps1.}
  DDSCAPS_COMPLEX      = $00000008;
  DDSCAPS_TEXTURE      = $00001000;
  DDSCAPS_MIPMAP       = $00400000;

  { Constans used by TDDSCaps.Caps2.}
  DDSCAPS2_CUBEMAP     = $00000200;
  DDSCAPS2_POSITIVEX   = $00000400;
  DDSCAPS2_NEGATIVEX   = $00000800;
  DDSCAPS2_POSITIVEY   = $00001000;
  DDSCAPS2_NEGATIVEY   = $00002000;
  DDSCAPS2_POSITIVEZ   = $00004000;
  DDSCAPS2_NEGATIVEZ   = $00008000;
  DDSCAPS2_VOLUME      = $00200000;

  { Minimal set of flags required to be in TDDSurfaceDesc2.Flags.}
  DDS_REQUIRED_FLAGS = DDSD_CAPS or DDSD_PIXELFORMAT or DDSD_WIDTH or
    DDSD_HEIGHT;

  { Flags for TDDSurfaceDesc2.Flags used when saving DDS file.}
  DDS_SAVE_FLAGS = DDS_REQUIRED_FLAGS or DDSD_LINEARSIZE;

type
  { Stores the pixel format information.}
  TDDPixelFormat = packed record
    Size: LongWord;       // Size of the structure = 32 bytes
    Flags: LongWord;      // Flags to indicate valid fields
    FourCC: LongWord;     // Four-char code for compressed textures (DXT)
    BitCount: LongWord;   // Bits per pixel if uncomp. usually 16,24 or 32
    RedMask: LongWord;    // Bit mask for the Red component
    GreenMask: LongWord;  // Bit mask for the Green component
    BlueMask: LongWord;   // Bit mask for the Blue component
    AlphaMask: LongWord;  // Bit mask for the Alpha component
  end;

  { Specifies capabilities of surface.}
  TDDSCaps = packed record
    Caps1: LongWord;      // Should always include DDSCAPS_TEXTURE
    Caps2: LongWord;      // For cubic environment maps
    Reserved: array[0..1] of LongWord; // Reserved
  end;

  { Record describing DDS file contents.}
  TDDSurfaceDesc2 = packed record
    Size: LongWord;       // Size of the structure = 124 Bytes
    Flags: LongWord;      // Flags to indicate valid fields
    Height: LongWord;     // Height of the main image in pixels
    Width: LongWord;      // Width of the main image in pixels
    PitchOrLinearSize: LongWord; // For uncomp formats number of bytes per
                          // scanline. For comp it is the size in
                          // bytes of the main image
    Depth: LongWord;      // Only for volume text depth of the volume
    MipMaps: LongInt;     // Total number of levels in the mipmap chain
    Reserved1: array[0..10] of LongWord; // Reserved
    PixelFormat: TDDPixelFormat; // Format of the pixel data
    Caps: TDDSCaps;       // Capabilities
    Reserved2: LongWord;  // Reserved
  end;

  { DDS file header.}
  TDDSFileHeader = packed record
    Magic: LongWord;       // File format magic
    Desc: TDDSurfaceDesc2; // Surface description
  end;

function GetVolumeLevelCount(Depth, MipMaps: LongInt): LongInt;
var
    I: LongInt;
begin
    Result := Depth;
    for I := 1 to MipMaps - 1 do
      Inc(Result, ClampInt(Depth shr I, 1, Depth));
end;


{ TDDSFileFormat class implementation }

constructor TDDSFileFormat.Create;
begin
  inherited Create;
  FName := SDDSFormatName;
  FCanLoad := True;
  FCanSave := True;
  FIsMultiImageFormat := True;
  FSaveCubeMap := False;
  FSaveVolume := False ;
  FSaveMipMapCount := 1;
  FSaveDepth := 1;

  AddMasks(SDDSMasks);
  RegisterOption(ImagingDDSLoadedCubeMap, @FLoadedCubeMap);
  RegisterOption(ImagingDDSLoadedVolume, @FLoadedVolume);
  RegisterOption(ImagingDDSLoadedMipMapCount, @FLoadedMipMapCount);
  RegisterOption(ImagingDDSLoadedDepth, @FLoadedDepth);
  RegisterOption(ImagingDDSSaveCubeMap, @FSaveCubeMap);
  RegisterOption(ImagingDDSSaveVolume, @FSaveVolume);
  RegisterOption(ImagingDDSSaveMipMapCount, @FSaveMipMapCount);
  RegisterOption(ImagingDDSSaveDepth, @FSaveDepth);
end;

function TDDSFileFormat.GetSupportedFormats: TImageFormats;
begin
  Result := DDSSupportedFormats;
end;

function TDDSFileFormat.LoadData(Handle: TImagingHandle;
  var Images: TDynImageDataArray; OnlyFirstLevel: Boolean): Boolean;
var
  Hdr: TDDSFileHeader;
  SrcFormat: TImageFormat;
  FmtInfo: PImageFormatInfo;
  NeedsSwapChannels, HasMipMaps: Boolean;
  CurWidth, CurHeight, ImageCount, LoadSize, I, PitchOrLinear: LongInt;
  Data: PByte;
  UseAsPitch: Boolean;
  UseAsLinear: Boolean;

  function MasksEqual(const DDPF: TDDPixelFormat; PF: PPixelFormatInfo): Boolean;
  begin
    Result := (DDPF.AlphaMask = PF.ABitMask) and
      (DDPF.RedMask = PF.RBitMask) and (DDPF.GreenMask = PF.GBitMask) and
      (DDPF.BlueMask = PF.BBitMask);
  end;

  procedure ComputeSubDimensions(Idx: LongInt; var CurWidth,
    CurHeight: LongInt);
  var
    I, Last, Shift: LongInt;
  begin
    CurWidth := Hdr.Desc.Width;
    CurHeight := Hdr.Desc.Height;
    if HasMipMaps then
    begin
      if not FLoadedVolume then
      begin
        // Cube maps are stored like this
        // Face 0 mimap 0
        // Face 0 mipmap 1
        // ...
        // Face 1 mipmap 0
        // Face 1 mipmap 1
        // ...
        if FLoadedCubeMap then
          Idx := Idx - ((Idx div Hdr.Desc.MipMaps) * Hdr.Desc.MipMaps);
        for I := 0 to Idx - 1 do
        begin
          CurWidth := ClampInt(CurWidth shr 1, 1, CurWidth);
          CurHeight := ClampInt(CurHeight shr 1, 1, CurHeight);
        end;
      end
      else
      begin
        // Volume textures are stored in DDS files like this:
        // Slice 0 mipmap 0
        // Slice 1 mipmap 0
        // Slice 2 mipmap 0
        // Slice 3 mipmap 0
        // Slice 0 mipmap 1
        // Slice 1 mipmap 1
        // Slice 0 mipmap 2
        // Slice 0 mipmap 3 ...
        Shift := 0;
        Last := Hdr.Desc.Depth;
        while Idx > Last - 1 do
        begin
          CurWidth := ClampInt(CurWidth shr 1, 1, CurWidth);
          CurHeight := ClampInt(CurHeight shr 1, 1, CurHeight);
          if (CurWidth = 1) and (CurHeight = 1) then
            Break;
          Inc(Shift);
          Inc(Last, ClampInt(Hdr.Desc.Depth shr Shift, 1, Hdr.Desc.Depth));
        end;
      end;
    end;
  end;

begin
  Result := False;
  Data := nil;
  with GetIO, Hdr, Hdr.Desc.PixelFormat do
  begin
    Read(Handle, @Hdr, SizeOF(Hdr));
    {
    // set position to the end of the header (for possible future versions
    // with larger header)
    Seek(Handle, Hdr.Desc.Size + SizeOf(Hdr.Magic) - SizeOf(Hdr),
      smFromCurrent);
    }
    SrcFormat := ifUnknown;
    NeedsSwapChannels := False;
    // get image data format
    if (Flags and DDPF_FOURCC) = DDPF_FOURCC then
      // handle FourCC and large ARGB formats
      case FourCC of
        D3DFMT_A16B16G16R16: SrcFormat := ifA16B16G16R16;
        D3DFMT_R32F: SrcFormat := ifR32F;
        D3DFMT_A32B32G32R32F: SrcFormat := ifA32B32G32R32F;
        D3DFMT_R16F: SrcFormat := ifR16F;
        D3DFMT_A16B16G16R16F: SrcFormat := ifA16B16G16R16F;
        FOURCC_DXT1: SrcFormat := ifDXT1;
        FOURCC_DXT3: SrcFormat := ifDXT3;
        FOURCC_DXT5: SrcFormat := ifDXT5;
      end
    else
      if (Flags and DDPF_RGB) = DDPF_RGB then
      begin
        // handle RGB formats
        if (Flags and DDPF_ALPHAPIXELS) = DDPF_ALPHAPIXELS then
          // handle RGB with alpha formats
          case BitCount of
            16:
              begin
                if MasksEqual(Desc.PixelFormat,
                  GetFormatInfo(ifA4R4G4B4).PixelFormat) then
                  SrcFormat := ifA4R4G4B4;
                if MasksEqual(Desc.PixelFormat,
                  GetFormatInfo(ifA1R5G5B5).PixelFormat) then
                  SrcFormat := ifA1R5G5B5;
              end;
            32:
              begin
                SrcFormat := ifA8R8G8B8;
                if BlueMask = $00FF0000 then
                  NeedsSwapChannels := True;
              end;
          end
        else
          // handle RGB without alpha formats
          case BitCount of
            8:
              if MasksEqual(Desc.PixelFormat,
                GetFormatInfo(ifR3G3B2).PixelFormat) then
                SrcFormat := ifR3G3B2;
            16:
              begin
                if MasksEqual(Desc.PixelFormat,
                  GetFormatInfo(ifX4R4G4B4).PixelFormat) then
                  SrcFormat := ifX4R4G4B4;
                if MasksEqual(Desc.PixelFormat,
                  GetFormatInfo(ifX1R5G5B5).PixelFormat) then
                  SrcFormat := ifX1R5G5B5;
                if MasksEqual(Desc.PixelFormat,
                  GetFormatInfo(ifR5G6B5).PixelFormat) then
                  SrcFormat := ifR5G6B5;
              end;
            24: SrcFormat := ifR8G8B8;
            32:
              begin
                SrcFormat := ifX8R8G8B8;
                if BlueMask = $00FF0000 then
                  NeedsSwapChannels := True;
              end;
          end;
      end
      else
        if (Flags and DDPF_LUMINANCE) = DDPF_LUMINANCE then
        begin
          // handle luminance formats
          if (Flags and DDPF_ALPHAPIXELS) = DDPF_ALPHAPIXELS then
          begin
            // handle luminance with alpha formats
            if BitCount = 16 then
              SrcFormat := ifA8Gray8;
          end
          else
            // handle luminance without alpha formats
            case BitCount of
              8: SrcFormat := ifGray8;
              16: SrcFormat := ifGray16;
            end;
        end
        else
          if (Flags and DDPF_BUMPLUMINANCE) = DDPF_BUMPLUMINANCE then
          begin
            // handle mixed bump-luminance formats like D3DFMT_X8L8V8U8
            case BitCount of
              32:
                if BlueMask = $00FF0000 then
                begin
                  SrcFormat := ifX8R8G8B8; // D3DFMT_X8L8V8U8
                  NeedsSwapChannels := True;
                end;
            end;
          end
          else
            if (Flags and DDPF_BUMPDUDV) = DDPF_BUMPDUDV then
            begin
              // handle bumpmap formats like D3DFMT_Q8W8V8U8
              case BitCount of
                16: SrcFormat := ifA8Gray8; // D3DFMT_V8U8
                32:
                  if AlphaMask = $FF000000 then
                  begin
                    SrcFormat := ifA8R8G8B8; // D3DFMT_Q8W8V8U8
                    NeedsSwapChannels := True;
                  end;
                64: SrcFormat := ifA16B16G16R16; // D3DFMT_Q16W16V16U16
              end;
            end;

    // determine number of subimages in file and type of texture stored
    ImageCount := 1;
    HasMipMaps := False;
    FLoadedMipMapCount := 1;
    FLoadedDepth := 1;
    FLoadedVolume := False;
    FLoadedCubeMap := False;

    // if DDS format is not supported we will exit
    if SrcFormat = ifUnknown then
      Exit;

    // file contains mipmaps for each subimage
    if ((Desc.Caps.Caps1 and DDSCAPS_MIPMAP) = DDSCAPS_MIPMAP) and
      ((Desc.Flags and DDSD_MIPMAPCOUNT) = DDSD_MIPMAPCOUNT) then
    begin
      HasMipMaps := True;
      FLoadedMipMapCount := Desc.MipMaps;
      ImageCount := Desc.MipMaps;
    end;

    // file stores volume texture
    if ((Desc.Caps.Caps2 and DDSCAPS2_VOLUME) = DDSCAPS2_VOLUME) and
      ((Desc.Flags and DDSD_DEPTH) = DDSD_DEPTH) then
    begin
      FLoadedVolume := True;
      FLoadedDepth := Desc.Depth;
      ImageCount := GetVolumeLevelCount(Desc.Depth, ImageCount);
    end;

    // file stores cube texture
    if (Desc.Caps.Caps2 and DDSCAPS2_CUBEMAP) = DDSCAPS2_CUBEMAP then
    begin
      FLoadedCubeMap := True;
      I := 0;
      if (Desc.Caps.Caps2 and DDSCAPS2_POSITIVEX) = DDSCAPS2_POSITIVEX then Inc(I);
      if (Desc.Caps.Caps2 and DDSCAPS2_POSITIVEY) = DDSCAPS2_POSITIVEY then Inc(I);
      if (Desc.Caps.Caps2 and DDSCAPS2_POSITIVEZ) = DDSCAPS2_POSITIVEZ then Inc(I);
      if (Desc.Caps.Caps2 and DDSCAPS2_NEGATIVEX) = DDSCAPS2_NEGATIVEX then Inc(I);
      if (Desc.Caps.Caps2 and DDSCAPS2_NEGATIVEY) = DDSCAPS2_NEGATIVEY then Inc(I);
      if (Desc.Caps.Caps2 and DDSCAPS2_NEGATIVEZ) = DDSCAPS2_NEGATIVEZ then Inc(I);
      FLoadedDepth := I;
      ImageCount := ImageCount * I;
    end;

    // allocate and load all images in file
    FmtInfo := GetFormatInfo(SrcFormat);
    {  whole image muse be read from input stream to support more images in one stream
    if OnlyFirstLevel then
      ImageCount := 1;
    }
    SetLength(Images, ImageCount);

    for I := 0 to ImageCount - 1 do
    begin
      // compute dimensions of surrent subimage based on texture type and
      // number of mipmaps
      ComputeSubDimensions(I, CurWidth, CurHeight);
      NewImage(CurWidth, CurHeight, SrcFormat, Images[I]);

      // compute the pitch or get if from file if present
      UseAsPitch := (Desc.Flags and DDSD_PITCH) = DDSD_PITCH;
      UseAsLinear := (Desc.Flags and DDSD_LINEARSIZE) = DDSD_LINEARSIZE;
      if (I = 0) and (UseAsPitch or UseAsLinear) then
        PitchOrLinear := Desc.PitchOrLinearSize
      else
        PitchOrLinear := FmtInfo.GetPixelsSize(SrcFormat, CurWidth, CurHeight);

      if UseAsPitch then
        LoadSize := CurHeight * PitchOrLinear
      else
        LoadSize := PitchOrLinear;

      if not UseAsPitch then
      begin
        // If DDS does not use Pitch we can simply copy data
        Read(Handle, Images[I].Bits, LoadSize)
      end
      else
      try
        // If DDS uses Pitch we must load aligned scanlines
        // and then remove padding
        GetMem(Data, LoadSize);
        Read(Handle, Data, LoadSize);
        RemovePadBytes(Data, Images[I].Bits, CurWidth, CurHeight,
          FmtInfo.BytesPerPixel, PitchOrLinear);
      finally
        FreeMem(Data);
      end;

      if NeedsSwapChannels then
        SwapChannels(Images[I], ChannelRed, ChannelBlue);

      Result := True;
    end;
  end;
end;

function TDDSFileFormat.SaveData(Handle: TImagingHandle;
  const Images: TDynImageDataArray; Index: LongInt): Boolean;
var
  Hdr: TDDSFileHeader;
  MainImage, ImageToSave: TImageData;
  I, MainIdx, Len, ImageCount: LongInt;
  J: LongWord;
  FmtInfo: PImageFormatInfo;
  MustBeFreed: Boolean;
begin
  Result := False;
  MainIdx := FFirstIdx;
  Len := Length(Images);

  // check if we have enough images on Input to save cube map
  if FSaveCubeMap then
  begin
    FSaveVolume := False;
    if Len - MainIdx < FSaveDepth *  FSaveMipMapCount then
      FSaveCubeMap := False;
  end;
  // check if we have enough images on Input to save volume texture
  if FSaveVolume then
  begin
    FSaveCubeMap := False;
    if Len - MainIdx < GetVolumeLevelCount(FSaveDepth, FSaveMipMapCount) then
      FSaveVolume := False;
  end;
  // check if we have enough images on Input to save mip maps
  if (FSaveMipMapCount > 1)  then
  begin
    if Len - MainIdx < FSaveMipMapCount then
      FSaveMipMapCount := 1;
  end;

  // we create compatible main image and fill headers
  if MakeCompatible(Images[MainIdx], MainImage, MustBeFreed) then
  with GetIO, MainImage, Hdr do
  try
    FmtInfo := GetFormatInfo(Format);
    FillChar(Hdr, Sizeof(Hdr), 0);
    Magic := DDSMagic;
    Desc.Size := SizeOf(Desc);
    Desc.Width := Width;
    Desc.Height := Height;
    Desc.Flags := DDS_SAVE_FLAGS;
    Desc.Caps.Caps1 := DDSCAPS_TEXTURE;
    Desc.PixelFormat.Size := SizeOf(Desc.PixelFormat);
    Desc.PitchOrLinearSize := MainImage.Size;
    ImageCount := FSaveMipMapCount;

    if FSaveMipMapCount > 1 then
    begin
      Desc.Flags := Desc.Flags or DDSD_MIPMAPCOUNT;
      Desc.Caps.Caps1 := Desc.Caps.Caps1 or DDSCAPS_MIPMAP;
      Desc.MipMaps := FSaveMipMapCount;
    end;
    if FSaveCubeMap then
    begin
      Desc.Caps.Caps1 := Desc.Caps.Caps1 or DDSCAPS_COMPLEX;
      Desc.Caps.Caps2 := Desc.Caps.Caps2 or DDSCAPS2_CUBEMAP;
      J := DDSCAPS2_POSITIVEX;
      for I := 0 to FSaveDepth - 1 do
      begin
        Desc.Caps.Caps2 := Desc.Caps.Caps2 or J;
        J := J shl 1;
      end;
      ImageCount := FSaveDepth * FSaveMipMapCount;
    end;
    if FSaveVolume then
    begin
      Desc.Flags := Desc.Flags or DDSD_DEPTH;
      Desc.Caps.Caps1 := Desc.Caps.Caps1 or DDSCAPS_COMPLEX;
      Desc.Caps.Caps2 := Desc.Caps.Caps2 or DDSCAPS2_VOLUME;
      Desc.Depth := FSaveDepth;
      ImageCount := GetVolumeLevelCount(FSaveDepth, FSaveMipMapCount);
    end;
    // now we set DDS pixel format for main image
    if FmtInfo.IsSpecial or FmtInfo.IsFloatingPoint or
      (FmtInfo.BytesPerPixel > 4) then
    begin
      Desc.PixelFormat.Flags := DDPF_FOURCC;
      case Format of
        ifA16B16G16R16: Desc.PixelFormat.FourCC := D3DFMT_A16B16G16R16;
        ifR32F: Desc.PixelFormat.FourCC := D3DFMT_R32F;
        ifA32B32G32R32F: Desc.PixelFormat.FourCC := D3DFMT_A32B32G32R32F;
        ifR16F: Desc.PixelFormat.FourCC := D3DFMT_R16F;
        ifA16B16G16R16F: Desc.PixelFormat.FourCC := D3DFMT_A16B16G16R16F;
        ifDXT1: Desc.PixelFormat.FourCC := FOURCC_DXT1;
        ifDXT3: Desc.PixelFormat.FourCC := FOURCC_DXT3;
        ifDXT5: Desc.PixelFormat.FourCC := FOURCC_DXT5;
      end;
    end
    else
      if FmtInfo.HasGrayChannel then
      begin
        Desc.PixelFormat.Flags := DDPF_LUMINANCE;
        Desc.PixelFormat.BitCount := FmtInfo.BytesPerPixel * 8;
        case Format of
          ifGray8: Desc.PixelFormat.RedMask := 255;
          ifGray16: Desc.PixelFormat.RedMask := 65535;
          ifA8Gray8:
            begin
              Desc.PixelFormat.Flags := Desc.PixelFormat.Flags or
                DDPF_ALPHAPIXELS;
              Desc.PixelFormat.RedMask := 255;
              Desc.PixelFormat.AlphaMask := 65280;
            end;
        end;
      end
      else
        begin
          Desc.PixelFormat.Flags := DDPF_RGB;
          Desc.PixelFormat.BitCount := FmtInfo.BytesPerPixel * 8;
          if FmtInfo.HasAlphaChannel then
          begin
            Desc.PixelFormat.Flags := Desc.PixelFormat.Flags or
                DDPF_ALPHAPIXELS;
            Desc.PixelFormat.AlphaMask := $FF000000;
          end;
          if FmtInfo.BytesPerPixel > 2 then
          begin
            Desc.PixelFormat.RedMask := $00FF0000;
            Desc.PixelFormat.GreenMask := $0000FF00;
            Desc.PixelFormat.BlueMask := $000000FF;
          end
          else
          begin
            Desc.PixelFormat.AlphaMask := FmtInfo.PixelFormat.ABitMask;
            Desc.PixelFormat.RedMask := FmtInfo.PixelFormat.RBitMask;
            Desc.PixelFormat.GreenMask := FmtInfo.PixelFormat.GBitMask;
            Desc.PixelFormat.BlueMask := FmtInfo.PixelFormat.BBitMask;
          end;
        end;
    // header and main image are written to output
    Write(Handle, @Hdr, SizeOf(Hdr));
    Write(Handle, MainImage.Bits, MainImage.Size);
    // write the rest of the images (and convert them to
    // the same format as main image if necessary)
    for I := MainIdx + 1 to MainIdx + ImageCount - 1 do
    begin
      if Images[I].Format <> Format then
      begin
        CloneImage(Images[I], ImageToSave);
        ConvertImage(ImageToSave, Format);
      end
      else
        ImageToSave := Images[I];
      Write(Handle, ImageToSave.Bits, ImageToSave.Size);
      if Images[I].Bits <> ImageToSave.Bits then
        FreeImage(ImageToSave);
    end;

    Result := True;
  finally
    if MustBeFreed then
      FreeImage(MainImage);
  end;
end;

function TDDSFileFormat.MakeCompatible(const Image: TImageData;
  var Comp: TImageData; out MustBeFreed: Boolean): Boolean;
var
  Info: PImageFormatInfo;
  ConvFormat: TImageFormat;
begin
  if not inherited MakeCompatible(Image, Comp, MustBeFreed) then
  begin
    Info := GetFormatInfo(Comp.Format);
    if Info.IsIndexed or Info.IsSpecial then
      // convert indexed and unsupported special formatd to A8R8G8B8
      ConvFormat := ifA8R8G8B8
    else if Info.IsFloatingPoint then
    begin
      if Info.Format = ifA16R16G16B16F then
        // only swap channels here
        ConvFormat := ifA16B16G16R16F
      else
        // convert other floating point formats to A32B32G32R32F
        ConvFormat := ifA32B32G32R32F
    end
    else if Info.HasGrayChannel then
    begin
      if Info.HasAlphaChannel then
        // convert grayscale with alpha to A8Gray8
        ConvFormat := ifA8Gray8
      else if Info.BytesPerPixel = 1 then
        // convert 8bit grayscale to Gray8
        ConvFormat := ifGray8
      else
        // convert 16-64bit grayscales to Gray16
        ConvFormat := ifGray16;
    end
    else if Info.BytesPerPixel > 4 then
      ConvFormat := ifA16B16G16R16
    else if Info.HasAlphaChannel then
      // convert the other images with alpha channel to A8R8G8B8
      ConvFormat := ifA8R8G8B8
    else
      // convert the other formats to X8R8G8B8
      ConvFormat := ifX8R8G8B8;

    ConvertImage(Comp, ConvFormat);
  end;
  Result := Comp.Format in GetSupportedFormats;
end;

function TDDSFileFormat.TestFormat(Handle: TImagingHandle): Boolean;
var
  Hdr: TDDSFileHeader;
  ReadCount: LongInt;
begin
  Result := False;
  if Handle <> nil then
    with GetIO do
    begin
      ReadCount := Read(Handle, @Hdr, SizeOf(Hdr));
      Seek(Handle, -ReadCount, smFromCurrent);
      Result := (Hdr.Magic = DDSMagic) and (ReadCount = SizeOf(Hdr)) and
        ((DDS_REQUIRED_FLAGS and Hdr.Desc.Flags) = DDS_REQUIRED_FLAGS) and
        ((Hdr.Desc.Caps.Caps1 and DDSCAPS_TEXTURE) = DDSCAPS_TEXTURE);
    end;
end;

initialization
  RegisterImageFileFormat(TDDSFileFormat);

{
  File Notes:

  -- TODOS ----------------------------------------------------
    - when saving multi image to DDS make sure all levels are
      saved and with proper dims and format
    - always store more images if they are on input, not only when
      SaveMipMapCount is set (problem in VampConvert)  

  -- 0.21 Changes/Bug Fixes -----------------------------------
    - Fixed bug that sometimes saved non-standard DDS files and another
      one that caused crash when these files were loaded.
    - Changed extensions to filename masks.
    - Changed SaveData, LoadData, and MakeCompatible methods according
      to changes in base class in Imaging unit.

  -- 0.19 Changes/Bug Fixes -----------------------------------
    - added support for half-float image formats
    - change in LoadData to allow support for more images
      in one stream loading

  -- 0.17 Changes/Bug Fixes -----------------------------------
    - fixed bug in TestFormat which does not recognize many DDS files
    - changed pitch/linearsize handling in DDS loading code to
      load DDS files produced by NVidia's Photoshop plugin
}

end.

