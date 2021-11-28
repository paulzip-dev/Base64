# Base64 Encoding and Decoding Routines PL/SQL Package for Oracle

Base64 is a group of binary-to-text encoding schemes that represent binary data in an ASCII string format by translating it into a radix-64 representation.  Base64 encoding is typically used to carry data stored in binary formats across channels that only reliably support text content.

Oracle's provides some Base64 routines in UTL_ENCODE, but these will only process RAWs and up to a maximum of 32KB.  This package supplements these restrictions by adding the following :
* Support for data types other than RAW
* Support for sizes above 32KB
* Support for files

## How to Install :

Compile package spec **P_Base64.pks** and package body **P_Base64.pkb**

## Base64 Encoding routines :

Function / Procedure | Operation 
--------------------------------------------------------|----------------------------------------------------------------
`function  EncodeString(pIP varchar2) return varchar2;` | Encodes a varchar2 string into a Base64 varchar2 string, limited to 32KB.
`function  EncodeRaw   (pIP raw) return varchar2;` | Encodes a raw bytes input into a Base64 varchar2 string, limited to 32KB.
`function  EncodeClob  (pIP clob) return clob;` | Encodes a clob input into a Base64 clob.
`function  EncodeBlob  (pIP blob) return clob;` | Encodes a blob input into a Base64 clob.
`function  EncodeBFile (pIP in out BFile) return clob;` | Encodes a bfile input into a Base64 clob.
`function  EncodeFile  (pOraDir varchar2, pFilename varchar2) return clob;` | Encodes the contents of a file into a Base64 clob.

## Base64 Decoding routines :

Function / Procedure | Operation 
--------------------------------------------------------|----------------------------------------------------------------
`function  DecodeToRaw   (pIP varchar2) return raw;` | Decodes a Base64 encoded string into raw bytes, limited to 32k
`function  DecodeToString(pIP varchar2) return varchar2;` | Decodes a Base64 encoded string into a varchar2 string, limited to 32k
`function  DecodeToClob  (pIP clob) return clob;` | Decodes a Base64 encoded clob into a clob
`function  DecodeToBlob  (pIP clob) return blob;` | Decodes a Base64 encoded clob into a blob
`procedure DecodeToFile  (pIP clob, pOraDir varchar2, pFilename varchar2);` | Decodes a Base64 encoded clob into a file
