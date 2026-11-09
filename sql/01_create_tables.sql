/* Northfield Lab Supply Co. - OTC reporting database
   SQL Server 2019+ (also runs on Azure SQL)
   Table and column names follow SAP SD so the model reads like a real extract. */

IF DB_ID('OTC_Portfolio') IS NULL
    CREATE DATABASE OTC_Portfolio;
GO
USE OTC_Portfolio;
GO
IF SCHEMA_ID('otc') IS NULL
    EXEC('CREATE SCHEMA otc');
GO

DROP TABLE IF EXISTS otc.VBRP, otc.VBRK, otc.LIPS, otc.LIKP, otc.VBEP, otc.VBAP, otc.VBAK,
                     otc.CUSTOMER_CREDIT, otc.MARA, otc.KNA1;
GO

-- Customer master (general data)
CREATE TABLE otc.KNA1 (
    KUNNR   VARCHAR(10)  NOT NULL PRIMARY KEY,   -- customer number
    NAME1   VARCHAR(60)  NOT NULL,
    ORT01   VARCHAR(40)  NULL,                    -- city
    REGIO   VARCHAR(3)   NULL,                    -- state
    LAND1   VARCHAR(3)   NULL,
    KTOKD   VARCHAR(4)   NULL,                    -- account group
    REGION  VARCHAR(20)  NULL                     -- sales region (custom attribute)
);

-- Credit data. In S/4HANA this lives in FSCM credit management (UKMBP_CMS_SGM).
CREATE TABLE otc.CUSTOMER_CREDIT (
    KUNNR          VARCHAR(10)   NOT NULL PRIMARY KEY,
    CREDIT_SEGMENT VARCHAR(10)   NOT NULL,
    CREDIT_LIMIT   DECIMAL(15,2) NOT NULL,
    RISK_CLASS     VARCHAR(10)   NOT NULL,
    WAERS          VARCHAR(5)    NOT NULL
);

-- Material master (MARA + MAKT text, list price simplified)
CREATE TABLE otc.MARA (
    MATNR      VARCHAR(18)   NOT NULL PRIMARY KEY,
    MAKTX      VARCHAR(40)   NOT NULL,
    MATKL      VARCHAR(9)    NOT NULL,            -- material group
    MEINS      VARCHAR(3)    NOT NULL,
    LIST_PRICE DECIMAL(15,2) NOT NULL
);

-- Sales order header
CREATE TABLE otc.VBAK (
    VBELN               VARCHAR(10)   NOT NULL PRIMARY KEY,
    ERDAT               DATE          NOT NULL,   -- created on
    AUART               VARCHAR(4)    NOT NULL,   -- order type
    VKORG               VARCHAR(4)    NOT NULL,
    VTWEG               VARCHAR(2)    NOT NULL,
    SPART               VARCHAR(2)    NOT NULL,
    KUNNR               VARCHAR(10)   NOT NULL REFERENCES otc.KNA1(KUNNR),
    NETWR               DECIMAL(15,2) NOT NULL,
    WAERK               VARCHAR(5)    NOT NULL,
    CMGST               CHAR(1)       NULL,       -- credit status: A passed, B blocked, D released
    CREDIT_RELEASE_DATE DATE          NULL,
    LIFSK               VARCHAR(2)    NULL,       -- delivery block
    FAKSK               VARCHAR(2)    NULL        -- billing block
);

-- Sales order item
CREATE TABLE otc.VBAP (
    VBELN  VARCHAR(10)   NOT NULL REFERENCES otc.VBAK(VBELN),
    POSNR  VARCHAR(6)    NOT NULL,
    MATNR  VARCHAR(18)   NOT NULL REFERENCES otc.MARA(MATNR),
    KWMENG DECIMAL(13,3) NOT NULL,                -- order quantity
    VRKME  VARCHAR(3)    NOT NULL,
    NETPR  DECIMAL(15,2) NOT NULL,                -- net price per unit
    NETWR  DECIMAL(15,2) NOT NULL,
    WERKS  VARCHAR(4)    NOT NULL,
    ABGRU  VARCHAR(2)    NULL,                    -- reason for rejection
    PRIMARY KEY (VBELN, POSNR)
);

-- Schedule lines (requested date and confirmed quantity)
CREATE TABLE otc.VBEP (
    VBELN VARCHAR(10)   NOT NULL,
    POSNR VARCHAR(6)    NOT NULL,
    ETENR VARCHAR(4)    NOT NULL,
    EDATU DATE          NOT NULL,                 -- requested delivery date
    WMENG DECIMAL(13,3) NOT NULL,                 -- requested quantity
    BMENG DECIMAL(13,3) NOT NULL,                 -- confirmed quantity
    PRIMARY KEY (VBELN, POSNR, ETENR),
    FOREIGN KEY (VBELN, POSNR) REFERENCES otc.VBAP(VBELN, POSNR)
);

-- Outbound delivery header
CREATE TABLE otc.LIKP (
    VBELN     VARCHAR(10) NOT NULL PRIMARY KEY,
    ERDAT     DATE        NOT NULL,
    LFART     VARCHAR(4)  NOT NULL,
    VSTEL     VARCHAR(4)  NOT NULL,               -- shipping point
    KUNAG     VARCHAR(10) NOT NULL,
    LFDAT     DATE        NOT NULL,               -- delivery date (requested)
    WADAT_IST DATE        NULL                    -- actual goods issue date
);

-- Outbound delivery item
CREATE TABLE otc.LIPS (
    VBELN VARCHAR(10)   NOT NULL REFERENCES otc.LIKP(VBELN),
    POSNR VARCHAR(6)    NOT NULL,
    MATNR VARCHAR(18)   NOT NULL,
    LFIMG DECIMAL(13,3) NOT NULL,                 -- delivered quantity
    VRKME VARCHAR(3)    NOT NULL,
    VGBEL VARCHAR(10)   NOT NULL,                 -- reference sales order
    VGPOS VARCHAR(6)    NOT NULL,
    PRIMARY KEY (VBELN, POSNR)
);

-- Billing header
CREATE TABLE otc.VBRK (
    VBELN VARCHAR(10)   NOT NULL PRIMARY KEY,
    FKART VARCHAR(4)    NOT NULL,                 -- F2 invoice, S1 cancellation
    FKDAT DATE          NOT NULL,
    KUNRG VARCHAR(10)   NOT NULL,                 -- payer
    NETWR DECIMAL(15,2) NOT NULL,
    WAERK VARCHAR(5)    NOT NULL,
    FKSTO CHAR(1)       NULL,                     -- X = cancelled
    SFAKN VARCHAR(10)   NULL                      -- cancelled billing doc (on S1)
);

-- Billing item
CREATE TABLE otc.VBRP (
    VBELN VARCHAR(10)   NOT NULL REFERENCES otc.VBRK(VBELN),
    POSNR VARCHAR(6)    NOT NULL,
    MATNR VARCHAR(18)   NOT NULL,
    FKIMG DECIMAL(13,3) NOT NULL,
    VRKME VARCHAR(3)    NOT NULL,
    NETWR DECIMAL(15,2) NOT NULL,
    VGBEL VARCHAR(10)   NOT NULL,                 -- reference delivery
    VGPOS VARCHAR(6)    NOT NULL,
    AUBEL VARCHAR(10)   NOT NULL,                 -- sales order
    AUPOS VARCHAR(6)    NOT NULL,
    PRIMARY KEY (VBELN, POSNR)
);

CREATE INDEX IX_LIPS_VGBEL ON otc.LIPS (VGBEL, VGPOS);
CREATE INDEX IX_VBRP_AUBEL ON otc.VBRP (AUBEL, AUPOS);
GO
