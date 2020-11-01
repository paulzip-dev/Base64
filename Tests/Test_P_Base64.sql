-- A test script, which validates the operations of the P_Base64 package
-- Tests here work by encoding and reversing that by decoding and comparing back to the original input  
declare 
  vOraDir    varchar2(30) := 'PAULZIP_DIR';    -- This will be your Oracle directory
  vFileName  varchar2(30) := 'B64Test1.txt';
  vFileName2 varchar2(40) := 'B64Test2.txt';
  vBlob blob;
  vErrors integer := 0;
  IT_STR  constant pls_integer := 1;
  IT_CLOB constant pls_integer := 2;
  IT_BLOB constant pls_integer := 3;
  IT_FILE constant pls_integer := 4;
  function GetStrOfLength(pLen integer) return varchar2 is
    vChunkLen integer := 1000;
    vChunk varchar2(1000);
    vCount integer := pLen;
    vResult varchar2(32767);
  begin
    if vCount > 0 then
      vChunk := dbms_random.string('p', vChunkLen);
      loop
        vResult := vResult || case when vCount >= vChunkLen then vChunk else substr(vChunk, 1, vCount) end;
        vCount := vCount - vChunkLen;
        exit when vCount <= 0;
      end loop;
    end if;
    return vResult;
  end;
  function GetBlobOfLength(pLen integer) return Blob is
    vChunkLen integer := 1000;
    vChunk raw(1000);
    vCount integer := pLen;
    vResult Blob;
  begin
    if coalesce(pLen, 0) > 0 then
      vChunk := DBMS_Crypto.RandomBytes(vChunkLen);
      dbms_lob.createtemporary(vResult, false, dbms_lob.call);
      loop
        dbms_lob.writeappend(vResult, least(vChunkLen, vCount), vChunk);
        vCount := vCount - vChunkLen;
        exit when vCount <= 0;
      end loop;
    end if;
    return case when pLen = 0 then empty_blob() else vResult end;
  end;
  function GetClobOfLength(pLen integer) return clob is
    vChunkLen integer := 1000;
    vChunk varchar2(1000);
    vCount integer := pLen;
    vResult clob;
  begin
    if coalesce(pLen, 0) > 0 then
      vChunk := DBMS_Random.String('P', vChunkLen);
      dbms_lob.createtemporary(vResult, false, dbms_lob.call);
      loop
        dbms_lob.writeappend(vResult, least(vChunkLen, vCount), vChunk);
        vCount := vCount - vChunkLen;
        exit when vCount <= 0;
      end loop;
    end if;
    return case when pLen = 0 then empty_clob() else vResult end;
  end;
  procedure WriteBlob(pDirectory       in varchar2,
                      pFilename        in varchar2,
                      pBlob            in blob,
                      pFileWriteAction in varchar2 default 'WB') is
    vDestFile utl_file.file_type;
    vPos      number := 1;
    vAmount   binary_integer := 32767;
    vBlobLen  number;
    vBuffer   raw(32767);
  begin
    vDestFile := utl_file.fopen(pDirectory, pFilename,  pFileWriteAction, 32767);
    vBlobLen := dbms_lob.getlength(pBlob);
    while vPos < vBlobLen
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
  function ReadBlob(pDirectory in varchar2,
                    pFilename  in varchar2) return blob is
    vDestOffset  integer := 1;
    vSrcOffset   integer := 1;
    vBFile    bfile;
    vBlob     blob;
    function FileLength return pls_integer is
      vExists     boolean;
      vFileLength number;
      vBlocksize  binary_integer;
    begin
      UTL_FILE.FGETATTR(pDirectory, pFilename, vExists, vFileLength, vBlocksize);
      return vFileLength;
    end;
  begin
    if nvl(FileLength, 0) > 0 then
      vBFile := BFilename(pDirectory, pFileName);
      begin
        DBMS_LOB.FileOpen(vBFile, dbms_lob.file_readonly);
        DBMS_LOB.CreateTemporary(vBlob, true, dbms_lob.call);
        DBMS_LOB.LoadBlobFromFile(vBlob,
                                  vBFile,
                                  dbms_lob.lobmaxsize,
                                  vDestOffset,
                                  vSrcOffset);
        DBMS_LOB.FileClose(vBFile);
      exception
        when OTHERS then
          if DBMS_LOB.FileIsOpen(vBFile) = 1 then
            DBMS_LOB.FileClose(vBFile);
          end if;
          raise;
      end;
    end if;
    return vBlob;
  end;
  function FileHash(pOracleDir in varchar2, pFilename in varchar2, pHashFunction PLS_Integer default 2 /* MD5 */) return varchar2 is
  -- Returns the hash of a file, which can be used to identify uniqueness
  -- pHashFunction is one of DBMS_CRYPTO hash function constants
  -- Use RawToHex on result to return as hex string
    vBlob blob;
    vHash raw(64); -- Max hash length from DBMS_CRYPTO currently 512 bits = 64 bytes
  begin
    vBlob := ReadBlob(pOracleDir, pFilename);
    vHash := DBMS_Crypto.Hash(coalesce(vBlob, Empty_Blob()), pHashFunction); -- Null blob is not allowed, empty blob is
    return RawToHex(vHash);
  end;
  function ValuesSame(pIP varchar2, pOP varchar2) return boolean is
  begin
    return (pIP is null and pOP is null) or coalesce(pIP = pOP, False);
  end;
  function ValuesSame(pIP clob, pOP clob) return boolean is
  begin
    return (pIP is null and pOP is null) or (pIP = empty_clob() and pOP = empty_clob()) or
            dbms_lob.compare(pIP, pOP) = 0;
  end;
  function ValuesSame(pIP blob, pOP blob) return boolean is
  begin
    return (pIP is null and pOP is null) or (dbms_lob.GetLength(pIP) = 0 and dbms_lob.GetLength(pOP) = 0) or
            dbms_lob.compare(pIP, pOP) = 0;
  end;
  procedure Assert(pExpr boolean, pMessage varchar2 default null) is
  begin
    if coalesce(pExpr, False) then
      dbms_output.put_line(pMessage ||' - OK');
    else
      dbms_output.put_line(pMessage ||' - Error');
      vErrors := vErrors + 1;
    end if;
  end;
  procedure CheckStr(pIP varchar2) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToString(P_Base64.EncodeString(pIP))), 'varchar2 '||length(pIP));
  end;
  procedure CheckClob(pIP clob) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToClob(P_Base64.EncodeClob(pIP))), 'Clob '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' chars' end);
  end;
  procedure CheckBlob(pIP blob) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToBlob(P_Base64.EncodeBlob(pIP))), 'Blob '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' bytes' end);
  end;
  procedure CheckFile(pIP blob) is
  begin
    WriteBlob(vOraDir, vFileName, pIP, 'WB'); -- Write blob to file
    P_Base64.DecodeToFile(P_Base64.EncodeFile(vOraDir, vFileName), vOraDir, vFileName2); -- Encode file to Base64 and decode it another file
    Assert(ValuesSame(FileHash(vOraDir, vFileName), FileHash(vOraDir, vFileName2)), 'File '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' bytes' end);  -- Compare file hashes
  end;
  procedure CheckItems(pItemType integer, pMinLen integer, pMaxLen integer, pCount integer default null) is
    vStart integer := case when pCount is null then pMinLen else 1 end;
    vEnd   integer := coalesce(pCount, pMaxLen);
    vLen   integer;
  begin
    for n in vStart..vEnd
    loop
      vLen := case when pCount is null then n else round(dbms_random.value(pMinLen, pMaxLen)) end;
      case pItemType
        when IT_STR  then CheckStr (GetStrOfLength (vLen));
        when IT_CLOB then CheckClob(GetClobOfLength(vLen));
        when IT_BLOB then CheckBlob(GetBlobOfLength(vLen));
        when IT_FILE then CheckFile(GetBlobOfLength(vLen));
      end case;
    end loop;
  end;
begin
--------------------------------------------------------------------------------
-- Varchar2
  CheckStr(null);
  CheckStr(GetStrOfLength(1));                                           -- Test lower limit
  CheckItems(IT_STR, pMinLen => 1, pMaxLen => 23829, pCount => 20);      -- Random sample of 20 strings which encode up to 32k (23829 input => 32KB output)
  CheckItems(IT_STR, pMinLen => 23819, pMaxLen => 23829);                -- Test lengths up to and including 32k boundary
--------------------------------------------------------------------------------
-- Clob
  CheckClob(null);
  CheckClob(empty_clob());
  CheckClob(GetClobOfLength(1));                                          -- Test lower limit
  CheckItems(IT_CLOB, pMinLen => 1, pMaxLen => 32767, pCount => 20);      -- Random sample of 20 clobs up to 32k
  CheckItems(IT_CLOB, pMinLen => 32766, pMaxLen => 32777);                -- Test lengths around 32k boundary to check splicing aspect works
  CheckItems(IT_CLOB, pMinLen => 100120, pMaxLen => 200120, pCount => 5); -- Test some larger examples, a random sample of 5
--------------------------------------------------------------------------------
-- Blob
  CheckBlob(null);
  CheckBlob(empty_blob());
  CheckBlob(GetBlobOfLength(1));                                          -- Test lower limit
  CheckItems(IT_BLOB, pMinLen => 1, pMaxLen => 32767, pCount => 20);      -- Random sample of 20 blobs up to 32k
  CheckItems(IT_BLOB, pMinLen => 32766, pMaxLen => 32777);                -- Test lengths around 32k boundary to check splicing aspect works
  CheckItems(IT_BLOB, pMinLen => 151234, pMaxLen => 254321, pCount => 5); -- Test some larger examples, random sample of 5
--------------------------------------------------------------------------------
-- Files
  CheckFile(null);
  CheckFile(empty_blob());
  CheckFile(GetBlobOfLength(1));                                          -- Test lower limit
  CheckItems(IT_FILE, pMinLen => 1, pMaxLen => 32767, pCount => 20);      -- Random sample of 20 files up to 32k
  CheckItems(IT_FILE, pMinLen => 32766, pMaxLen => 32777);                -- Test lengths around 32k boundary to check splicing aspect works
  CheckItems(IT_FILE, pMinLen => 278901, pMaxLen => 378901, pCount => 5); -- Test some larger examples, random sample of 5
  utl_file.fremove (vOraDir, vFileName);
  utl_file.fremove (vOraDir, vFileName2);
--------------------------------------------------------------------------------
  if vErrors > 0 then
    raise_application_error(-20001, 'Errors found = '||vErrors);
  end if;
end;
/