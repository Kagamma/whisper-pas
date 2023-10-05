program whisper_cli;

uses
  SysUtils, Classes, whisper;

type
  TWaveHeader = packed record
    ChunkID: array [0..3] of Char;      // "RIFF" (Resource Interchange File Format)
    ChunkSize: LongWord;                // Total file size - 8 (file size - 8 bytes)
    Format: array [0..3] of Char;       // "WAVE" (Waveform Audio File Format)
    Subchunk1ID: array [0..3] of Char;  // "fmt " (Format subchunk)
    Subchunk1Size: LongWord;            // Size of the format subchunk (16 for PCM)
    AudioFormat: Word;                  // Audio format (1 for PCM)
    NumChannels: Word;                  // Number of channels (1 for mono, 2 for stereo, etc.)
    SampleRate: LongWord;               // Sample rate (e.g., 44100 for CD-quality audio)
    ByteRate: LongWord;                 // Byte rate (SampleRate * NumChannels * BitsPerSample / 8)
    BlockAlign: Word;                   // Block alignment (NumChannels * BitsPerSample / 8)
    BitsPerSample: Word;                // Bits per sample (e.g., 16 for 16-bit audio)
  end;

  TWaveChunk = packed record
    ID: array [0..3] of Char;
    Size: LongWord;
  end;

var
  ModelFName: String;
  InputFName: String;
  WaveHeader: TWaveHeader;
  WaveData: array of SmallInt;
  WaveDataFloat: array of Single;

procedure ReadWaveFile;
var
  FS: TFileStream;
  Chunk: TWaveChunk;
  I: Integer;
begin
  if not FileExists(InputFName) then
  begin
    Writeln('Input file not found!');
    Halt;
  end;
  FS := TFileStream.Create(InputFName, fmOpenRead);
  try
    FS.Read(WaveHeader, SizeOf(TWaveHeader));
    if (WaveHeader.ChunkID <> 'RIFF') or (WaveHeader.Format<> 'WAVE') then
    begin
      Writeln('Input file is not a WAVE file!');
      Halt;
    end;
    if (WaveHeader.BitsPerSample <> 16) then
    begin
      Writeln('BitsPerSample must be 16!');
      Halt;
    end;
    while FS.Position < FS.Size - 1 do
    begin
      FS.Read(Chunk, SizeOf(TWaveChunk));
      if Chunk.ID = 'data' then
      begin
        SetLength(WaveData, Chunk.Size div (WaveHeader.BitsPerSample div 8));
        SetLength(WaveDataFloat, Length(WaveData));
        FS.Read(WaveData[0], Chunk.Size);
        for I := 0 to Length(WaveData) - 1 do
          WaveDataFloat[I] := WaveData[I] / (2 shl WaveHeader.BitsPerSample);
        Break;
      end else
      begin
        FS.Position := FS.Position + Chunk.Size;
      end;
    end;
  finally
    FS.Free;
  end;
end;

procedure Inference;
var
  Params: Twhisper_full_params;
  Ctx: Pwhisper_context;
  I, NumSegments: Integer;
  Str: PChar;
begin
  Ctx := whisper_init_from_file(PChar(ModelFName));
  if Ctx = nil then
  begin
    Writeln('Failed to initialize whisper context');
    Halt;
  end;
  Params := whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  Params.n_threads := 4;
  Params.strategy := WHISPER_SAMPLING_GREEDY;
  Params.print_realtime := false;
  Params.print_progress := false;
  if whisper_full_parallel(Ctx, params, @WaveDataFloat[0], Length(WaveDataFloat), 1) <> 0 then
  begin
    Writeln('Failed to process audio');
    Halt;
  end;
  NumSegments := whisper_full_n_segments(Ctx);
  for I := 0 to NumSegments - 1 do
  begin
    Str := whisper_full_get_segment_text(Ctx, I);
    Writeln(Str);
  end;
  whisper_print_timings(Ctx);
  whisper_free(Ctx);
end;

procedure ParseParameters;
var
  I: Integer;

  procedure Increase;
  begin
    Inc(I);
    if I > ParamCount then
      raise Exception.Create('Invalid parameter');
  end;

begin
  if ParamCount = 0 then
  begin
    Writeln('Usage: whisper-cli -m <model> -i <input wav file>');
    Halt;
  end;
  I := 1;
  while I <= ParamCount do
  begin
    case ParamStr(I) of
      '-m':
        begin
          Increase;
          ModelFName := ParamStr(I);
        end;
      '-i':
        begin
          Increase;
          InputFName := ParamStr(I);
        end;
    end;
    Inc(I);
  end;
end;

begin
  ParseParameters;
  ReadWaveFile;
  Inference;
end.

