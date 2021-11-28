create or replace package body P_Base64 is

/*
MAX_ENC_CHUNK_LEN : An input chunk size of 23760 converts to 32668 output in
Base64, 23760 is modulo divisible by 48 and 3 (with no remainder) which means
content will be full lines including CRLF endings, as it doesn't exceed 32767
it also allows space for us to add a concatenating CRLF between chunks

MAX_DEC_CHUNK_LEN : Has to be modulo divisible (with no remainder) for each of :
 4 - as encoding is 4 * 6 bit bytes chunks,
64 - as a terminating line is 64 bytes and without CRLF
66 - as a non terminating line is 64 bytes + CRLF
*/
MAX_ENC_CHUNK_LEN constant pls_integer := 23760; -- Don't change!!
MAX_DEC_CHUNK_LEN constant pls_integer := 14784; -- Don't change!!
CRLF varchar2(2) := chr(13) || chr(10);
WHITESPACE varchar2(6) := ' ' || CRLF || chr(9) || chr(11) || chr(12); -- Whitespace : 32 (Space), 13 (Carriage Return), 10 (Line Feed), 9 (Horizontal Tab), 11 (Vertical Tab), 12 (Form Feed)

--------------------------------------------------------------------------------

function EncodeRaw(pIP raw, pLineSeparators TFlag default 1) return varchar2 is
-- Encodes a raw input of bytes into a Base64 string
-- If pLineSeparators = 0 then any CRLFs will be removed from encoded content
begin
  return case
           when pIP is null then null
           when pLineSeparators = 0 then replace(utl_raw.cast_to_varchar2(utl_encode.base64_encode(pIP)), CRLF, '')  -- Remove line separators that Oracle adds, replace is faster than translate
           else utl_raw.cast_to_varchar2(utl_encode.base64_encode(pIP))
         end;
end;

function EncodeString(pIP varchar2, pLineSeparators TFlag default 1) return varchar2 is
-- Encodes a string into a Base64 string
begin
  return EncodeRaw(utl_raw.cast_to_raw(pIP), pLineSeparators);
end;

function EncodeClob(pIP clob, pLineSeparators TFlag default 1) return clob is
-- Encodes a clob into a Base64 clob
  vOffset integer := 1;
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
  vLineSep varchar2(2) := case when pLineSeparators = 0 then null else CRLF end;
  vResult clob;
begin
  case
    when vLen = 0 then
      vResult := pIP;
    when vLen <= MAX_ENC_CHUNK_LEN then
      vResult := EncodeString(pIP, pLineSeparators);
    else
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      for i in 1..ceil(vLen / MAX_ENC_CHUNK_LEN)
      loop
        vChunk := case when i > 1 then vLineSep end || EncodeString(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, vOffset), pLineSeparators);
        dbms_lob.writeappend(vResult, length(vChunk), vChunk);
        vOffset := vOffset + MAX_ENC_CHUNK_LEN;
      end loop;
  end case;
  return vResult;
end;

function EncodeBlob(pIP blob, pLineSeparators TFlag default 1) return clob is
-- Encodes a blob into a Base64 clob
  vOffset integer := 1;
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
  vLineSep varchar2(2) := case when pLineSeparators = 0 then null else CRLF end;
  vResult clob;
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

function EncodeBFile(pIP in out BFile, pLineSeparators TFlag default 1) return clob is
-- Encodes a BFile's content into a Base64 clob
  vOffset integer := 1;
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
  vLineSep varchar2(2) := case when pLineSeparators = 0 then null else CRLF end;
  vResult clob;
begin
  if dbms_lob.isopen(pIP) = 0 then
    dbms_lob.fileopen(pIP, dbms_lob.file_readonly);
  end if;
  begin
    case
      when vLen = 0 then
        null;
      when vLen <= MAX_ENC_CHUNK_LEN then
        vResult := EncodeRaw(dbms_lob.substr(pIP, vLen, 1), pLineSeparators);
      else
        dbms_lob.createtemporary(vResult, true, dbms_lob.call);
        for i in 1..ceil(vLen / MAX_ENC_CHUNK_LEN)
        loop
          vChunk := case when i > 1 then vLineSep end || EncodeRaw(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, vOffset), pLineSeparators);
          dbms_lob.writeappend(vResult, length(vChunk), vChunk);
          vOffset := vOffset + MAX_ENC_CHUNK_LEN;
        end loop;
    end case;
    if dbms_lob.isopen(pIP) = 1 then
      dbms_lob.fileclose(pIP);
    end if;
  exception
    when OTHERS then
      if dbms_lob.isopen(pIP) = 1 then
        dbms_lob.fileclose(pIP);
      end if;
      raise;
  end;
  return vResult;
end;

function EncodeFile(pOraDir varchar2, pFilename varchar2, pLineSeparators TFlag default 1) return clob is
-- Encodes the content of a file in an Oracle directory into a Base64 clob
  vBFilename BFile;
begin
  vBFilename := BFilename(pOraDir, pFilename);
  return EncodeBFile(vBFilename, pLineSeparators);
end;

--------------------------------------------------------------------------------

function DecodeToRaw(pIP varchar2) return raw is
-- Decodes a Base64 encoded string into raw bytes (max 32k bytes)
begin
  return case
           when pIP is not null then utl_encode.base64_decode(utl_raw.cast_to_raw(translate(pIP, 'a'||WHITESPACE, 'a')))  -- Translate here removes whitespace
         end;
end;

function DecodeToString(pIP varchar2) return varchar2 is
-- Decodes a Base64 encoded string into a varchar2 string (max 32k bytes)
begin
  return utl_raw.cast_to_varchar2(DecodeToRaw(pIP));
end;

function DecodeToClob(pIP clob) return clob is
-- Decodes a Base64 encoded clob into a clob
  vOffset integer := 1;
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vBufferVarchar2 varchar2(32767 byte);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
  vResult clob;
begin
  case
    when vLen = 0 then
      vResult := pIP;
    when vLen <= MAX_DEC_CHUNK_LEN then
      vResult := DecodeToString(pIP);
    when vLen > MAX_DEC_CHUNK_LEN then
      dbms_lob.createtemporary(vResult, false, dbms_lob.call);
      for i in 1..ceil(vLen / vBufferSize)
      loop
        dbms_lob.read(pIP, vBufferSize, vOffset, vBufferVarchar2);
        vBufferVarchar2 := DecodeToString(vBufferVarchar2);
        dbms_lob.writeappend(vResult, length(vBufferVarchar2), vBufferVarchar2);
        vOffset := vOffset + vBufferSize;
      end loop;
  end case;
  return vResult;
end;

function DecodeToBlob(pIP clob) return blob is
-- Decodes a Base64 encoded clob into a blob
  vOffset integer := 1;
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vBufferRaw raw(32767);
  vBufferVarchar2 varchar2(32767 byte);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
  vResult blob;
begin
  case
    when vLen = 0 then
      vResult := case when pIP is null then null else empty_blob() end;
    when vLen <= MAX_DEC_CHUNK_LEN then
      vResult := DecodeToRaw(pIP);
    when vLen > MAX_DEC_CHUNK_LEN then
      dbms_lob.createtemporary(vResult, false, dbms_lob.call);
      for i in 1..ceil(vLen / vBufferSize)
      loop
        dbms_lob.read(pIP, vBufferSize, vOffset, vBufferVarchar2);
        vBufferRaw := DecodeToRaw(vBufferVarchar2);
        dbms_lob.writeappend(vResult, utl_raw.length(vBufferRaw), vBufferRaw);
        vOffset := vOffset + vBufferSize;
      end loop;
  end case;
  return vResult;
end;

procedure DecodeToFile(pIP clob, pOraDir varchar2, pFilename varchar2) is
-- Decodes a Base64 encoded clob, saving it into a file in the Oracle directory
  vOffset integer := 1;
  vLen pls_integer;
  vFile utl_file.file_type;
  vBuffer varchar2(32767);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
begin
  vFile := utl_file.fopen(pOraDir, pFilename, 'wb', 32767);
  vLen  := dbms_lob.getlength(pIP);
  while vOffset <= vLen
  loop
    dbms_lob.read(pIP, vBufferSize, vOffset, vBuffer);
    utl_file.put_raw(vFile, DecodeToRaw(vBuffer), true);
    vOffset := vOffset + vBufferSize;
  end loop;
  utl_file.fclose(vFile);
exception
  when OTHERS then
    if utl_file.is_open(vFile) then
      utl_file.fclose(vFile);
    end if;
    raise;
end;

end;
/

