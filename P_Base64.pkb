create or replace package body P_Base64 is

/*
An input chunk size of 23760 converts to 32668 output in Base64, 23760 is modulo
divisible by 48 and 3 which means content will be full lines including CRLF
endings, as it doesn't exceed 327676 it also allows space for us to add a
concatenating CRLF between chunks
*/
MAX_ENC_CHUNK_LEN constant pls_integer := 23760;
MAX_DEC_CHUNK_LEN constant pls_integer := 32764;  -- Divisible by 4
CRLF varchar2(2) := chr(13) || chr(10);

--------------------------------------------------------------------------------

--function EncodeRawToRaw(pIP raw) return raw is
--begin
--  return case
--           when pIP is not null then utl_encode.base64_encode(pIP)
--         end;
--end;

function EncodeRaw(pIP raw) return varchar2 is
begin
  return case
           when pIP is not null then utl_raw.cast_to_varchar2(utl_encode.base64_encode(pIP))
         end;
end;

function EncodeString(pIP varchar2) return varchar2 is
begin
  return EncodeRaw(utl_raw.cast_to_raw(pIP));
end;

function EncodeClob(pIP clob) return clob is
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
  vResult clob;
begin
  case
    when vLen = 0 then
      vResult := pIP;
    when vLen <= MAX_ENC_CHUNK_LEN then
      vResult := EncodeString(pIP);
    else
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      for i in 0..trunc((vLen - 1) / MAX_ENC_CHUNK_LEN)
      loop
        vChunk := case when i > 0 then CRLF end || EncodeString(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, i * MAX_ENC_CHUNK_LEN + 1));
        dbms_lob.writeappend(vResult, length(vChunk), vChunk);
      end loop;
  end case;
  return vResult;
end;

function EncodeBlob(pIP blob) return clob is
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
  vResult clob;
begin
  case
    when vLen = 0 then
      vResult := case when pIP is null then null else empty_clob() end;
    when vLen <= MAX_ENC_CHUNK_LEN then
      vResult := EncodeRaw(pIP);
    else
      dbms_lob.createtemporary(vResult, true, dbms_lob.call);
      for i in 0..trunc((vLen - 1) / MAX_ENC_CHUNK_LEN)
      loop
        vChunk := case when i > 0 then CRLF end || EncodeRaw(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, i * MAX_ENC_CHUNK_LEN + 1));
        dbms_lob.writeappend(vResult, length(vChunk), vChunk);
      end loop;
  end case;
  return vResult;
end;

function EncodeBFile(pIP in out BFile) return clob is
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vChunk varchar2(32767);
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
        vResult := EncodeRaw(dbms_lob.substr(pIP, vLen, 1));
      else
        dbms_lob.createtemporary(vResult, true, dbms_lob.call);
        for i in 0..trunc((vLen - 1) / MAX_ENC_CHUNK_LEN)
        loop
          vChunk := case when i > 0 then CRLF end || EncodeRaw(dbms_lob.substr(pIP, MAX_ENC_CHUNK_LEN, i * MAX_ENC_CHUNK_LEN + 1));
          dbms_lob.writeappend(vResult, length(vChunk), vChunk);
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

function EncodeFile(pOraDir varchar2, pFilename varchar2) return clob is
  vBFilename BFile;
begin
  vBFilename := BFilename(pOraDir, pFilename);
  return EncodeBFile(vBFilename);
end;

--------------------------------------------------------------------------------

function DecodeToRaw(pIP varchar2) return raw is
begin
  return case
           when pIP is not null then utl_encode.base64_decode(utl_raw.cast_to_raw(translate(pIP, 'a'||chr(13)||chr(10), 'a')))  -- Translate here removes CR and LFs
         end;
end;

function DecodeToString(pIP varchar2) return varchar2 is
begin
  return utl_raw.cast_to_varchar2(DecodeToRaw(pIP));
end;

function DecodeToClob(pIP clob) return clob is
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vBufferVarchar2 varchar2(32767 byte);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
  vOffset integer := 1;
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
  vLen pls_integer := coalesce(dbms_lob.getlength(pIP), 0);
  vBufferRaw raw(32767);
  vBufferVarchar2 varchar2(32767 byte);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
  vOffset integer := 1;
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
  vLen pls_integer;
  vFile utl_file.file_type;
  vBuffer varchar2(32767);
  vBufferSize integer := MAX_DEC_CHUNK_LEN;
  vOffset integer := 1;
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

