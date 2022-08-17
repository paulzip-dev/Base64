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
  function FileHash(pOracleDir in varchar2, pFilename in varchar2, pHashFunction PLS_Integer default 2 /* MD5 */) return varchar2 is
  -- Returns the hash of a file, which can be used to identify uniqueness
  -- pHashFunction is one of DBMS_CRYPTO hash function constants
  -- Use RawToHex on result to return as hex string
    vBlob blob;
    vHash raw(64); -- Max hash length from DBMS_CRYPTO currently 512 bits = 64 bytes
  begin
    vBlob := P_Base64.FileToBlob(pOracleDir, pFilename);
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
  procedure CheckStr(pIP varchar2, pLineSeparators integer) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToString(P_Base64.EncodeString(pIP, pLineSeparators))), 'varchar2 '||length(pIP)||', pLineSeparators = '||pLineSeparators);
  end;
  procedure CheckClob(pIP clob, pLineSeparators integer) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToClob(P_Base64.EncodeClob(pIP, pLineSeparators))), 'Clob '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' chars' end||', pLineSeparators = '||pLineSeparators);
  end;
  procedure CheckBlob(pIP blob, pLineSeparators integer) is
  begin
    Assert(ValuesSame(pIP, P_Base64.DecodeToBlob(P_Base64.EncodeBlob(pIP, pLineSeparators))), 'Blob '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' bytes' end||', pLineSeparators = '||pLineSeparators);
  end;
  procedure CheckFile(pIP blob, pLineSeparators integer) is
  begin
    P_Base64.BlobToFile(pIP, vOraDir, vFileName); -- Write blob to file
    P_Base64.DecodeToFile(P_Base64.EncodeFile(vOraDir, vFileName, pLineSeparators), vOraDir, vFileName2); -- Encode file to Base64 and decode it another file
    Assert(ValuesSame(FileHash(vOraDir, vFileName), FileHash(vOraDir, vFileName2)), 'File '||case when pIP is null then '{null}' else to_char(length(pIP)) || ' bytes' end||', pLineSeparators = '||pLineSeparators);  -- Compare file hashes
  end;
  procedure CheckItems(pItemType integer, pMinLen integer, pMaxLen integer, pCount integer default null, pLineSeparators integer) is
    vStart integer := case when pCount is null then pMinLen else 1 end;
    vEnd   integer := coalesce(pCount, pMaxLen);
    vLen   integer;
  begin
    for n in vStart..vEnd
    loop
      vLen := case when pCount is null then n else round(dbms_random.value(pMinLen, pMaxLen)) end;
      case pItemType
        when IT_STR  then CheckStr (GetStrOfLength (vLen), pLineSeparators);
        when IT_CLOB then CheckClob(GetClobOfLength(vLen), pLineSeparators);
        when IT_BLOB then CheckBlob(GetBlobOfLength(vLen), pLineSeparators);
        when IT_FILE then CheckFile(GetBlobOfLength(vLen), pLineSeparators);
      end case;
    end loop;
  end;
begin
  for vLineSeparators in 0..1
  loop
  --------------------------------------------------------------------------------
  -- Varchar2
    dbms_output.put_line('--- Varchar2 Tests ---');
    CheckStr(null, vLineSeparators);
    CheckStr(GetStrOfLength(1), vLineSeparators);                                                              -- Test lower limit
    CheckItems(IT_STR, pMinLen => 1, pMaxLen => 23829, pCount => 20, pLineSeparators => vLineSeparators);      -- Random sample of 20 strings which encode up to 32k (23829 input => 32KB output)
    CheckItems(IT_STR, pMinLen => 23819, pMaxLen => 23829, pLineSeparators => vLineSeparators);                -- Test lengths up to and including 32k boundary
  --------------------------------------------------------------------------------
  -- Clob
    dbms_output.put_line('--- Clob Tests ---');
    CheckClob(null, vLineSeparators);
    CheckClob(empty_clob(), vLineSeparators);
    CheckClob(GetClobOfLength(1), vLineSeparators);                                                             -- Test lower limit
    CheckItems(IT_CLOB, pMinLen => 1, pMaxLen => 32767, pCount => 20, pLineSeparators => vLineSeparators);      -- Random sample of 20 clobs up to 32k
    CheckItems(IT_CLOB, pMinLen => 32766, pMaxLen => 32777, pLineSeparators => vLineSeparators);                -- Test lengths around 32k boundary to check splicing aspect works
    CheckItems(IT_CLOB, pMinLen => 100120, pMaxLen => 200120, pCount => 5, pLineSeparators => vLineSeparators); -- Test some larger examples, a random sample of 5
  --------------------------------------------------------------------------------
  -- Blob
    dbms_output.put_line('--- Blob Tests ---');
    CheckBlob(null, vLineSeparators);
    CheckBlob(empty_blob(), vLineSeparators);
    CheckBlob(GetBlobOfLength(1), vLineSeparators);                                                             -- Test lower limit
    CheckItems(IT_BLOB, pMinLen => 1, pMaxLen => 32767, pCount => 20, pLineSeparators => vLineSeparators);      -- Random sample of 20 blobs up to 32k
    CheckItems(IT_BLOB, pMinLen => 32766, pMaxLen => 32777, pLineSeparators => vLineSeparators);                -- Test lengths around 32k boundary to check splicing aspect works
    CheckItems(IT_BLOB, pMinLen => 151234, pMaxLen => 254321, pCount => 5, pLineSeparators => vLineSeparators); -- Test some larger examples, random sample of 5
  --------------------------------------------------------------------------------
  -- Files
    dbms_output.put_line('--- File Tests ---');
    CheckFile(null, vLineSeparators);
    CheckFile(empty_blob(), vLineSeparators);
    CheckFile(GetBlobOfLength(1), vLineSeparators);                                                             -- Test lower limit
    CheckItems(IT_FILE, pMinLen => 1, pMaxLen => 32767, pCount => 20, pLineSeparators => vLineSeparators);      -- Random sample of 20 files up to 32k
    CheckItems(IT_FILE, pMinLen => 32766, pMaxLen => 32777, pLineSeparators => vLineSeparators);                -- Test lengths around 32k boundary to check splicing aspect works
    CheckItems(IT_FILE, pMinLen => 278901, pMaxLen => 378901, pCount => 5, pLineSeparators => vLineSeparators); -- Test some larger examples, random sample of 5
    utl_file.fremove (vOraDir, vFileName);
    utl_file.fremove (vOraDir, vFileName2);
  --------------------------------------------------------------------------------
  end loop;
  if vErrors > 0 then
    raise_application_error(-20001, 'Errors found = '||vErrors);
  end if;
end;
/