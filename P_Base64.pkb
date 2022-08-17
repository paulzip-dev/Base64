create or replace package body P_Base64 is

/*
MAX_ENC_CHUNK_LEN : An input chunk size of 23760 bytes converts to 32668 Base64,
23760 is modulo divisible by 48 and 3 (with no remainder) which means
content will be full lines including CRLF endings, as it doesn't exceed 32767
it also allows space for us to add a concatenating CRLF between chunks

MAX_DEC_CHUNK_LEN : When decoding a Base64 encoded source, it helps to have a
chunking length that is modulo divisible (with no remainder) for each of :
   4 - as encoding is 4 * 6 bit bytes chunks,
  64 - as a terminating line is 64 bytes and without CRLF
  66 - as a non terminating line is 64 bytes + CRLF
To facilitate nice chunking boundaries.  Also this length has to be less than
32k to avoid ORA-06502 in dbms_lob.writeappend, on some Oracle versions
*/

MAX_ENC_CHUNK_LEN constant pls_integer := 23760; -- Don't change!!
MAX_DEC_CHUNK_LEN constant pls_integer := 31680; -- Don't change!!
CRLF varchar2(2) := chr(13) || chr(10);
WHITESPACE varchar2(6) := ' ' || CRLF || chr(9) || chr(11) || chr(12); -- Whitespace : 32 (Space), 13 (Carriage Return), 10 (Line Feed), 9 (Horizontal Tab), 11 (Vertical Tab), 12 (Form Feed)

--------------------------------------------------------------------------------
-- Miscellaneous helper routines
-- Many of these helper routines are generic, and defined in isloation, so could
-- be moved to another library package if required

function RemoveWhitespace(pIP varchar2) return varchar2 is
-- Returns a string with all whitespace removed
begin
  return translate(pIP, 'a' || WHITESPACE, 'a');
end;

function FileLength(pOraDir varchar2, pFilename varchar2) return pls_integer is
-- Returns the length of a file in bytes
  vExists     boolean;
  vFileLength number;
  vBlocksize  binary_integer;
begin
  utl_file.fgetattr(pOraDir, pFilename, vExists, vFileLength, vBlocksize);
  return vFileLength;
end;

function BFileLength(pBFile BFile) return pls_integer is
-- Returns the length of a file located by a BFile in bytes
  vOraDir varchar2(4000 byte);
  vFilename varchar2(4000 byte);
begin
  dbms_lob.filegetname(pBFile, vOraDir, vFilename);
  return FileLength(vOraDir, vFilename);
end;

function ClobToBlob(pClob           in clob
                  , pCharsetID      in integer default dbms_lob.default_csid
                  , pErrorOnWarning in TFlag default 0) return blob is
-- Function for converting a Clob into a Blob
  vResult       blob;
  vDest_offset  integer := 1;
  vSrc_offset   integer := 1;
  vLang_context integer := dbms_lob.default_lang_ctx;
  vWarning      integer;
begin
  dbms_lob.createtemporary(vResult, true, dbms_lob.call);
  dbms_lob.converttoblob(
    dest_lob     => vResult
  , src_clob     => pClob
  , amount       => dbms_lob.lobmaxsize
  , dest_offset  => vDest_offset
  , src_offset   => vSrc_offset
  , blob_csid    => pCharsetID
  , lang_context => vLang_context
  , warning      => vWarning
  );
  if vWarning <> dbms_lob.no_warning and pErrorOnWarning = 1 then
    raise_application_error(-20001, 'Error during lob conversion : '
      || case
           when vWarning = dbms_lob.warn_inconvertible_char then 'Inconvertible character'
           else 'Warning code '|| vWarning
         end);
  end if;
  return vResult;
end;

function BlobToClob(pBlob           in blob
                  , pCharsetID      in integer default dbms_lob.default_csid
                  , pErrorOnWarning in TFlag default 0) return clob is
-- Function for converting a Blob into a Clob
  vResult       clob;
  vDest_offset  integer := 1;
  vSrc_offset   integer := 1;
  vLang_context integer := dbms_lob.default_lang_ctx;
  vWarning      integer;
begin
  dbms_lob.createtemporary(vResult, true, dbms_lob.call);
  dbms_lob.converttoclob(
    dest_lob     => vResult
  , src_blob     => pBlob
  , amount       => dbms_lob.lobmaxsize
  , dest_offset  => vDest_offset
  , src_offset   => vSrc_offset
  , blob_csid    => pCharsetID
  , lang_context => vLang_context
  , warning      => vWarning
  );
  if vWarning <> dbms_lob.no_warning and pErrorOnWarning = 1 then
    raise_application_error(-20001, 'Error during lob conversion : '
      || case
           when vWarning = dbms_lob.warn_inconvertible_char then 'Inconvertible character'
           else 'Warning code '|| vWarning
         end);
  end if;
  return vResult;
end;

function BFileToBlob(pBFile in out BFile) return blob is
-- Function for reading the file pointed to be a BFile into a blob
  vResult      blob;
  vDest_offset integer := 1;
  vSrc_offset  integer := 1;
begin
  if nvl(BFileLength(pBFile), 0) > 0 then
    dbms_lob.fileopen(pBFile, dbms_lob.file_readonly);
    begin
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      dbms_lob.loadblobfromfile (
        dest_lob      => vResult
      , src_bfile     => pBFile
      , amount        => dbms_lob.lobmaxsize
      , dest_offset   => vDest_offset
      , src_offset    => vSrc_offset
      );
      dbms_lob.fileclose(pBFile);
    exception
      when OTHERS then
        if dbms_lob.fileisopen(pBFile) = 1 then
          dbms_lob.fileclose(pBFile);
          raise;
        end if;
    end;
  end if;
  return vResult;
end;

function FileToBlob(pOraDir varchar2, pFilename varchar2) return blob is
-- Function for reading a file's contents into a blob
  vBFile BFile;
begin
  vBFile := BFilename(pOraDir, pFilename);
  return BFileToBlob(vBFile);
end;

function BFileToClob(pBFile in out BFile) return clob is
-- Function for reading the file pointed to by a BFile into a clob
  vResult       clob;
  vDest_offset  integer := 1;
  vSrc_offset   integer := 1;
  vBFile_csid   number  := 0;
  vLang_context integer := dbms_lob.default_lang_ctx;
  vWarning      integer;
begin
  if nvl(BFileLength(pBFile), 0) > 0 then
    dbms_lob.fileopen(pBFile, dbms_lob.file_readonly);
    begin
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      dbms_lob.loadclobfromfile (
        dest_lob      => vResult
      , src_bfile     => pBFile
      , amount        => dbms_lob.lobmaxsize
      , dest_offset   => vDest_offset
      , src_offset    => vSrc_offset
      , bfile_csid    => vBFile_csid
      , lang_context  => vLang_context
      , warning       => vWarning);
      dbms_lob.fileclose(pBFile);
    exception
      when OTHERS then
        if dbms_lob.fileisopen(pBFile) = 1 then
          dbms_lob.fileclose(pBFile);
          raise;
        end if;
    end;
  end if;
  return vResult;
end;

function FileToClob(pOraDir varchar2, pFilename varchar2) return clob is
-- Function for reading a file into a clob
  vBFile BFile;
begin
  vBFile := BFilename(pOraDir, pFilename);
  return BFileToClob(vBFile);
end;

procedure BlobToFile(pBlob     in blob
                   , pOraDir   in varchar2
                   , pFilename in varchar2) is
-- Routine for writing a blob to a file
  vDestFile utl_file.file_type;
  vPos      pls_integer := 1;
  vAmount   pls_integer := 32767;
  vLen      pls_integer := dbms_lob.getlength(pBlob);
  vBuffer   raw(32767);
begin
  vDestFile := utl_file.fopen(pOraDir, pFilename,  'WB', 32767);
  while vPos <= vLen
  loop
    dbms_lob.read(pBlob, vAmount, vPos, vBuffer);
    utl_file.put_raw(vDestFile, vBuffer, true);
    vPos := vPos + vAmount;
  end loop;
  utl_file.fclose(vDestFile);
exception
  when OTHERS then
    if utl_file.is_open(vDestFile) then
      utl_file.fclose(vDestFile);
    end if;
    raise;
end;

--------------------------------------------------------------------------------
-- Encoding to Base64 routines

function EncodeRaw(pIP raw, pLineSeparators TFlag default 1) return varchar2 is
-- Encodes a raw input of bytes into a Base64 string
-- If pLineSeparators = 0 then any CRLFs will be removed from encoded content
begin
  return case
           when pIP is null then null
           when pLineSeparators = 0 then replace(utl_raw.cast_to_varchar2(utl_encode.base64_encode(pIP)), CRLF, '')  -- Remove line separators that Oracle adds, replace is faster than translate
           else rtrim(utl_raw.cast_to_varchar2(utl_encode.base64_encode(pIP)), CRLF)
         end;
end;

function EncodeString(pIP varchar2, pLineSeparators TFlag default 1) return varchar2 is
-- Encodes a string into a Base64 string
begin
  return EncodeRaw(utl_raw.cast_to_raw(pIP), pLineSeparators);
end;

function EncodeBlob(pIP blob, pLineSeparators TFlag default 1) return clob is
-- Encodes a blob into a Base64 clob
  vOffset  integer     := 1;
  vLen     pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk   varchar2(32767);
  vLineSep varchar2(2) := case when pLineSeparators = 0 then null else CRLF end;
  vResult  clob;
begin
  case
    when vLen = 0 then
      vResult := case when pIP is null then null else empty_clob() end;
    when vLen <= MAX_ENC_CHUNK_LEN then
      vResult := EncodeRaw(pIP, pLineSeparators);
    else
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      for i in 1..ceil(vLen / MAX_ENC_CHUNK_LEN)
      loop
        vChunk := case when i > 1 then vLineSep end || EncodeRaw(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, vOffset), pLineSeparators);
        dbms_lob.writeappend(vResult, length(vChunk), vChunk);
        vOffset := vOffset + MAX_ENC_CHUNK_LEN;
      end loop;
  end case;
  return vResult;
end;

function EncodeClob(pIP clob, pLineSeparators TFlag default 1) return clob is
-- Encodes a clob into a Base64 clob
-- Base64 chunking a clob could result in partial multibyte characters, so it is
-- safer to convert to blob and perfom base64 conversions in the blob byte domain
begin
  return case
           when pIP is null or pIP = empty_clob() then pIP
           else EncodeBlob(ClobToBlob(pIP), pLineSeparators)
         end;
end;

function EncodeBFile(pIP in out BFile, pLineSeparators TFlag default 1) return clob is
-- Encodes a BFile's content into a Base64 clob
begin
  return EncodeBlob(BFileToBlob(pIP), pLineSeparators);
end;

function EncodeFile(pOraDir varchar2, pFilename varchar2, pLineSeparators TFlag default 1) return clob is
-- Encodes the content of a file in an Oracle directory into a Base64 clob
  vBFilename BFile;
begin
  vBFilename := BFilename(pOraDir, pFilename);
  return EncodeBFile(vBFilename, pLineSeparators);
end;

--------------------------------------------------------------------------------
-- Decoding Base64 data routines

function DecodeToRawInternal(pIP varchar2
                           , pRemoveWhitespace TFlag default 1) return raw is
-- Decodes a Base64 encoded string into raw bytes, but with optional whitespace removal
begin
  return case
           when pIP is not null then utl_encode.base64_decode(utl_raw.cast_to_raw(case when pRemoveWhitespace = 0 then pIP else RemoveWhitespace(pIP) end))  -- Translate here removes whitespace
         end;
end;

function DecodeToRaw(pIP varchar2) return raw is
-- Decodes a Base64 encoded string into raw bytes (max 32k bytes)
begin
  return DecodeToRawInternal(pIP);
end;

function DecodeToString(pIP varchar2) return varchar2 is
-- Decodes a Base64 encoded string into a varchar2 string (max 32k bytes)
begin
  return utl_raw.cast_to_varchar2(DecodeToRaw(pIP));
end;

function DecodeToBlob(pIP clob) return blob is
-- Decodes a Base64 encoded clob into a blob
  vOffset    integer     := 1;
  vLen       pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vBuffer    varchar2(32767 byte);
  vModulo    pls_integer;
  vOverflow  varchar2(4 byte);
  vBufferLen pls_integer;
  vAmount    integer := MAX_DEC_CHUNK_LEN;
  vResult    blob;
  procedure AppendChunk(pChunk varchar2) is
    vBufferRaw raw(32767);
  begin
    vBufferRaw := DecodeToRawInternal(pChunk, pRemoveWhitespace => 0);
    dbms_lob.writeappend(vResult, utl_raw.length(vBufferRaw), vBufferRaw);
  end;
begin
  case
    when vLen = 0 then
      vResult := case when pIP is null then null else empty_blob() end;
    when vLen <= MAX_DEC_CHUNK_LEN then
      vResult := DecodeToRaw(pIP);    -- For speed, work with raw no need to chunk
    when vLen > MAX_DEC_CHUNK_LEN then
      dbms_lob.createtemporary(vResult, false, dbms_lob.call);
      while vOffset <= vLen
      loop
        dbms_lob.read(pIP, vAmount, vOffset, vBuffer);
        vBuffer    := RemoveWhitespace(vBuffer);
        vBufferLen := length(vBuffer);
        vModulo    := mod(vBufferLen, 4);   -- 4 chars safely decode into 3 octets, anything remaining is too short for decoding, so overflow
        if vModulo > 0 then
          AppendChunk(vOverflow || substr(vBuffer, 1, vBufferLen - vModulo));
          vOverflow := substr(vBuffer, -vModulo);
        else
          AppendChunk(vBuffer);
          vOverflow := null;
        end if;
        vOffset := vOffset + vAmount;
      end loop;
      if vOverflow is not null then
        AppendChunk(vOverflow);
      end if;
  end case;
  return vResult;
end;

function DecodeToClob(pIP clob) return clob is
-- Decodes a Base64 encoded clob into a clob
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
begin
  return case
           when vLen = 0 then pIP
           when vLen <= MAX_DEC_CHUNK_LEN then DecodeToString(pIP)
           when vLen > MAX_DEC_CHUNK_LEN then BlobToClob(DecodeToBlob(pIP))   -- Conversions outside of MAX_DEC_CHUNK_LEN are chunked, so to protect chunks having partial multibyte chars, we work with blobs
         end;
end;

procedure DecodeToFile(pIP clob, pOraDir varchar2, pFilename varchar2) is
-- Decodes a Base64 encoded clob, saving it into a file in the Oracle directory
begin
  BlobToFile(DecodeToBlob(pIP), pOraDir, pFilename);
end;

end;
/
