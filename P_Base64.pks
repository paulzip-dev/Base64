create or replace package P_Base64 is

/*
By Paul Scott - October 2020
Oracle's Base64 routines in UTL_ENCODE will only process a maximum of 32K bytes,
so this supplements those for sizes above that.

With Base64 encoding, 3 input bytes (using 8 bits) get converted into 4 bytes
(as only 6 bits of each byte are used). Oracle processes 64 byte input chunks
into 48 bytes lines. Oracle adds a carriage return + line feed pair (CRLF)
between each of these.
*/

subtype TFlag is pls_integer range 0..1;

function  EncodeString(pIP varchar2, pLineSeparators TFlag default 1) return varchar2;
function  EncodeRaw   (pIP raw, pLineSeparators TFlag default 1) return varchar2;
function  EncodeClob  (pIP clob, pLineSeparators TFlag default 1) return clob;
function  EncodeBlob  (pIP blob, pLineSeparators TFlag default 1) return clob;
function  EncodeBFile (pIP in out BFile, pLineSeparators TFlag default 1) return clob;
function  EncodeFile  (pOraDir varchar2, pFilename varchar2, pLineSeparators TFlag default 1) return clob;

function  DecodeToRaw   (pIP varchar2) return raw;
function  DecodeToString(pIP varchar2) return varchar2;
function  DecodeToClob  (pIP clob) return clob;
function  DecodeToBlob  (pIP clob) return blob;
procedure DecodeToFile  (pIP clob, pOraDir varchar2, pFilename varchar2);

end;
/